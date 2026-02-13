import Foundation

// MARK: - Source Summary Service

/// Service for generating 2-page summaries of knowledge sources
actor SourceSummaryService {
    private let openAIApiKey: String
    private let model = "gpt-5"
    private let session: URLSession

    init(openAIApiKey: String) {
        self.openAIApiKey = openAIApiKey

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 180
        config.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: config)
    }

    // MARK: - Generate Summary

    /// Generate a summary for a knowledge source
    /// - Parameters:
    ///   - source: The knowledge source to summarize
    ///   - characterName: The name of the character this source belongs to
    /// - Returns: A structured summary
    func generateSummary(
        for source: KnowledgeSource,
        characterName: String,
        onProgress: @escaping @Sendable (String) -> Void
    ) async throws -> SourceSummary {
        onProgress("Preparing source content...")

        // Build content from either raw transcript or entries
        let content: String
        if let transcript = source.rawTranscript, !transcript.isEmpty {
            content = transcript
        } else if let rawContent = source.rawContent, !rawContent.isEmpty {
            content = rawContent
        } else {
            // Build content from entries
            content = source.entries.map { entry in
                "[\(entry.section)] \(entry.content)"
            }.joined(separator: "\n\n")
        }

        guard !content.isEmpty else {
            throw SourceSummaryError.emptyContent
        }

        onProgress("Generating summary...")

        let prompt = buildSummaryPrompt(
            sourceTitle: source.title,
            sourceType: source.sourceType,
            characterName: characterName
        )

        let response = try await callOpenAI(
            systemPrompt: prompt,
            userContent: content
        )

        onProgress("Processing response...")

        return try parseSummaryResponse(response)
    }

    // MARK: - Private Methods

    private func buildSummaryPrompt(
        sourceTitle: String,
        sourceType: KnowledgeSourceType,
        characterName: String
    ) -> String {
        return """
        You are creating a concise 2-page summary of content related to \(characterName).

        SOURCE TITLE: \(sourceTitle)
        SOURCE TYPE: \(sourceType.displayName)

        ---

        ## Your Task

        Create a structured summary that team members can quickly reference to understand this source's key content.

        ---

        ## Output Format

        Return a JSON object with this exact structure:

        ```json
        {
          "overview": "2-3 sentence overview of what this source covers and its significance.",
          "key_points": [
            {
              "topic": "Brief topic name",
              "summary": "1-2 sentence explanation of the key point",
              "importance": "high" | "medium" | "low",
              "timestamp": 300  // Optional: timestamp in seconds if from video
            }
          ],
          "notable_quotes": [
            "Direct quote that captures something important or memorable"
          ],
          "themes": [
            "Main theme 1",
            "Main theme 2"
          ]
        }
        ```

        ---

        ## Guidelines

        1. **Overview**: Provide context about what this source is and why it matters for understanding \(characterName).

        2. **Key Points** (8-12 points):
           - Cover the most important information
           - Mark importance: "high" for critical insights, "medium" for useful details, "low" for supplementary info
           - Include timestamps if the content has time references
           - Focus on facts, insights, and revelations

        3. **Notable Quotes** (3-5 quotes):
           - Select quotes that are memorable, insightful, or capture \(characterName)'s voice
           - Keep quotes concise (1-2 sentences max)

        4. **Themes** (3-5 themes):
           - Identify the main topics or recurring ideas
           - Use clear, descriptive names

        ---

        ## Critical

        - Output ONLY valid JSON - no markdown, no commentary
        - Be concise but comprehensive
        - Focus on information useful for understanding \(characterName)
        """
    }

    private func callOpenAI(systemPrompt: String, userContent: String) async throws -> String {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(openAIApiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Truncate content if too long
        let maxContentLength = 100000
        let truncatedContent = userContent.count > maxContentLength
            ? String(userContent.prefix(maxContentLength)) + "\n\n[Content truncated...]"
            : userContent

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": truncatedContent]
            ],
            "max_completion_tokens": 4000,
            "response_format": ["type": "json_object"]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SourceSummaryError.networkError
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw SourceSummaryError.apiError("OpenAI error: \(errorBody)")
        }

        struct ChatResponse: Decodable {
            let choices: [Choice]
            struct Choice: Decodable {
                let message: Message
            }
            struct Message: Decodable {
                let content: String
            }
        }

        let chatResponse = try JSONDecoder().decode(ChatResponse.self, from: data)
        return chatResponse.choices.first?.message.content ?? ""
    }

    private func parseSummaryResponse(_ response: String) throws -> SourceSummary {
        guard let jsonData = response.data(using: .utf8) else {
            throw SourceSummaryError.parseError("Failed to encode response as data")
        }

        struct SummaryResponse: Decodable {
            let overview: String
            let key_points: [KeyPointDTO]
            let notable_quotes: [String]
            let themes: [String]

            struct KeyPointDTO: Decodable {
                let topic: String
                let summary: String
                let importance: String
                let timestamp: Double?
            }
        }

        let parsed = try JSONDecoder().decode(SummaryResponse.self, from: jsonData)

        let keyPoints = parsed.key_points.map { dto in
            KeyPoint(
                topic: dto.topic,
                summary: dto.summary,
                importance: KeyPoint.Importance(rawValue: dto.importance.lowercased()) ?? .medium,
                timestamp: dto.timestamp
            )
        }

        return SourceSummary(
            overview: parsed.overview,
            keyPoints: keyPoints,
            notableQuotes: parsed.notable_quotes,
            themes: parsed.themes
        )
    }
}

// MARK: - Errors

enum SourceSummaryError: LocalizedError {
    case emptyContent
    case networkError
    case apiError(String)
    case parseError(String)

    var errorDescription: String? {
        switch self {
        case .emptyContent:
            return "Source has no content to summarize"
        case .networkError:
            return "Network error occurred"
        case .apiError(let message):
            return message
        case .parseError(let reason):
            return "Failed to parse response: \(reason)"
        }
    }
}
