import Foundation

// MARK: - Genies Persona Service

/// Actor handling all Genies Persona API HTTP calls
actor GeniesPersonaService {
    static let shared = GeniesPersonaService()

    private let baseURL = "https://chat.dev.genies.com"
    private let session = URLSession.shared

    // MARK: - Config Management

    /// Create a new character config
    func createConfig(name: String, config: GeniesCharacterConfig, orgId: String) async throws -> GeniesConfigResponse {
        var components = URLComponents(string: "\(baseURL)/character/config")!
        components.queryItems = [URLQueryItem(name: "type", value: "config")]
        var request = try await authenticatedRequest(url: components.url!, method: "POST")

        let body: [String: Any] = [
            "name": name,
            "org_id": orgId,
            "config": try jsonObject(from: config)
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data)
        return try JSONDecoder().decode(GeniesConfigResponse.self, from: data)
    }

    /// Update an existing character config
    func updateConfig(configId: String, name: String?, config: GeniesCharacterConfig) async throws {
        let url = URL(string: "\(baseURL)/character/config/\(configId)")!
        var request = try await authenticatedRequest(url: url, method: "PATCH")

        var body: [String: Any] = [
            "config": try jsonObject(from: config)
        ]
        if let name = name {
            body["name"] = name
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data)
    }

    /// Get a specific config by ID
    func getConfig(configId: String) async throws -> GeniesConfigResponse {
        let url = URL(string: "\(baseURL)/character/config/\(configId)")!
        let request = try await authenticatedRequest(url: url, method: "GET")

        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data)
        return try JSONDecoder().decode(GeniesConfigResponse.self, from: data)
    }

    /// Query configs for an organization
    func queryConfigs(orgId: String? = nil, limit: Int = 50, cursor: String? = nil) async throws -> GeniesConfigListResponse {
        var components = URLComponents(string: "\(baseURL)/character/config")!
        var queryItems = [
            URLQueryItem(name: "limit", value: String(limit))
        ]
        if let orgId = orgId {
            queryItems.append(URLQueryItem(name: "org_id", value: orgId))
        }
        if let cursor = cursor {
            queryItems.append(URLQueryItem(name: "cursor", value: cursor))
        }
        components.queryItems = queryItems

        let request = try await authenticatedRequest(url: components.url!, method: "GET")
        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data)

        do {
            return try JSONDecoder().decode(GeniesConfigListResponse.self, from: data)
        } catch {
            let bodyPreview = String(data: data, encoding: .utf8)?.prefix(500) ?? "(non-utf8)"
            NSLog("[GeniesPersonaService] Failed to decode config list: %@\nResponse preview: %@", error.localizedDescription, String(bodyPreview))
            throw error
        }
    }

    // MARK: - Chat

    /// Send a message via the Genies Chat V2 API
    func sendMessage(input: String, sessionId: String, configId: String) async throws -> GeniesChatResponse {
        let url = URL(string: "\(baseURL)/v2/chat")!
        var request = try await authenticatedRequest(url: url, method: "POST")
        request.timeoutInterval = 60

        let body: [String: Any] = [
            "input": input,
            "session_id": sessionId,
            "config_id": configId
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data)
        return try JSONDecoder().decode(GeniesChatResponse.self, from: data)
    }

    /// Get the latest session for a config
    func getLatestSession(configId: String) async throws -> GeniesSessionInfo? {
        let components = URLComponents(string: "\(baseURL)/v2/sessions")!
        // The API may filter by config_id — adjust if the actual API differs
        var request = try await authenticatedRequest(url: components.url!, method: "GET")

        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data)

        let list = try JSONDecoder().decode(GeniesSessionListResponse.self, from: data)
        return list.data.first(where: { $0.configId == configId })
    }

    /// Get chat history for a session
    func getSessionHistory(sessionId: String, limit: Int = 50, cursor: String? = nil) async throws -> GeniesChatHistoryResponse {
        var components = URLComponents(string: "\(baseURL)/v2/sessions/\(sessionId)/messages")!
        var queryItems = [URLQueryItem(name: "limit", value: String(limit))]
        if let cursor = cursor {
            queryItems.append(URLQueryItem(name: "cursor", value: cursor))
        }
        components.queryItems = queryItems

        let request = try await authenticatedRequest(url: components.url!, method: "GET")
        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data)
        return try JSONDecoder().decode(GeniesChatHistoryResponse.self, from: data)
    }

    // MARK: - Helpers

    private func authenticatedRequest(url: URL, method: String) async throws -> URLRequest {
        let token = try await AuthService.shared.getValidAccessToken()

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }

    private func jsonObject(from encodable: some Encodable) throws -> Any {
        let data = try JSONEncoder().encode(encodable)
        return try JSONSerialization.jsonObject(with: data)
    }

    private func validateResponse(_ response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeniesAPIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            if httpResponse.statusCode == 401 {
                throw GeniesAPIError.unauthorized
            }
            throw GeniesAPIError.httpError(statusCode: httpResponse.statusCode, body: body)
        }
    }
}

// MARK: - Errors

enum GeniesAPIError: LocalizedError {
    case invalidResponse
    case unauthorized
    case httpError(statusCode: Int, body: String)
    case notPublished

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from Genies API"
        case .unauthorized:
            return "Authentication failed. Please log in again."
        case .httpError(let statusCode, let body):
            return "Genies API error (\(statusCode)): \(body)"
        case .notPublished:
            return "Character must be published before chatting"
        }
    }
}
