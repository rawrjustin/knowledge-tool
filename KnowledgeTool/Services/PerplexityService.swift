import Foundation

actor PerplexityService {
    private let apiKey: String
    private let baseURL = "https://api.perplexity.ai"

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    // MARK: - Deep Research for Character Creation

    /// Performs deep research on a person/character using sonar-deep-research model
    /// Returns comprehensive research with citations for building rich character profiles
    func deepResearch(query: String, onProgress: ((String) -> Void)? = nil) async throws -> PerplexityResearchResult {
        let endpoint = "\(baseURL)/chat/completions"

        guard let url = URL(string: endpoint) else {
            throw PerplexityError.invalidURL
        }

        let systemPrompt = """
        You are an expert researcher helping build comprehensive AI character profiles. Your research should be:

        1. EXHAUSTIVE: Cover every aspect of the subject's life, career, personality, relationships, and public presence
        2. FACTUAL: Only include verified information with sources
        3. DETAILED: Include specific dates, numbers, quotes, and concrete details
        4. CURRENT: Include the most recent available information
        5. NUANCED: Capture personality traits, speech patterns, values, and behavioral tendencies

        For each fact or claim, provide the source when available.

        Structure your research to cover:
        - Background and origins (birthplace, family, upbringing)
        - Career timeline and major milestones
        - Personality traits and psychological profile
        - Communication style and speech patterns
        - Values, beliefs, and moral framework
        - Key relationships (family, friends, rivals, partners)
        - Physical characteristics and style
        - Behavioral mannerisms and habits
        - Transformative life moments
        - Cultural impact and legacy
        - Recent news and current situation
        - Controversies or challenges faced
        - Quotes that reveal character
        - Interests, hobbies, and passions
        """

        struct ChatRequest: Codable {
            let model: String
            let messages: [Message]
            let temperature: Double
            let max_tokens: Int
            let return_citations: Bool
            let search_recency_filter: String

            struct Message: Codable {
                let role: String
                let content: String
            }
        }

        let requestBody = ChatRequest(
            model: "sonar-deep-research",
            messages: [
                ChatRequest.Message(role: "system", content: systemPrompt),
                ChatRequest.Message(role: "user", content: query)
            ],
            temperature: 0.2,
            max_tokens: 8000,
            return_citations: true,
            search_recency_filter: "month"
        )

        let requestData = try JSONEncoder().encode(requestBody)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = requestData
        request.timeoutInterval = 300 // 5 minute timeout for deep research

        onProgress?("Starting deep research with Perplexity sonar-deep-research...")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw PerplexityError.networkError
        }

        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw PerplexityError.apiError("Perplexity request failed (\(httpResponse.statusCode)): \(errorMessage)")
        }

        let perplexityResponse = try JSONDecoder().decode(PerplexityResponse.self, from: data)

        guard let content = perplexityResponse.choices.first?.message.content else {
            throw PerplexityError.noContent
        }

        onProgress?("Research complete. Processing \(perplexityResponse.citations?.count ?? 0) citations...")

        return PerplexityResearchResult(
            content: content,
            citations: perplexityResponse.citations ?? [],
            model: perplexityResponse.model
        )
    }

    /// Performs quick research using sonar model for faster responses
    func quickResearch(query: String) async throws -> String {
        let endpoint = "\(baseURL)/chat/completions"

        guard let url = URL(string: endpoint) else {
            throw PerplexityError.invalidURL
        }

        struct ChatRequest: Codable {
            let model: String
            let messages: [Message]
            let temperature: Double
            let max_tokens: Int

            struct Message: Codable {
                let role: String
                let content: String
            }
        }

        let requestBody = ChatRequest(
            model: "sonar",
            messages: [
                ChatRequest.Message(role: "user", content: query)
            ],
            temperature: 0.3,
            max_tokens: 4000
        )

        let requestData = try JSONEncoder().encode(requestBody)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = requestData

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw PerplexityError.apiError("Perplexity request failed: \(errorMessage)")
        }

        let perplexityResponse = try JSONDecoder().decode(PerplexityResponse.self, from: data)

        guard let content = perplexityResponse.choices.first?.message.content else {
            throw PerplexityError.noContent
        }

        return content
    }
}

// MARK: - Response Models

struct PerplexityResponse: Codable {
    let id: String
    let model: String
    let choices: [Choice]
    let citations: [String]?

    struct Choice: Codable {
        let message: Message
        let finish_reason: String?

        struct Message: Codable {
            let role: String
            let content: String
        }
    }
}

struct PerplexityResearchResult {
    let content: String
    let citations: [String]
    let model: String

    var formattedCitations: String {
        guard !citations.isEmpty else { return "" }

        return citations.enumerated().map { index, url in
            "[\(index + 1)] \(url)"
        }.joined(separator: "\n")
    }
}

// MARK: - Errors

enum PerplexityError: LocalizedError {
    case invalidURL
    case networkError
    case apiError(String)
    case noContent

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid Perplexity API URL"
        case .networkError:
            return "Network error while connecting to Perplexity"
        case .apiError(let message):
            return message
        case .noContent:
            return "No content received from Perplexity"
        }
    }
}
