import Foundation

// MARK: - Auth Models

struct AuthTokens: Codable {
    let accessToken: String
    let refreshToken: String
}

struct AuthUser: Codable, Sendable {
    let userId: String
    let email: String
    let organizationId: String

    private enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case email
        case organizationId = "organization_id"
    }
}

// MARK: - Auth Service

actor AuthService {
    static let shared = AuthService()

    private let baseURL = "https://api.dev.genies.com/auth/v2"
    private let session = URLSession.shared

    // MARK: - UserDefaults Keys

    private enum StorageKey {
        static let accessToken = "auth_access_token"
        static let refreshToken = "auth_refresh_token"
        static let userEmail = "auth_user_email"
        static let userId = "auth_user_id"
        static let organizationId = "auth_organization_id"
    }

    // MARK: - Token Storage

    func storeTokens(_ tokens: AuthTokens) {
        UserDefaults.standard.set(tokens.accessToken, forKey: StorageKey.accessToken)
        UserDefaults.standard.set(tokens.refreshToken, forKey: StorageKey.refreshToken)
    }

    func storeUserInfo(email: String, userId: String, organizationId: String) {
        UserDefaults.standard.set(email, forKey: StorageKey.userEmail)
        UserDefaults.standard.set(userId, forKey: StorageKey.userId)
        UserDefaults.standard.set(organizationId, forKey: StorageKey.organizationId)
    }

    func getAccessToken() -> String? {
        UserDefaults.standard.string(forKey: StorageKey.accessToken)
    }

    func getRefreshToken() -> String? {
        UserDefaults.standard.string(forKey: StorageKey.refreshToken)
    }

    func getStoredEmail() -> String? {
        UserDefaults.standard.string(forKey: StorageKey.userEmail)
    }

    func getStoredUserId() -> String? {
        UserDefaults.standard.string(forKey: StorageKey.userId)
    }

    func getStoredOrganizationId() -> String? {
        UserDefaults.standard.string(forKey: StorageKey.organizationId)
    }

    func clearAll() {
        UserDefaults.standard.removeObject(forKey: StorageKey.accessToken)
        UserDefaults.standard.removeObject(forKey: StorageKey.refreshToken)
        UserDefaults.standard.removeObject(forKey: StorageKey.userEmail)
        UserDefaults.standard.removeObject(forKey: StorageKey.userId)
        UserDefaults.standard.removeObject(forKey: StorageKey.organizationId)
    }

    // MARK: - JWT Helpers

    func isTokenExpired() -> Bool {
        guard let token = UserDefaults.standard.string(forKey: StorageKey.accessToken) else {
            return true
        }
        guard let expiry = getTokenExpiry(token) else {
            return true
        }
        // Consider expired if within 5 minutes of expiry
        let bufferSeconds: TimeInterval = 5 * 60
        return Date().timeIntervalSince1970 >= (expiry - bufferSeconds)
    }

    private func getTokenExpiry(_ jwt: String) -> TimeInterval? {
        let parts = jwt.split(separator: ".")
        guard parts.count >= 2 else { return nil }

        var base64 = String(parts[1])
        // Pad base64 string
        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }

        guard let data = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let exp = json["exp"] as? TimeInterval else {
            return nil
        }
        return exp
    }

    /// Extract user info from JWT token claims
    func extractUserInfoFromToken(_ jwt: String) -> (userId: String?, organizationId: String?) {
        let parts = jwt.split(separator: ".")
        guard parts.count >= 2 else { return (nil, nil) }

        var base64 = String(parts[1])
        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }

        guard let data = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return (nil, nil)
        }

        let userId = json["sub"] as? String
        let orgId = json["org_id"] as? String
        return (userId, orgId)
    }

    // MARK: - Magic Link Auth

    /// Step 1: Request a magic link code to be sent to the email
    func requestMagicLink(email: String) async throws {
        let url = URL(string: "\(baseURL)/magic-auth/start")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = ["email": email]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.networkError("Invalid response")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw AuthError.apiError("Failed to send magic link (HTTP \(httpResponse.statusCode))")
        }

        NSLog("[Auth] Magic link sent to %@", email)
    }

    /// Step 2: Verify the code from email
    func verifyMagicLink(email: String, code: String) async throws -> AuthTokens {
        let url = URL(string: "\(baseURL)/magic-auth/verify")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = ["email": email, "code": code]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.networkError("Invalid response")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 || httpResponse.statusCode == 400 {
                throw AuthError.invalidCode
            }
            throw AuthError.apiError("Verification failed (HTTP \(httpResponse.statusCode))")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = json["accessToken"] as? String,
              let refreshToken = json["refreshToken"] as? String else {
            throw AuthError.apiError("Invalid response format")
        }

        let tokens = AuthTokens(accessToken: accessToken, refreshToken: refreshToken)

        // Store tokens
        storeTokens(tokens)

        // Extract and store user info from JWT
        let userInfo = extractUserInfoFromToken(accessToken)
        storeUserInfo(
            email: email,
            userId: userInfo.userId ?? "",
            organizationId: userInfo.organizationId ?? ""
        )

        NSLog("[Auth] Successfully authenticated user: %@", email)
        return tokens
    }

    // MARK: - Token Refresh

    func refreshSession() async throws -> AuthTokens {
        guard let refreshToken = getRefreshToken() else {
            throw AuthError.noRefreshToken
        }

        let url = URL(string: "\(baseURL)/refresh-session")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: String] = ["refreshToken": refreshToken]
        if let orgId = getStoredOrganizationId(), !orgId.isEmpty {
            body["organizationId"] = orgId
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.networkError("Invalid response")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 {
                // Refresh token is invalid/expired — user needs to re-login
                clearAll()
                throw AuthError.sessionExpired
            }
            throw AuthError.apiError("Token refresh failed (HTTP \(httpResponse.statusCode))")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let newAccessToken = json["accessToken"] as? String,
              let newRefreshToken = json["refreshToken"] as? String else {
            throw AuthError.apiError("Invalid refresh response format")
        }

        let newTokens = AuthTokens(accessToken: newAccessToken, refreshToken: newRefreshToken)
        storeTokens(newTokens)

        // Update user info from new token
        let userInfo = extractUserInfoFromToken(newAccessToken)
        if let userId = userInfo.userId, !userId.isEmpty {
            UserDefaults.standard.set(userId, forKey: StorageKey.userId)
        }
        if let orgId = userInfo.organizationId, !orgId.isEmpty {
            UserDefaults.standard.set(orgId, forKey: StorageKey.organizationId)
        }

        NSLog("[Auth] Token refreshed successfully")
        return newTokens
    }

    /// Get a valid access token, refreshing if needed
    func getValidAccessToken() async throws -> String {
        if isTokenExpired() {
            let tokens = try await refreshSession()
            return tokens.accessToken
        }
        guard let token = getAccessToken() else {
            throw AuthError.notAuthenticated
        }
        return token
    }
}

// MARK: - Auth Errors

enum AuthError: LocalizedError {
    case networkError(String)
    case apiError(String)
    case invalidCode
    case noRefreshToken
    case sessionExpired
    case notAuthenticated

    var errorDescription: String? {
        switch self {
        case .networkError(let msg): return msg
        case .apiError(let msg): return msg
        case .invalidCode: return "Invalid verification code. Please try again."
        case .noRefreshToken: return "No refresh token available. Please log in again."
        case .sessionExpired: return "Your session has expired. Please log in again."
        case .notAuthenticated: return "Not authenticated. Please log in."
        }
    }
}
