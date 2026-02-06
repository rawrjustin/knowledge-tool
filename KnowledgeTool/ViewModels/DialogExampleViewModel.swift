import Foundation
import SwiftUI

/// ViewModel for managing dialog example generation
@MainActor
@Observable
final class DialogExampleViewModel {
    // MARK: - State

    /// Selected categories for generation
    var selectedCategoryIds: Set<String> = Set(DialogCategories.coreCategoryIds)

    /// Additional tone guidance
    var toneGuidance: String = ""

    /// Style notes for generation
    var styleNotes: String = ""

    /// Whether to extract from transcripts
    var useTranscripts: Bool = true

    /// Whether to research real quotes (for real people)
    var researchQuotes: Bool = true

    /// Target number of examples
    var targetExamples: Int = 30

    // MARK: - Progress State

    /// Whether generation is in progress
    private(set) var isGenerating: Bool = false

    /// Current progress message
    private(set) var progressMessage: String = ""

    /// Error message if any
    var error: String?

    // MARK: - Results

    /// Generated examples (not yet saved)
    private(set) var generatedExamples: [DialogExample] = []

    /// Existing examples (loaded from character)
    private(set) var existingExamples: [DialogExample] = []

    /// Example currently being edited
    var editingExample: DialogExample?

    /// Edited dialog text
    var editedDialogText: String = ""

    // MARK: - Dependencies

    private let repository: CombinedCharacterRepository
    private var dialogService: DialogExampleService?
    private var character: Character?

    // MARK: - Computed Properties

    /// All examples (existing + generated)
    var allExamples: [DialogExample] {
        existingExamples + generatedExamples
    }

    /// Total example count
    var totalCount: Int {
        allExamples.count
    }

    /// Examples grouped by category
    var examplesByCategory: [String: [DialogExample]] {
        Dictionary(grouping: allExamples) { $0.categoryId }
    }

    /// Whether there are any examples
    var hasExamples: Bool {
        !allExamples.isEmpty
    }

    /// Categories with their example counts
    var categoriesWithCounts: [(category: DialogCategory, count: Int)] {
        DialogCategories.all.map { category in
            let count = examplesByCategory[category.id]?.count ?? 0
            return (category, count)
        }
    }

    /// Selected categories
    var selectedCategories: [DialogCategory] {
        DialogCategories.categories(for: Array(selectedCategoryIds))
    }

    // MARK: - Initialization

    init(character: Character?, apiKeyManager: APIKeyManager, repository: CombinedCharacterRepository) {
        self.character = character
        self.repository = repository

        // Initialize service if we have API keys
        if let openAIKey = apiKeyManager.getAPIKey(for: .openAI) {
            let perplexityKey = apiKeyManager.getAPIKey(for: .perplexity)
            self.dialogService = DialogExampleService(
                openAIApiKey: openAIKey,
                perplexityApiKey: perplexityKey
            )
        }

        // Load existing examples
        if let character = character {
            Task {
                await loadExisting(from: character)
            }
        }
    }

    // MARK: - Actions

    /// Generate dialog examples for the character
    func generate() async {
        guard let character = character else {
            error = "No character selected"
            return
        }

        guard let service = dialogService else {
            error = "OpenAI API key required for generation"
            return
        }

        guard !selectedCategoryIds.isEmpty else {
            error = "Select at least one category"
            return
        }

        isGenerating = true
        error = nil
        progressMessage = "Starting generation..."

        let config = DialogGenerationConfig(
            selectedCategoryIds: Array(selectedCategoryIds),
            toneGuidance: toneGuidance,
            styleNotes: styleNotes,
            targetTotalExamples: targetExamples,
            useTranscripts: useTranscripts,
            researchQuotes: researchQuotes
        )

        do {
            let examples = try await service.generateDialogExamples(
                characterName: character.name,
                personaContent: character.markdownContent,
                knowledgeFiles: character.knowledgeFiles,
                config: config,
                onProgress: { [weak self] message in
                    Task { @MainActor in
                        self?.progressMessage = message
                    }
                }
            )

            generatedExamples = examples
            progressMessage = "Generated \(examples.count) examples"

            // Auto-save after generation
            progressMessage = "Saving to character..."
            try await save()
            progressMessage = "Saved \(examples.count) examples"
        } catch {
            self.error = error.localizedDescription
            progressMessage = ""
        }

        isGenerating = false
    }

    /// Regenerate a specific example
    func regenerateExample(_ example: DialogExample) async {
        guard let character = character,
              let service = dialogService else {
            return
        }

        // Find and mark as regenerating
        progressMessage = "Regenerating example..."

        do {
            let newExample = try await service.regenerateExample(
                example: example,
                characterName: character.name,
                personaContent: character.markdownContent
            )

            // Replace in appropriate list
            if let index = generatedExamples.firstIndex(where: { $0.id == example.id }) {
                generatedExamples[index] = newExample
            } else if let index = existingExamples.firstIndex(where: { $0.id == example.id }) {
                // Move regenerated existing to generated (it's now modified)
                existingExamples.remove(at: index)
                generatedExamples.append(newExample)
            }

            // Auto-save after regeneration
            try await save()
            progressMessage = ""
        } catch {
            self.error = "Failed to regenerate: \(error.localizedDescription)"
            progressMessage = ""
        }
    }

