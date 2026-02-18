import Foundation
import SwiftUI

/// ViewModel for managing scenario generation and state
@Observable
@MainActor
final class ScenarioViewModel {
    // Configuration state
    var theme: String = ""
    var numberOfScenarios: Int = 5
    var includeDramaticStakes: Bool = false

    // Progress state
    private(set) var isGenerating: Bool = false
    private(set) var progressMessage: String = ""
    var error: String?

    // Results
    private(set) var existingScenarios: [Scenario] = []
    private(set) var generatedScenarios: [Scenario] = []

    // Editing state
    var editingScenario: Scenario?
    var editedTitle: String = ""
    var editedSituation: String = ""
    var editedObjective: String = ""

    // Dependencies
    private let repository: CombinedCharacterRepository
    private var scenarioService: ScenarioGenerationService?
    private var character: Character?
    var onCharacterUpdated: ((Character) -> Void)?
    var jobManager: BackgroundJobManager?

    // Computed properties
    var allScenarios: [Scenario] {
        existingScenarios + generatedScenarios
    }

    var activeScenario: Scenario? {
        allScenarios.first(where: { $0.isActive })
    }

    var hasScenarios: Bool {
        !allScenarios.isEmpty
    }

    var totalCount: Int {
        allScenarios.count
    }

    var hasUnsavedChanges: Bool {
        !generatedScenarios.isEmpty
    }

    // MARK: - Initialization

    init(character: Character?, apiKeyManager: APIKeyManager, repository: CombinedCharacterRepository) {
        self.character = character
        self.repository = repository

        // Initialize services if we have an API key
        if let openAIKey = apiKeyManager.getAPIKey(for: .openAI) {
            self.scenarioService = ScenarioGenerationService(openAIApiKey: openAIKey)
        }

        // Load existing scenarios
        if let character = character {
            Task {
                await loadExisting(from: character)
            }
        }
    }

    // MARK: - Load Existing

    func loadExisting(from character: Character) async {
        self.character = character

        // Look for scenarios.jsonl in knowledge files
        guard let scenarioFile = character.knowledgeFiles.first(where: { $0.fileName == "scenarios.jsonl" }),
              let service = scenarioService else {
            existingScenarios = []
            return
        }

        existingScenarios = await service.parseJSONL(scenarioFile.content)
    }

    // MARK: - Generate Scenarios

    func generate() async {
        guard let service = scenarioService else {
            error = "OpenAI API key not configured. Please add it in Settings."
            return
        }

        guard let character = character else {
            error = "No character selected"
            return
        }

        isGenerating = true
        error = nil
        progressMessage = "Starting generation..."

        let jobId = jobManager?.startJob(type: .scenarioGeneration, characterName: character.name)

        let config = ScenarioGenerationConfig(
            theme: theme,
            numberOfScenarios: numberOfScenarios,
            includeDramaticStakes: includeDramaticStakes
        )

        do {
            let scenarios = try await service.generateScenarios(
                characterId: character.id,
                characterName: character.name,
                personaContent: character.markdownContent,
                systemPromptType: character.systemPromptType,
                config: config,
                onProgress: { [weak self] message in
                    Task { @MainActor in
                        self?.progressMessage = message
                        if let jobId = jobId {
                            self?.jobManager?.updateProgress(jobId: jobId, message: message)
                        }
                    }
                }
            )

            generatedScenarios.append(contentsOf: scenarios)
            progressMessage = "Generated \(scenarios.count) scenarios (\(allScenarios.count) total)"

            // Auto-save
            try await save()

            if let jobId = jobId {
                jobManager?.completeJob(jobId: jobId)
            }

        } catch {
            self.error = error.localizedDescription
            if let jobId = jobId {
                jobManager?.failJob(jobId: jobId, error: error.localizedDescription)
            }
        }

        isGenerating = false
    }

    // MARK: - Activate/Deactivate Scenario

    func activateScenario(_ scenario: Scenario) async {
        // Deactivate all scenarios first
        existingScenarios = existingScenarios.map { s in
            var updated = s
            updated.isActive = false
            return updated
        }
        generatedScenarios = generatedScenarios.map { s in
            var updated = s
            updated.isActive = false
            return updated
        }

        // Activate the selected scenario
        if let index = existingScenarios.firstIndex(where: { $0.id == scenario.id }) {
            existingScenarios[index].isActive = true
        } else if let index = generatedScenarios.firstIndex(where: { $0.id == scenario.id }) {
            generatedScenarios[index].isActive = true
        }

        // Save changes
        do {
            try await save()
        } catch {
            self.error = "Failed to save: \(error.localizedDescription)"
        }
    }

    func deactivateScenario(_ scenario: Scenario) async {
        if let index = existingScenarios.firstIndex(where: { $0.id == scenario.id }) {
            existingScenarios[index].isActive = false
        } else if let index = generatedScenarios.firstIndex(where: { $0.id == scenario.id }) {
            generatedScenarios[index].isActive = false
        }

        do {
            try await save()
        } catch {
            self.error = "Failed to save: \(error.localizedDescription)"
        }
    }

    func deactivateAll() async {
        existingScenarios = existingScenarios.map { s in
            var updated = s
            updated.isActive = false
            return updated
        }
        generatedScenarios = generatedScenarios.map { s in
            var updated = s
            updated.isActive = false
            return updated
        }

        do {
            try await save()
        } catch {
            self.error = "Failed to save: \(error.localizedDescription)"
        }
    }

