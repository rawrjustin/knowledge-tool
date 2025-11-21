import Foundation

actor OpenAIService {
    private let apiKey: String
    private let baseURL = "https://api.openai.com/v1"
    private let model: String

    init(apiKey: String, model: String = "gpt-4o") {
        self.apiKey = apiKey
        self.model = model
    }

    // MARK: - Summarize Text
    func summarize(text: String, contentType: ContentType) async throws -> String {
        let prompt = createSummarizationPrompt(for: contentType)
        return try await generateCompletion(systemPrompt: prompt, userContent: text)
    }

    // MARK: - Analyze Text Snippet
    func analyzeTextSnippet(_ text: String) async throws -> String {
        let prompt = """
        You are an AI assistant that analyzes and summarizes text snippets.
        Provide a clear, concise summary and extract key insights from the provided text.
        Focus on the main ideas, important details, and actionable information.
        """

        return try await generateCompletion(systemPrompt: prompt, userContent: text)
    }

    // MARK: - Generate Completion
    private func generateCompletion(systemPrompt: String, userContent: String) async throws -> String {
        let endpoint = "\(baseURL)/chat/completions"

        guard let url = URL(string: endpoint) else {
            throw KnowledgeToolError.invalidURL
        }

        struct ChatRequest: Codable {
            let model: String
            let messages: [Message]
            let temperature: Double

            struct Message: Codable {
                let role: String
                let content: String
            }
        }

        let requestBody = ChatRequest(
            model: model,
            messages: [
                ChatRequest.Message(role: "system", content: systemPrompt),
                ChatRequest.Message(role: "user", content: userContent)
            ],
            temperature: 0.7
        )

        let requestData = try JSONEncoder().encode(requestBody)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = requestData

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw KnowledgeToolError.networkError(URLError(.badServerResponse))
        }

        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw KnowledgeToolError.apiError("OpenAI request failed: \(errorMessage)")
        }

        struct ChatResponse: Codable {
            let choices: [Choice]

            struct Choice: Codable {
                let message: Message

                struct Message: Codable {
                    let content: String
                }
            }
        }

        let chatResponse = try JSONDecoder().decode(ChatResponse.self, from: data)

        guard let content = chatResponse.choices.first?.message.content else {
            throw KnowledgeToolError.summarizationFailed("No response content received")
        }

        return content
    }

    // MARK: - Create Summarization Prompts
    private func createSummarizationPrompt(for contentType: ContentType) -> String {
        switch contentType {
        case .video:
            return """
            You are an AI assistant specialized in summarizing video transcripts.
            Create a comprehensive summary of the video transcript provided.
            Your summary should:
            - Capture all key points and main ideas
            - Preserve important details, names, dates, and specific information
            - Organize information logically
            - Be detailed enough to understand the content without watching the video
            - Use clear, concise language

            This summary will be used for knowledge retrieval and reference, so prioritize
            completeness and accuracy over brevity.
            """

        case .article:
            return """
            You are an AI assistant specialized in summarizing articles and web content.
            Create a comprehensive summary of the article provided.
            Your summary should:
            - Identify and explain the main thesis or argument
            - Capture all key points and supporting evidence
            - Preserve important details, statistics, and quotes
            - Maintain the logical flow of ideas
            - Be detailed enough to understand the article without reading the original
            - Use clear, concise language

            This summary will be used for knowledge retrieval and reference, so prioritize
            completeness and accuracy over brevity.
            """

        case .textSnippet:
            return """
            You are an AI assistant specialized in analyzing text snippets.
            Provide a clear analysis and summary of the text snippet provided.
            Your analysis should:
            - Identify the main ideas or purpose
            - Extract key information and insights
            - Highlight any actionable items or important details
            - Provide context if applicable
            - Use clear, concise language

            Focus on making the information easily digestible and useful for future reference.
            """
        }
    }
}
