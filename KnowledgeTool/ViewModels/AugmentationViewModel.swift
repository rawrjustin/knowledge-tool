import Foundation
import SwiftUI

@MainActor
@Observable
class AugmentationViewModel {
    // Input state
    var sourceType: AugmentationSourceType = .text
    var sourceInput: String = ""
    var sourceLabel: String = ""

    // Processing state
    var isProcessing: Bool = false
    var progressMessage: String = ""
    var error: String?

    // Results state
    var analysisResult: AugmentationAnalysisResult?
    var augmentations: [PersonaAugmentation] = []
    var hasResults: Bool { analysisResult != nil }

    // Preview state
    var showingPreview: Bool = false
    var previewContent: String = ""

    // Dependencies
    private let character: Character
    private let repository: CombinedCharacterRepository
    private let apiKeyManager: APIKeyManager

    init(character: Character, repository: CombinedCharacterRepository, apiKeyManager: APIKeyManager) {
        self.character = character
        self.repository = repository
        self.apiKeyManager = apiKeyManager
    }

    // MARK: - Public Methods

    var canProcess: Bool {
        !sourceInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isProcessing
    }

    var selectedAugmentationsCount: Int {
        augmentations.filter { $0.isSelected }.count
    }

    var selectedRAGEntriesCount: Int {
        analysisResult?.ragEntries.count ?? 0
    }

    func processSource() async {
        guard canProcess else { return }
        guard let openAIKey = apiKeyManager.getAPIKey(for: .openAI) else {
            error = "OpenAI API key not configured. Please add it in Settings."
            return
        }

        isProcessing = true
        error = nil
        progressMessage = "Starting analysis..."

        do {
            let service = AugmentationService(
                openAIApiKey: openAIKey,
                assemblyAIApiKey: apiKeyManager.getAPIKey(for: .assemblyAI)
            )

            let result: AugmentationAnalysisResult

            switch sourceType {
            case .youtubeVideo:
                result = try await service.processYouTubeVideo(
                    character: character,
                    videoURL: sourceInput,
                    onProgress: { [weak self] message in
                        Task { @MainActor in
                            self?.progressMessage = message
                        }
                    }
                )

            case .webLink:
                result = try await service.processWebLink(
                    character: character,
                    url: sourceInput,
                    onProgress: { [weak self] message in
                        Task { @MainActor in
                            self?.progressMessage = message
                        }
                    }
                )

            case .text:
                let label = sourceLabel.isEmpty ? "User Input" : sourceLabel
                result = try await service.analyzeForAugmentation(
                    character: character,
                    sourceType: .text,
                    content: sourceInput,
                    sourceTitle: label,
                    onProgress: { [weak self] message in
                        Task { @MainActor in
                            self?.progressMessage = message
                        }
                    }
                )
            }

            analysisResult = result
            augmentations = result.augmentations
            progressMessage = ""

        } catch {
            self.error = error.localizedDescription
            progressMessage = ""
        }

        isProcessing = false
    }

    func toggleAugmentation(_ augmentation: PersonaAugmentation) {
        if let index = augmentations.firstIndex(where: { $0.id == augmentation.id }) {
            augmentations[index].isSelected.toggle()
        }
    }

    func selectAllAugmentations() {
        for index in augmentations.indices {
            augmentations[index].isSelected = true
        }
    }

    func deselectAllAugmentations() {
        for index in augmentations.indices {
            augmentations[index].isSelected = false
        }
    }

    func generatePreview() -> String {
        guard let openAIKey = apiKeyManager.getAPIKey(for: .openAI) else {
            return character.markdownContent
        }

        let service = AugmentationService(openAIApiKey: openAIKey)
        return service.applyAugmentations(
            to: character.markdownContent,
            augmentations: augmentations
        )
    }

    func showPreview() {
        previewContent = generatePreview()
        showingPreview = true
    }