    /// Delete an example
    func deleteExample(_ example: DialogExample) {
        generatedExamples.removeAll { $0.id == example.id }
        existingExamples.removeAll { $0.id == example.id }

        // Auto-save after deletion
        Task {
            try? await save()
        }
    }

    /// Start editing an example
    func startEditing(_ example: DialogExample) {
        editingExample = example
        editedDialogText = example.dialog
    }

    /// Save edited example
    func saveEditedExample() {
        guard let editing = editingExample else { return }

        let updated = DialogExample(
            id: editing.id,
            categoryId: editing.categoryId,
            scenario: editing.scenario,
            dialog: editedDialogText,
            source: editing.source,
            keywords: editing.keywords,
            createdAt: editing.createdAt
        )

        // Update in appropriate list
        if let index = generatedExamples.firstIndex(where: { $0.id == editing.id }) {
            generatedExamples[index] = updated
        } else if let index = existingExamples.firstIndex(where: { $0.id == editing.id }) {
            existingExamples[index] = updated
        }

        editingExample = nil
        editedDialogText = ""

        // Auto-save after edit
        Task {
            try? await save()
        }
    }

    /// Cancel editing
    func cancelEditing() {
        editingExample = nil
        editedDialogText = ""
    }

    /// Add a new example manually
    func addExample(categoryId: String, dialog: String) {
        let example = DialogExample(
            categoryId: categoryId,
            dialog: dialog,
            source: .userCreated,
            keywords: []
        )
        generatedExamples.append(example)

        // Auto-save after adding
        Task {
            try? await save()
        }
    }

    /// Save all examples to character
    func save() async throws {
        guard let character = character else {
            throw DialogExampleError.apiError("No character selected")
        }

        let allToSave = allExamples
        let jsonl = examplesToJSONL(allToSave)

        let fileName = "dialog_examples.jsonl"

        _ = try await repository.createKnowledgeFile(
            for: character,
            fileName: fileName,
            content: jsonl
        )

        // Move generated to existing
        existingExamples = allToSave
        generatedExamples = []
    }

    /// Convert examples to JSONL format
    private func examplesToJSONL(_ examples: [DialogExample]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = []
        encoder.dateEncodingStrategy = .iso8601

        return examples.compactMap { example -> String? in
            guard let data = try? encoder.encode(example),
                  let json = String(data: data, encoding: .utf8) else {
                return nil
            }
            return json
        }.joined(separator: "\n")
    }

    /// Parse JSONL content into dialog examples
    private func parseJSONL(_ content: String) -> [DialogExample] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return content.components(separatedBy: .newlines).compactMap { line -> DialogExample? in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty,
                  let data = trimmed.data(using: .utf8) else {
                return nil
            }
            return try? decoder.decode(DialogExample.self, from: data)
        }
    }

    /// Delete all examples
    func deleteAllExamples() {
        generatedExamples = []
        existingExamples = []
        error = nil
        progressMessage = ""

        // Auto-save (will save empty file)
        Task {
            try? await save()
        }
    }

    /// Load existing examples from character
    func loadExisting(from character: Character) async {
        self.character = character

        // Look for dialog_examples.jsonl in knowledge files
        if let file = character.knowledgeFiles.first(where: { $0.fileName == "dialog_examples.jsonl" }) {
            existingExamples = parseJSONL(file.content)
        }
    }

    /// Toggle category selection
    func toggleCategory(_ categoryId: String) {
        if selectedCategoryIds.contains(categoryId) {
            selectedCategoryIds.remove(categoryId)
        } else {
            selectedCategoryIds.insert(categoryId)
        }
    }

    /// Select all categories
    func selectAllCategories() {
        selectedCategoryIds = Set(DialogCategories.all.map { $0.id })
    }

    /// Deselect all categories
    func deselectAllCategories() {
        selectedCategoryIds = []
    }

    /// Export examples as JSONL string
    func exportJSONL() -> String {
        return examplesToJSONL(allExamples)
    }

    /// Export examples as plain text grouped by category
    func exportPlainText() -> String {
        // Capture current examples to ensure consistency
        let currentExisting = existingExamples
        let currentGenerated = generatedExamples
        let examples = currentExisting + currentGenerated

        // If no examples, return empty
        guard !examples.isEmpty else {
            return ""
        }

        var lines: [String] = []
        let grouped = Dictionary(grouping: examples) { $0.categoryId }
        var exportedIds = Set<UUID>()

        // First, export examples by known categories
        for category in DialogCategories.all {
            let categoryExamples = grouped[category.id] ?? []
            if !categoryExamples.isEmpty {
                // Add category header
                lines.append("## \(category.name)")
                lines.append("")

                // Add each dialog example
                for example in categoryExamples {
                    lines.append(example.dialog)
                    exportedIds.insert(example.id)
                }

                lines.append("")  // Blank line between categories
            }
        }

        // Export any examples with unknown category IDs
        let unmatchedExamples = examples.filter { !exportedIds.contains($0.id) }
        if !unmatchedExamples.isEmpty {
            lines.append("## Other")
            lines.append("")
            for example in unmatchedExamples {
                lines.append(example.dialog)
            }
            lines.append("")
        }

        let result = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)

        // Debug fallback: if we have examples but result is empty, export raw dialogs
        if result.isEmpty && !examples.isEmpty {
            return examples.map { $0.dialog }.joined(separator: "\n\n")
        }

        return result
    }
}
