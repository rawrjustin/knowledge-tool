import Foundation

@Observable
final class APIKeyManager {
    // MARK: - Settings Keys
    private enum SettingsKey {
        static let repositoryPath = "characterRepositoryPath"
        static let supabaseURL = "supabase_url"
        static let supabaseAnonKey = "supabase_anon_key"
        static let supabaseSyncEnabled = "supabase_sync_enabled"
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
        case sportsDataIO = "SportsData.io"

        var storageKey: String {
            switch self {
            case .assemblyAI: return "apikey_assemblyai"
            case .openAI: return "apikey_openai"
            case .perplexity: return "apikey_perplexity"
            case .pinecone: return "apikey_pinecone"
            case .sportsDataIO: return "apikey_sportsdataio"
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

    // MARK: - Supabase Settings

    var supabaseURL: String {
        get {
            UserDefaults.standard.string(forKey: SettingsKey.supabaseURL) ?? ""
        }
        set {
            if newValue.isEmpty {
                UserDefaults.standard.removeObject(forKey: SettingsKey.supabaseURL)
            } else {
                UserDefaults.standard.set(newValue, forKey: SettingsKey.supabaseURL)
            }
        }
    }

    var supabaseAnonKey: String {
        get {
            UserDefaults.standard.string(forKey: SettingsKey.supabaseAnonKey) ?? ""
        }
        set {
            if newValue.isEmpty {
                UserDefaults.standard.removeObject(forKey: SettingsKey.supabaseAnonKey)
            } else {
                UserDefaults.standard.set(newValue, forKey: SettingsKey.supabaseAnonKey)
            }
        }
    }

    var supabaseSyncEnabled: Bool {
        get {
            UserDefaults.standard.bool(forKey: SettingsKey.supabaseSyncEnabled)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: SettingsKey.supabaseSyncEnabled)
        }
    }

    var hasSupabaseConfigured: Bool {
        !supabaseURL.isEmpty && !supabaseAnonKey.isEmpty
    }

    /// Validate Supabase URL format
    var isSupabaseURLValid: Bool {
        guard !supabaseURL.isEmpty,
              let url = URL(string: supabaseURL),
              url.scheme == "https",
              url.host?.contains("supabase") == true else {
            return false
        }
        return true
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
        guard let key = UserDefaults.standard.string(forKey: service.storageKey) else {
            return nil
        }
        // Return cleaned key (trimmed, no surrounding quotes)
        let cleaned = cleanAPIKey(key)
        return cleaned.isEmpty ? nil : cleaned
    }

    func setAPIKey(_ key: String, for service: APIService) {
        // Clean the key before storing
        let cleanedKey = cleanAPIKey(key)
        if cleanedKey.isEmpty {
            UserDefaults.standard.removeObject(forKey: service.storageKey)
        } else {
            UserDefaults.standard.set(cleanedKey, forKey: service.storageKey)
        }
    }

    /// Clean an API key by removing whitespace and surrounding quotes
    private func cleanAPIKey(_ key: String) -> String {
        var cleaned = key.trimmingCharacters(in: .whitespacesAndNewlines)
        // Remove surrounding quotes if present
        if cleaned.hasPrefix("\"") && cleaned.hasSuffix("\"") && cleaned.count >= 2 {
            cleaned = String(cleaned.dropFirst().dropLast())
        }
        if cleaned.hasPrefix("'") && cleaned.hasSuffix("'") && cleaned.count >= 2 {
            cleaned = String(cleaned.dropFirst().dropLast())
        }
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
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
