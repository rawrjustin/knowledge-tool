import Foundation

actor PerplexityService {
    private let apiKey: String
    private let baseURL = "https://api.perplexity.ai"

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    // MARK: - Deep Research for Character Creation (Async API)

    /// Performs deep research on a person/character using sonar-deep-research model
    /// Uses async API endpoints with polling as required by the sonar-deep-research model
    /// Returns comprehensive research with citations for building rich character profiles
    func deepResearch(query: String, onProgress: ((String) -> Void)? = nil) async throws -> PerplexityResearchResult {
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

        // Step 1: Create async research job
        onProgress?("Creating deep research job with Perplexity sonar-deep-research...")

        let requestId = try await createAsyncRequest(
            systemPrompt: systemPrompt,
            userQuery: query
        )

        onProgress?("Research job created (ID: \(requestId.prefix(8))...). Polling for results...")

        // Step 2: Poll for completion
        let result = try await pollForCompletion(requestId: requestId, onProgress: onProgress)

        onProgress?("Research complete. Processing \(result.citations.count) citations...")

        return result
    }

    /// Creates an async chat completion job for sonar-deep-research
    private func createAsyncRequest(systemPrompt: String, userQuery: String) async throws -> String {
        let endpoint = "\(baseURL)/async/chat/completions"

        guard let url = URL(string: endpoint) else {
            throw PerplexityError.invalidURL
        }

        struct AsyncRequest: Codable {
            let model: String
            let messages: [Message]
            let reasoning_effort: String

            struct Message: Codable {
                let role: String
                let content: String
            }
        }

        let requestBody = AsyncRequest(
            model: "sonar-deep-research",
            messages: [
                AsyncRequest.Message(role: "system", content: systemPrompt),
                AsyncRequest.Message(role: "user", content: userQuery)
            ],
            reasoning_effort: "high"
        )

        let requestData = try JSONEncoder().encode(requestBody)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = requestData

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw PerplexityError.networkError
        }

        guard httpResponse.statusCode == 200 || httpResponse.statusCode == 201 || httpResponse.statusCode == 202 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw PerplexityError.apiError("Failed to create async request (\(httpResponse.statusCode)): \(errorMessage)")
        }

        struct AsyncCreateResponse: Codable {
            let id: String
            let status: String?
        }

        let createResponse = try JSONDecoder().decode(AsyncCreateResponse.self, from: data)
        return createResponse.id
    }

    /// Polls for async request completion with exponential backoff
    private func pollForCompletion(requestId: String, onProgress: ((String) -> Void)? = nil) async throws -> PerplexityResearchResult {
        let endpoint = "\(baseURL)/async/chat/completions/\(requestId)"

        guard let url = URL(string: endpoint) else {
            throw PerplexityError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        // Poll with exponential backoff: start at 5 seconds, max 60 seconds
        // sonar-deep-research can take 2-4 minutes typically, up to 30+ minutes for complex research
        var pollInterval: UInt64 = 5_000_000_000 // 5 seconds in nanoseconds
        let maxPollInterval: UInt64 = 60_000_000_000 // 60 seconds max between polls
        let maxAttempts = 120 // Max ~30 minutes of polling
        var attempts = 0

        while attempts < maxAttempts {
            attempts += 1

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw PerplexityError.networkError
            }

            guard httpResponse.statusCode == 200 else {
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw PerplexityError.apiError("Failed to get async result (\(httpResponse.statusCode)): \(errorMessage)")
            }

            let pollResponse = try JSONDecoder().decode(AsyncPollResponse.self, from: data)

            switch pollResponse.status {
            case "completed":
                // Extract content and citations from the completed response
                guard let content = pollResponse.choices?.first?.message.content else {
                    throw PerplexityError.noContent
                }

                return PerplexityResearchResult(
                    content: content,
                    citations: pollResponse.citations ?? [],
                    model: pollResponse.model ?? "sonar-deep-research"
                )

            case "failed":
                throw PerplexityError.apiError("Research job failed: \(pollResponse.error ?? "Unknown error")")

            case "pending", "in_progress", "processing":
                onProgress?("Research in progress... (attempt \(attempts), status: \(pollResponse.status))")
                try await Task.sleep(nanoseconds: pollInterval)

                // Exponential backoff with cap
                pollInterval = min(pollInterval * 3 / 2, maxPollInterval)

            default:
                onProgress?("Unknown status: \(pollResponse.status), continuing to poll...")
                try await Task.sleep(nanoseconds: pollInterval)
            }
        }

        throw PerplexityError.timeout
    }

    // MARK: - Quick Research (Sync API)

    /// Performs quick research using sonar model for faster responses
    /// Uses standard synchronous chat completions endpoint
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

struct AsyncPollResponse: Codable {
    let id: String
    let status: String
    let model: String?
    let choices: [Choice]?
    let citations: [String]?
    let error: String?

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
    case timeout

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
        case .timeout:
            return "Research request timed out after 30 minutes"
        }
    }
}
