import Foundation
import SwiftUI

@Observable
final class TextSnippetViewModel {
    var textInput: String = ""
    var processingState: ProcessingState = .idle
    var analysis: Summary?
    var errorMessage: String?

    private let apiKeyManager: APIKeyManager

    init(apiKeyManager: APIKeyManager) {
        self.apiKeyManager = apiKeyManager
    }

    // MARK: - Process Text Snippet
    @MainActor
    func processTextSnippet() async {
        guard !textInput.trimmingCharacters(in: .whitespaces).isEmpty else {
            errorMessage = "Please enter some text to analyze"
            return
        }

        // Validate API key
        guard let openAIKey = apiKeyManager.getAPIKey(for: .openAI) else {
            errorMessage = "OpenAI API key not found. Please add it in Settings."
            processingState = .failed("Missing API key")
            return
        }

        // Reset state
        analysis = nil
        errorMessage = nil

        do {
            processingState = .processing("Analyzing text...")

            let openAI = OpenAIService(apiKey: openAIKey)
            let analysisText = try await openAI.analyzeTextSnippet(textInput)

            analysis = Summary(
                text: analysisText,
                sourceType: .textSnippet,
                sourceURL: nil,
                title: "Text Analysis"
            )

            processingState = .completed

        } catch let error as KnowledgeToolError {
            errorMessage = error.localizedDescription
            processingState = .failed(error.localizedDescription)
        } catch {
            errorMessage = error.localizedDescription
            processingState = .failed(error.localizedDescription)
        }
    }

    // MARK: - Paste from Clipboard
    @MainActor
    func pasteFromClipboard() {
        #if os(macOS)
        if let clipboardString = NSPasteboard.general.string(forType: .string) {
            textInput = clipboardString
        }
        #endif
    }

    // MARK: - Export Results
    func exportAnalysis() -> String? {
        guard let analysis = analysis else { return nil }

        var output = ""
        output += "Date: \(analysis.createdAt.formatted())\n\n"
        output += "=== Original Text ===\n\n"
        output += textInput
        output += "\n\n=== Analysis ===\n\n"
        output += analysis.text

        return output
    }

    // MARK: - Reset
    @MainActor
    func reset() {
        textInput = ""
        processingState = .idle
        analysis = nil
        errorMessage = nil
    }
}
