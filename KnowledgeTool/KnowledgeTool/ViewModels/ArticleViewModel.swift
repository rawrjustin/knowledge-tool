import Foundation
import SwiftUI

@Observable
final class ArticleViewModel {
    var urlInput: String = ""
    var processingState: ProcessingState = .idle
    var articleInfo: ArticleInfo?
    var summary: Summary?
    var errorMessage: String?

    private let apiKeyManager: APIKeyManager
    private var articleService = ArticleService()

    init(apiKeyManager: APIKeyManager) {
        self.apiKeyManager = apiKeyManager
    }

    // MARK: - Process Article from URL
    @MainActor
    func processArticle() async {
        guard !urlInput.trimmingCharacters(in: .whitespaces).isEmpty else {
            errorMessage = "Please enter a valid URL"
            return
        }

        // Validate API key
        guard let openAIKey = apiKeyManager.getAPIKey(for: .openAI) else {
            errorMessage = "OpenAI API key not found. Please add it in Settings."
            processingState = .failed("Missing API key")
            return
        }

        // Reset state
        articleInfo = nil
        summary = nil
        errorMessage = nil

        do {
            // Step 1: Fetch article content
            processingState = .processing("Fetching article...")

            let article = try await articleService.fetchArticle(from: urlInput)
            articleInfo = article

            // Step 2: Summarize article
            processingState = .processing("Generating summary...")

            let openAI = OpenAIService(apiKey: openAIKey)
            let summaryText = try await openAI.summarize(text: article.content, contentType: .article)

            summary = Summary(
                text: summaryText,
                sourceType: .article,
                sourceURL: urlInput,
                title: article.title
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

    // MARK: - Export Results
    func exportArticleContent() -> String? {
        guard let article = articleInfo else { return nil }

        var output = ""

        if let title = article.title {
            output += "Title: \(title)\n"
        }

        output += "URL: \(article.url)\n"

        if let publishedDate = article.publishedDate {
            output += "Published: \(publishedDate.formatted())\n"
        }

        output += "\n=== Article Content ===\n\n"
        output += article.content

        return output
    }

    func exportSummary() -> String? {
        guard let summary = summary else { return nil }

        var output = ""

        if let title = summary.title {
            output += "Title: \(title)\n"
        }

        if let sourceURL = summary.sourceURL {
            output += "Source: \(sourceURL)\n"
        }

        output += "Date: \(summary.createdAt.formatted())\n\n"
        output += "=== Summary ===\n\n"
        output += summary.text

        return output
    }

    // MARK: - Reset
    @MainActor
    func reset() {
        urlInput = ""
        processingState = .idle
        articleInfo = nil
        summary = nil
        errorMessage = nil
    }
}
