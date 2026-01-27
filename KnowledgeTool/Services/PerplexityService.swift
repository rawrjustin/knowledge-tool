import Foundation

actor PerplexityService {
    private let apiKey: String
    private let baseURL = "https://api.perplexity.ai"

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    // MARK: - Research for Character Creation

    /// Performs research on a person/character using sonar-pro model
    /// Uses synchronous API for fast, reliable results (typically 20-60 seconds)
    /// Returns research with citations for building character profiles
    func research(query: String, onProgress: (@Sendable (String) -> Void)? = nil) async throws -> PerplexityResearchResult {
        let systemPrompt = """
        You are an expert researcher helping build comprehensive AI character profiles. Your research should be:

        1. THOROUGH: Cover key aspects of the subject's life, career, personality, relationships, and public presence
        2. FACTUAL: Only include verified information with sources
        3. DETAILED: Include specific dates, numbers, quotes, and concrete details
        4. CURRENT: Include the most recent available information
        5. NUANCED: Capture personality traits, speech patterns, values, and behavioral tendencies

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

        onProgress?("Starting web research with Perplexity...")

        let requestBody = ChatRequest(
            model: "sonar-pro",
            messages: [
                ChatRequest.Message(role: "system", content: systemPrompt),
                ChatRequest.Message(role: "user", content: query)
            ],
            temperature: 0.3,
            max_tokens: 8000
        )

        let requestData = try JSONEncoder().encode(requestBody)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = requestData
        request.timeoutInterval = 180 // 3 minute timeout

        onProgress?("Researching... (this typically takes 30-60 seconds)")

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

        onProgress?("Research complete!")

        return PerplexityResearchResult(
            content: content,
            citations: perplexityResponse.citations ?? [],
            model: "sonar-pro"
        )
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