    func applyChanges() async -> Character? {
        guard let openAIKey = apiKeyManager.getAPIKey(for: .openAI) else {
            error = "OpenAI API key not configured"
            return nil
        }

        isProcessing = true
        progressMessage = "Applying augmentations..."

        do {
            let service = AugmentationService(openAIApiKey: openAIKey)

            // Apply persona augmentations
            let updatedMarkdown = service.applyAugmentations(
                to: character.markdownContent,
                augmentations: augmentations
            )

            // Save as new version
            progressMessage = "Saving new version..."
            var characterToSave = character
            characterToSave.markdownContent = updatedMarkdown
            characterToSave.lastModified = Date()
            let updatedCharacter = try await repository.saveCharacterAsNewVersion(characterToSave)

            // Save RAG entries as knowledge file in a source folder
            if let result = analysisResult, !result.ragEntries.isEmpty {
                progressMessage = "Saving knowledge entries..."
                let jsonlContent = knowledgeEntriesToJSONL(result.ragEntries)

                // Create source folder for this augmentation
                let sourceId = UUID()

                // Determine source type string from current sourceType property
                let sourceTypeString: String
                switch self.sourceType {
                case .youtubeVideo:
                    sourceTypeString = "youtube"
                case .webLink:
                    sourceTypeString = "web"
                case .text:
                    sourceTypeString = "text"
                }

                // Create metadata
                let metadata = SourceMetadata(
                    id: sourceId,
                    type: sourceTypeString,
                    title: result.sourceTitle,
                    sourceUrl: self.sourceType == .text ? nil : sourceInput,
                    processedAt: Date(),
                    files: SourceMetadata.Files(knowledge: "knowledge.jsonl")
                )

                // Save metadata
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                encoder.dateEncodingStrategy = .iso8601
                if let metadataData = try? encoder.encode(metadata),
                   let metadataString = String(data: metadataData, encoding: .utf8) {
                    _ = try await repository.createKnowledgeFileInSourceFolder(
                        for: updatedCharacter,
                        sourceId: sourceId,
                        fileName: "metadata.json",
                        content: metadataString
                    )
                }

                // Save knowledge file
                _ = try await repository.createKnowledgeFileInSourceFolder(
                    for: updatedCharacter,
                    sourceId: sourceId,
                    fileName: "knowledge.jsonl",
                    content: jsonlContent
                )
            }

            progressMessage = ""
            isProcessing = false
            return updatedCharacter

        } catch {
            self.error = error.localizedDescription
            progressMessage = ""
            isProcessing = false
            return nil
        }
    }

    func reset() {
        sourceInput = ""
        sourceLabel = ""
        analysisResult = nil
        augmentations = []
        error = nil
        progressMessage = ""
        showingPreview = false
        previewContent = ""
    }

    // MARK: - Validation

    var isValidYouTubeURL: Bool {
        sourceInput.contains("youtube.com") || sourceInput.contains("youtu.be")
    }

    var isValidURL: Bool {
        guard let url = URL(string: sourceInput) else { return false }
        return url.scheme == "http" || url.scheme == "https"
    }

    var inputPlaceholder: String {
        switch sourceType {
        case .youtubeVideo:
            return "https://www.youtube.com/watch?v=..."
        case .webLink:
            return "https://example.com/article..."
        case .text:
            return "Paste interview transcript, article, notes, or any text content..."
        }
    }

    var inputValidationMessage: String? {
        guard !sourceInput.isEmpty else { return nil }

        switch sourceType {
        case .youtubeVideo:
            return isValidYouTubeURL ? nil : "Please enter a valid YouTube URL"
        case .webLink:
            return isValidURL ? nil : "Please enter a valid URL (http:// or https://)"
        case .text:
            return nil
        }
    }

    var canSubmit: Bool {
        guard !sourceInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }

        switch sourceType {
        case .youtubeVideo:
            return isValidYouTubeURL
        case .webLink:
            return isValidURL
        case .text:
            return true
        }
    }

    // MARK: - Private Helpers

    private func knowledgeEntriesToJSONL(_ entries: [AugmentationKnowledgeEntry]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = []

        return entries.compactMap { entry -> String? in
            guard let data = try? encoder.encode(entry),
                  let json = String(data: data, encoding: .utf8) else {
                return nil
            }
            return json
        }.joined(separator: "\n")
    }
}
