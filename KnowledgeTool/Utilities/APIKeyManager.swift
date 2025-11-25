import Foundation
import Security

@Observable
final class APIKeyManager {
    private let keychainService = "com.knowledgetool.apikeys"

    // MARK: - Settings Keys
    private enum SettingsKey {
        static let repositoryPath = "characterRepositoryPath"
    }

    // MARK: - Default Repository Path
    static var defaultRepositoryPath: URL {
        // Default to Application Support directory
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("KnowledgeTool/CharacterPrompts")
    }

    enum APIService: String, CaseIterable {
        case assemblyAI = "AssemblyAI"
        case openAI = "OpenAI"
        case perplexity = "Perplexity"
        case gitHubPAT = "GitHub PAT"

        var keychainKey: String {
            switch self {
            case .assemblyAI: return "assemblyai_api_key"
            case .openAI: return "openai_api_key"
            case .perplexity: return "perplexity_api_key"
            case .gitHubPAT: return "github_pat"
            }
        }

        var displayName: String { rawValue }
    }

    // MARK: - Repository Path
    var repositoryPath: URL {
        get {
            if let savedPath = UserDefaults.standard.string(forKey: SettingsKey.repositoryPath) {
                return URL(fileURLWithPath: savedPath)
            }
            return Self.defaultRepositoryPath
        }
        set {
            UserDefaults.standard.set(newValue.path, forKey: SettingsKey.repositoryPath)
        }
    }

    var hasCustomRepositoryPath: Bool {
        UserDefaults.standard.string(forKey: SettingsKey.repositoryPath) != nil
    }

    func resetRepositoryPath() {
        UserDefaults.standard.removeObject(forKey: SettingsKey.repositoryPath)
    }

    func getAPIKey(for service: APIService) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: service.keychainKey,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let key = String(data: data, encoding: .utf8) else {
            return nil
        }

        return key
    }

    func setAPIKey(_ key: String, for service: APIService) throws {
        // Delete existing key first
        try? deleteAPIKey(for: service)

        guard let keyData = key.data(using: .utf8) else {
            throw KnowledgeToolError.apiError("Invalid API key format")
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: service.keychainKey,
            kSecValueData as String: keyData,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]

        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            throw KnowledgeToolError.apiError("Failed to save API key to Keychain")
        }
    }

    func deleteAPIKey(for service: APIService) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: service.keychainKey
        ]

        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KnowledgeToolError.apiError("Failed to delete API key from Keychain")
        }
    }

    func hasAPIKey(for service: APIService) -> Bool {
        getAPIKey(for: service) != nil
    }

    func validateAPIKeys() -> [APIService] {
        APIService.allCases.filter { !hasAPIKey(for: $0) }
    }
}