    // MARK: - Add/Delete/Regenerate

    func addScenario(title: String, currentSituation: String, liveObjective: String) {
        guard let character = character else { return }

        let scenario = Scenario(
            characterId: character.id,
            theme: "User Created",
            title: title,
            currentSituation: currentSituation,
            liveObjective: liveObjective,
            source: .userCreated
        )

        generatedScenarios.append(scenario)

        Task {
            try? await save()
        }
    }

    func deleteScenario(_ scenario: Scenario) {
        existingScenarios.removeAll { $0.id == scenario.id }
        generatedScenarios.removeAll { $0.id == scenario.id }

        Task {
            try? await save()
        }
    }

    func deleteAllScenarios() {
        existingScenarios = []
        generatedScenarios = []

        Task {
            try? await save()
        }
    }

    func regenerateScenario(_ scenario: Scenario) async {
        guard let service = scenarioService,
              let character = character else {
            error = "Cannot regenerate: service or character not available"
            return
        }

        do {
            let newScenario = try await service.regenerateScenario(
                scenario: scenario,
                characterName: character.name,
                personaContent: character.markdownContent
            )

            // Replace the old scenario with the new one
            if let index = existingScenarios.firstIndex(where: { $0.id == scenario.id }) {
                existingScenarios[index] = newScenario
            } else if let index = generatedScenarios.firstIndex(where: { $0.id == scenario.id }) {
                generatedScenarios[index] = newScenario
            }

            try await save()

        } catch {
            self.error = "Failed to regenerate: \(error.localizedDescription)"
        }
    }

    // MARK: - Editing

    func startEditing(_ scenario: Scenario) {
        editingScenario = scenario
        editedTitle = scenario.title
        editedSituation = scenario.currentSituation
        editedObjective = scenario.liveObjective
    }

    func saveEditedScenario() {
        guard let editing = editingScenario else { return }

        let updated = Scenario(
            id: editing.id,
            characterId: editing.characterId,
            theme: editing.theme,
            title: editedTitle,
            currentSituation: editedSituation,
            liveObjective: editedObjective,
            source: editing.source,
            isActive: editing.isActive,
            createdAt: editing.createdAt
        )

        if let index = existingScenarios.firstIndex(where: { $0.id == editing.id }) {
            existingScenarios[index] = updated
        } else if let index = generatedScenarios.firstIndex(where: { $0.id == editing.id }) {
            generatedScenarios[index] = updated
        }

        editingScenario = nil

        Task {
            try? await save()
        }
    }

    func cancelEditing() {
        editingScenario = nil
        editedTitle = ""
        editedSituation = ""
        editedObjective = ""
    }

    // MARK: - Apply Scenario to Persona

    func applyScenario(_ scenario: Scenario) async {
        guard var character = character else { return }

        // Replace both Current Situation and Live Objective in markdownContent
        replaceSection(in: &character.markdownContent, sectionName: "Current Situation", newContent: scenario.currentSituation)
        replaceSection(in: &character.markdownContent, sectionName: "Live Objective", newContent: scenario.liveObjective)

        self.character = character

        do {
            try await repository.saveCharacter(character)
            onCharacterUpdated?(character)
            progressMessage = "Applied \"\(scenario.title)\" to persona"
        } catch {
            self.error = "Failed to save: \(error.localizedDescription)"
        }
    }

    private func replaceSection(in content: inout String, sectionName: String, newContent: String) {
        let pattern = "###\\s*\(NSRegularExpression.escapedPattern(for: sectionName))\\s*\\n[\\s\\S]*?(?=\\n###|\\n##|$)"

        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            content += "\n\n### \(sectionName)\n\(newContent)"
            return
        }

        let nsString = content as NSString
        let range = NSRange(location: 0, length: nsString.length)
        let matches = regex.matches(in: content, range: range)

        if let match = matches.first {
            let replacement = "### \(sectionName)\n\(newContent)"
            content = nsString.replacingCharacters(in: match.range, with: replacement)
        } else {
            content += "\n\n### \(sectionName)\n\(newContent)"
        }
    }

    // MARK: - Save

    func save() async throws {
        guard var character = character,
              let service = scenarioService else { return }

        let allToSave = allScenarios
        let jsonl = await service.scenariosToJSONL(allToSave)

        let fileName = "scenarios.jsonl"

        let updatedFile = try await repository.createKnowledgeFile(
            for: character,
            fileName: fileName,
            content: jsonl
        )

        // Update local character with new knowledge file
        if let index = character.knowledgeFiles.firstIndex(where: { $0.fileName == fileName }) {
            character.knowledgeFiles[index] = updatedFile
        } else {
            character.knowledgeFiles.append(updatedFile)
        }
        self.character = character
        onCharacterUpdated?(character)

        // Move generated to existing after save
        existingScenarios = allToSave
        generatedScenarios = []
    }

    // MARK: - Export

    func exportPlainText() -> String {
        var text = "# Scenarios for \(character?.name ?? "Character")\n\n"

        for (index, scenario) in allScenarios.enumerated() {
            text += "## \(index + 1). \(scenario.title)\n"
            text += "Theme: \(scenario.theme)\n"
            text += "Source: \(scenario.source.displayName)\n"
            if scenario.isActive {
                text += "Status: ACTIVE\n"
            }
            text += "\n### Current Situation\n\(scenario.currentSituation)\n"
            text += "\n### Live Objective\n\(scenario.liveObjective)\n"
            text += "\n---\n\n"
        }

        return text
    }
}
