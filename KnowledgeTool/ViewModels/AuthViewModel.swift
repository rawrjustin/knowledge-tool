import Foundation

@MainActor
@Observable
final class AuthViewModel {
    // MARK: - Auth State

    enum AuthState: Sendable {
        case unknown
        case loggedOut
        case loggedIn
    }

    enum LoginStep {
        case enterEmail
        case enterCode
    }

    var authState: AuthState = .unknown
    var loginStep: LoginStep = .enterEmail

    // Login form state
    var email = ""
    var verificationCode = ""
    var isLoading = false
    var errorMessage: String?

    // User info (populated after login)
    var userEmail: String?
    var userId: String?
    var organizationId: String?

    private let authService = AuthService.shared

    // MARK: - Initialization

    func checkExistingSession() async {
        let hasToken = await authService.getAccessToken() != nil
        let hasRefresh = await authService.getRefreshToken() != nil

        if hasToken && hasRefresh {
            // Try to refresh token to validate session
            let isExpired = await authService.isTokenExpired()
            if isExpired {
                do {
                    _ = try await authService.refreshSession()
                    await loadUserInfo()
                    authState = .loggedIn
                } catch {
                    NSLog("[Auth] Session refresh failed: %@", error.localizedDescription)
                    authState = .loggedOut
                }
            } else {
                await loadUserInfo()
                authState = .loggedIn
            }
        } else {
            authState = .loggedOut
        }
    }

    private func loadUserInfo() async {
        userEmail = await authService.getStoredEmail()
        userId = await authService.getStoredUserId()
        organizationId = await authService.getStoredOrganizationId()
    }

    // MARK: - Login Flow

    func requestMagicLink() async {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmedEmail.isEmpty else {
            errorMessage = "Please enter your email address."
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            try await authService.requestMagicLink(email: trimmedEmail)
            email = trimmedEmail
            loginStep = .enterCode
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func verifyCode() async {
        let trimmedCode = verificationCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCode.isEmpty else {
            errorMessage = "Please enter the verification code."
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            _ = try await authService.verifyMagicLink(email: email, code: trimmedCode)
            await loadUserInfo()
            authState = .loggedIn
            resetLoginForm()
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func logout() async {
        await authService.clearAll()
        userEmail = nil
        userId = nil
        organizationId = nil
        authState = .loggedOut
        resetLoginForm()
    }

    func goBackToEmail() {
        loginStep = .enterEmail
        verificationCode = ""
        errorMessage = nil
    }

    private func resetLoginForm() {
        email = ""
        verificationCode = ""
        loginStep = .enterEmail
        errorMessage = nil
    }

    // MARK: - Display Helpers

    var userInitials: String {
        guard let email = userEmail, !email.isEmpty else { return "?" }
        let name = email.components(separatedBy: "@").first ?? email
        let parts = name.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        if parts.count >= 2 {
            return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }

    var displayName: String {
        guard let email = userEmail, !email.isEmpty else { return "Unknown" }
        return email.components(separatedBy: "@").first ?? email
    }
}
