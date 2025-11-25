import Foundation
import Security
import AppKit

// MARK: - GitHub Configuration

struct GitHubConfig {
    // GitHub App credentials for OAuth (Option B)
    static let clientID = "Iv23liEqcFt6FWCHq2cx"
    static let clientSecret = "998ce306ef59fbcd28d810523ced31217bfb14c8"
    static let appID = "2332856"

    // Read-only PAT for unauthenticated users (Option A - Fallback)
    // Set via environment variable GITHUB_PAT or replace with your own token
    static let readOnlyPAT = ProcessInfo.processInfo.environment["GITHUB_PAT"] ?? ""

    // Repository info
    static let owner = "geniesinc"
    static let repo = "CharacterPrompts"

    // OAuth URLs
    static let authorizeURL = "https://github.com/login/oauth/authorize"
    static let accessTokenURL = "https://github.com/login/oauth/access_token"
    static let callbackScheme = "knowledgetool"
}

// MARK: - GitHub Auth Service

@Observable
@MainActor
final class GitHubAuthService: @unchecked Sendable {
    private(set) var authMode: GitHubAuthMode?
    private(set) var isAuthenticating = false

    private let keychainService = "com.knowledgetool.github"
    private let keychainAccount = "oauth_token"

    init() {
        // Try to load saved OAuth token on init
        Task {
            await loadSavedAuth()
        }
    }

    // MARK: - Authentication State

    var isAuthenticated: Bool {
        if case .authenticated = authMode {
            return true
        }
        return false
    }

    var isReadOnly: Bool {
        authMode?.isReadOnly ?? true
    }

    var currentUser: GitHubUser? {
        authMode?.user
    }

    var token: String {
        authMode?.token ?? GitHubConfig.readOnlyPAT
    }

    // MARK: - OAuth Flow

    /// Initiates OAuth flow by opening GitHub authorization URL in browser
    func startOAuthFlow() {
        isAuthenticating = true

        var components = URLComponents(string: GitHubConfig.authorizeURL)
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: GitHubConfig.clientID),
            URLQueryItem(name: "scope", value: "repo user:email"),
            URLQueryItem(name: "redirect_uri", value: "\(GitHubConfig.callbackScheme)://oauth/callback")
        ]

        guard let url = components?.url else {
            isAuthenticating = false
            return
        }

        NSWorkspace.shared.open(url)
    }

    /// Handles OAuth callback with authorization code
    func handleOAuthCallback(code: String) async throws {
        defer { isAuthenticating = false }

        // Exchange code for access token
        let accessToken = try await exchangeCodeForToken(code: code)

        // Fetch user info
        let user = try await fetchUserInfo(token: accessToken)

        // Save to keychain
        try saveTokenToKeychain(accessToken)

        // Update auth mode
        authMode = .authenticated(token: accessToken, user: user)
    }

    /// Sign out and revert to read-only mode
    func signOut() {
        deleteTokenFromKeychain()
        authMode = .readOnly(token: GitHubConfig.readOnlyPAT)
    }

    /// Use read-only mode (fallback PAT)
    func useReadOnlyMode() {
        authMode = .readOnly(token: GitHubConfig.readOnlyPAT)
    }

    // MARK: - Private Helpers

    private func loadSavedAuth() async {
        // Try to load OAuth token from keychain
        if let savedToken = loadTokenFromKeychain() {
            do {
                let user = try await fetchUserInfo(token: savedToken)
                authMode = .authenticated(token: savedToken, user: user)
                return
            } catch {
                // Token might be expired, delete it
                deleteTokenFromKeychain()
            }
        }

        // Fall back to read-only mode
        authMode = .readOnly(token: GitHubConfig.readOnlyPAT)
    }

    private func exchangeCodeForToken(code: String) async throws -> String {
        var request = URLRequest(url: URL(string: GitHubConfig.accessTokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = [
            "client_id": GitHubConfig.clientID,
            "client_secret": GitHubConfig.clientSecret,
            "code": code,
            "redirect_uri": "\(GitHubConfig.callbackScheme)://oauth/callback"
        ]

        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw GitHubAuthError.tokenExchangeFailed
        }

        let oauthResponse = try JSONDecoder().decode(GitHubOAuthResponse.self, from: data)
        return oauthResponse.accessToken
    }

    private func fetchUserInfo(token: String) async throws -> GitHubUser {
        var request = URLRequest(url: URL(string: "https://api.github.com/user")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw GitHubAuthError.userFetchFailed
        }

        return try JSONDecoder().decode(GitHubUser.self, from: data)
    }

    // MARK: - Keychain Operations

    private func saveTokenToKeychain(_ token: String) throws {
        let data = token.data(using: .utf8)!

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecValueData as String: data
        ]

        // Delete existing item first
        SecItemDelete(query as CFDictionary)

        // Add new item
        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            throw GitHubAuthError.keychainSaveFailed
        }
    }

    private func loadTokenFromKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8) else {
            return nil
        }

        return token
    }

    private func deleteTokenFromKeychain() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]

        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Errors

enum GitHubAuthError: LocalizedError {
    case tokenExchangeFailed
    case userFetchFailed
    case keychainSaveFailed
    case notAuthenticated

    var errorDescription: String? {
        switch self {
        case .tokenExchangeFailed:
            return "Failed to exchange authorization code for access token"
        case .userFetchFailed:
            return "Failed to fetch user information from GitHub"
        case .keychainSaveFailed:
            return "Failed to save token to keychain"
        case .notAuthenticated:
            return "User is not authenticated. Read-only mode active."
        }
    }
}
