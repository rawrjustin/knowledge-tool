import Foundation

// MARK: - GitHub API Service

actor GitHubAPIService {
    private let baseURL = "https://api.github.com"
    nonisolated let getToken: @MainActor @Sendable () -> String
    nonisolated let isReadOnly: @MainActor @Sendable () -> Bool

    init(getToken: @escaping @MainActor @Sendable () -> String, isReadOnly: @escaping @MainActor @Sendable () -> Bool) {
        self.getToken = getToken
        self.isReadOnly = isReadOnly
    }

    // MARK: - Repository Contents

    /// List contents of a directory
    func listContents(at path: String) async throws -> [GitHubFile] {
        let url = "\(baseURL)/repos/\(GitHubConfig.owner)/\(GitHubConfig.repo)/contents/\(path)"
        let request = try await createRequest(url: url, method: "GET")

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response)

        return try JSONDecoder().decode([GitHubFile].self, from: data)
    }

    /// Get a single file's contents
    func getFile(at path: String) async throws -> GitHubFile {
        let url = "\(baseURL)/repos/\(GitHubConfig.owner)/\(GitHubConfig.repo)/contents/\(path)"
        let request = try await createRequest(url: url, method: "GET")

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response)

        return try JSONDecoder().decode(GitHubFile.self, from: data)
    }

    /// Create or update a file
    func updateFile(at path: String, content: String, message: String, sha: String? = nil) async throws -> GitHubFile {
        // Check if read-only mode
        let readOnly = await isReadOnly()
        guard !readOnly else {
            throw GitHubAPIError.readOnlyMode
        }

        let url = "\(baseURL)/repos/\(GitHubConfig.owner)/\(GitHubConfig.repo)/contents/\(path)"
        var request = try await createRequest(url: url, method: "PUT")

        let updateRequest = GitHubContentUpdateRequest(
            message: message,
            content: content,
            sha: sha
        )

        request.httpBody = try JSONEncoder().encode(updateRequest)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response)

        let responseObject = try JSONDecoder().decode(GitHubUpdateResponse.self, from: data)
        return responseObject.content
    }

    // MARK: - Commits

    /// Get commit history for a file or directory
    func getCommits(path: String? = nil, limit: Int = 30) async throws -> [GitHubCommit] {
        var urlString = "\(baseURL)/repos/\(GitHubConfig.owner)/\(GitHubConfig.repo)/commits?per_page=\(limit)"
        if let path = path {
            urlString += "&path=\(path)"
        }

        let request = try await createRequest(url: urlString, method: "GET")

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response)

        return try JSONDecoder().decode([GitHubCommit].self, from: data)
    }

    /// Get a specific commit
    func getCommit(sha: String) async throws -> GitHubCommit {
        let url = "\(baseURL)/repos/\(GitHubConfig.owner)/\(GitHubConfig.repo)/commits/\(sha)"
        let request = try await createRequest(url: url, method: "GET")

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response)

        return try JSONDecoder().decode(GitHubCommit.self, from: data)
    }

    /// Compare two commits to see what changed
    func compareCommits(base: String, head: String) async throws -> GitHubComparison {
        let url = "\(baseURL)/repos/\(GitHubConfig.owner)/\(GitHubConfig.repo)/compare/\(base)...\(head)"
        let request = try await createRequest(url: url, method: "GET")

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response)

        return try JSONDecoder().decode(GitHubComparison.self, from: data)
    }

    // MARK: - User Info

    /// Get current authenticated user
    func getCurrentUser() async throws -> GitHubUser {
        let url = "\(baseURL)/user"
        let request = try await createRequest(url: url, method: "GET")

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response)

        return try JSONDecoder().decode(GitHubUser.self, from: data)
    }

    // MARK: - Private Helpers

    private func createRequest(url: String, method: String) async throws -> URLRequest {
        guard let requestURL = URL(string: url) else {
            throw GitHubAPIError.invalidURL
        }

        var request = URLRequest(url: requestURL)
        request.httpMethod = method
        let token = await getToken()
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        return request
    }

    private func validateResponse(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GitHubAPIError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200...299:
            return
        case 401:
            throw GitHubAPIError.unauthorized
        case 403:
            throw GitHubAPIError.forbidden
        case 404:
            throw GitHubAPIError.notFound
        case 422:
            throw GitHubAPIError.validationFailed
        default:
            throw GitHubAPIError.httpError(httpResponse.statusCode)
        }
    }
}

// MARK: - Supporting Types

struct GitHubUpdateResponse: Codable {
    let content: GitHubFile
    let commit: CommitInfo

    struct CommitInfo: Codable {
        let sha: String
        let message: String
    }
}

struct GitHubComparison: Codable {
    let baseCommit: GitHubCommit
    let commits: [GitHubCommit]
    let files: [FileChange]?

    enum CodingKeys: String, CodingKey {
        case baseCommit = "base_commit"
        case commits
        case files
    }

    struct FileChange: Codable {
        let filename: String
        let status: String // "added", "modified", "removed"
        let additions: Int
        let deletions: Int
        let changes: Int
        let patch: String?
    }
}

// MARK: - Errors

enum GitHubAPIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case unauthorized
    case forbidden
    case notFound
    case validationFailed
    case httpError(Int)
    case readOnlyMode

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid GitHub API URL"
        case .invalidResponse:
            return "Invalid response from GitHub API"
        case .unauthorized:
            return "Unauthorized. Please check your GitHub authentication."
        case .forbidden:
            return "Access forbidden. You may not have permission to access this resource."
        case .notFound:
            return "Resource not found on GitHub"
        case .validationFailed:
            return "Validation failed. The request was invalid."
        case .httpError(let code):
            return "GitHub API error: HTTP \(code)"
        case .readOnlyMode:
            return "Cannot modify files in read-only mode. Please sign in with GitHub to make changes."
        }
    }
}
