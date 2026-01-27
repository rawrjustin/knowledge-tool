import Foundation

@Observable
final class APIKeyManager {
    // MARK: - Settings Keys
    private enum SettingsKey {
        static let repositoryPath = "characterRepositoryPath"
        static let githubOwner = "github_repo_owner"
        static let githubRepo = "github_repo_name"
        static let githubClientID = "github_client_id"
        static let githubClientSecret = "github_client_secret"
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
        case pinecone = "Pinecone"
        case gitHubPAT = "GitHub PAT"

        var storageKey: String {
            switch self {
            case .assemblyAI: return "apikey_assemblyai"
            case .openAI: return "apikey_openai"
            case .perplexity: return "apikey_perplexity"
            case .pinecone: return "apikey_pinecone"
            case .gitHubPAT: return "apikey_github_pat"
            }
        }

        var displayName: String { rawValue }
    }

    // MARK: - Pinecone Settings
    private enum PineconeSettingsKey {
        static let indexName = "pinecone_index_name"
        static let environment = "pinecone_environment"
    }

    var pineconeIndexName: String {
        get {
            UserDefaults.standard.string(forKey: PineconeSettingsKey.indexName) ?? ""
        }
        set {
            UserDefaults.standard.set(newValue, forKey: PineconeSettingsKey.indexName)
        }
    }

    var pineconeEnvironment: PineconeEnvironment {
        get {
            if let raw = UserDefaults.standard.string(forKey: PineconeSettingsKey.environment),
               let env = PineconeEnvironment(rawValue: raw) {
                return env
            }
            return .development
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: PineconeSettingsKey.environment)
            // Update index name based on environment
            pineconeIndexName = newValue.defaultIndexName
        }
    }

    enum PineconeEnvironment: String, CaseIterable {
        case development = "development"
        case production = "production"

        var displayName: String {
            switch self {
            case .development: return "Development"
            case .production: return "Production"
            }
        }

        var defaultIndexName: String {
            // Return empty string - users must configure their own index
            return ""
        }
    }

    // MARK: - GitHub Repository Settings
    var githubRepoOwner: String {
        get {
            UserDefaults.standard.string(forKey: SettingsKey.githubOwner) ?? ""
        }
        set {
            if newValue.isEmpty {
                UserDefaults.standard.removeObject(forKey: SettingsKey.githubOwner)
            } else {
                UserDefaults.standard.set(newValue, forKey: SettingsKey.githubOwner)
            }
        }
    }

    var githubRepoName: String {
        get {
            UserDefaults.standard.string(forKey: SettingsKey.githubRepo) ?? ""
        }
        set {
            if newValue.isEmpty {
                UserDefaults.standard.removeObject(forKey: SettingsKey.githubRepo)
            } else {
                UserDefaults.standard.set(newValue, forKey: SettingsKey.githubRepo)
            }
        }
    }

    var hasGitHubRepoConfigured: Bool {
        !githubRepoOwner.isEmpty && !githubRepoName.isEmpty
    }

    // MARK: - GitHub OAuth Settings (Optional - for contributors)
    var githubClientID: String {
        get {
            UserDefaults.standard.string(forKey: SettingsKey.githubClientID) ?? ""
        }
        set {
            if newValue.isEmpty {
                UserDefaults.standard.removeObject(forKey: SettingsKey.githubClientID)
            } else {
                UserDefaults.standard.set(newValue, forKey: SettingsKey.githubClientID)
            }
        }
    }

    var githubClientSecret: String {
        get {
            UserDefaults.standard.string(forKey: SettingsKey.githubClientSecret) ?? ""
        }
        set {
            if newValue.isEmpty {
                UserDefaults.standard.removeObject(forKey: SettingsKey.githubClientSecret)
            } else {
                UserDefaults.standard.set(newValue, forKey: SettingsKey.githubClientSecret)
            }
        }
    }

    var hasGitHubOAuthConfigured: Bool {
        !githubClientID.isEmpty && !githubClientSecret.isEmpty
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

    // MARK: - API Key Management (UserDefaults)

    func getAPIKey(for service: APIService) -> String? {
        return UserDefaults.standard.string(forKey: service.storageKey)
    }

    func setAPIKey(_ key: String, for service: APIService) {
        if key.isEmpty {
            UserDefaults.standard.removeObject(forKey: service.storageKey)
        } else {
            UserDefaults.standard.set(key, forKey: service.storageKey)
        }
    }

    func deleteAPIKey(for service: APIService) {
        UserDefaults.standard.removeObject(forKey: service.storageKey)
    }

    func hasAPIKey(for service: APIService) -> Bool {
        getAPIKey(for: service) != nil
    }

    func validateAPIKeys() -> [APIService] {
        APIService.allCases.filter { !hasAPIKey(for: $0) }
    }
}
