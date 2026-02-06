import Foundation
import SwiftUI

// MARK: - Source Summary View Model

@MainActor
@Observable
class SourceSummaryViewModel {
    // State
    var isGenerating: Bool = false
    var progressMessage: String = ""
    var error: String?
    var summary: SourceSummary?

    // Dependencies
    private let source: KnowledgeSource
    private let characterName: String
    private let apiKeyManager: APIKeyManager

    init(source: KnowledgeSource, characterName: String, apiKeyManager: APIKeyManager) {
        self.source = source
        self.characterName = characterName
        self.apiKeyManager = apiKeyManager
        self.summary = source.summary
    }

    // MARK: - Public Methods

    var hasSummary: Bool {
        summary != nil
    }

    func generateSummary() async {
        guard let openAIKey = apiKeyManager.getAPIKey(for: .openAI) else {
            error = "OpenAI API key not configured. Please add it in Settings."
            return
        }

        isGenerating = true
        error = nil
        progressMessage = "Starting summary generation..."

        do {
            let service = SourceSummaryService(openAIApiKey: openAIKey)

            summary = try await service.generateSummary(
                for: source,
                characterName: characterName,
                onProgress: { [weak self] message in
                    Task { @MainActor in
                        self?.progressMessage = message
                    }
                }
            )

            progressMessage = ""

        } catch {
            self.error = error.localizedDescription
            progressMessage = ""
        }

        isGenerating = false
    }

    func exportAsMarkdown() -> String {
        guard let summary = summary else { return "" }
        return summary.toMarkdown(sourceTitle: source.title)
    }

    func copyToClipboard() {
        let markdown = exportAsMarkdown()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(markdown, forType: .string)
    }
}
