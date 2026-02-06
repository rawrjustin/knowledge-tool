import Foundation
import Supabase

// MARK: - Supabase Configuration

/// Configuration for Supabase connection
struct SupabaseConfig: Sendable {
    let url: URL
    let anonKey: String

    /// Shared configuration - set once at app startup before any concurrent access
    nonisolated(unsafe) static var shared: SupabaseConfig?

    static func configure(url: String, anonKey: String) throws {
        guard let supabaseURL = URL(string: url) else {
            throw SupabaseServiceError.invalidConfiguration("Invalid Supabase URL")
        }
        shared = SupabaseConfig(url: supabaseURL, anonKey: anonKey)
    }

    /// Configure from APIKeyManager
    static func configureFromAPIKeyManager(_ manager: APIKeyManager) throws {
        guard manager.hasSupabaseConfigured else {
            throw SupabaseServiceError.notConfigured
        }
        try configure(url: manager.supabaseURL, anonKey: manager.supabaseAnonKey)
    }
}

// MARK: - Database Models

/// Character visibility levels
enum CharacterVisibility: String, Codable {
    case `private` = "private"
    case shared = "shared"
    case `public` = "public"
}

/// Share permission levels
enum SharePermission: String, Codable {
    case viewer = "viewer"
    case editor = "editor"
    case admin = "admin"
}

/// User profile from Supabase
struct SupabaseProfile: Codable, Identifiable {
    let id: UUID
    let email: String?
    let displayName: String?
    let avatarUrl: String?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case email
        case displayName = "display_name"
        case avatarUrl = "avatar_url"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// Character record from Supabase
struct SupabaseCharacter: Codable, Identifiable {
    let id: UUID
    let ownerId: UUID
    var name: String
    var slug: String
    var description: String?
    var visibility: CharacterVisibility
    var personaStoragePath: String?
    var personaContent: String?
    var systemPromptType: String
    var version: Int
    var sourceType: String?
    var sourceUrls: [String]?
    var pineconeNamespace: String?
    let createdAt: Date
    var updatedAt: Date

    // Joined data
    var knowledgeFiles: [SupabaseKnowledgeFile]?
    var ownerProfile: SupabaseProfile?

    enum CodingKeys: String, CodingKey {
        case id
        case ownerId = "owner_id"
        case name
        case slug
        case description
        case visibility
        case personaStoragePath = "persona_storage_path"
        case personaContent = "persona_content"
        case systemPromptType = "system_prompt_type"
        case version
        case sourceType = "source_type"
        case sourceUrls = "source_urls"
        case pineconeNamespace = "pinecone_namespace"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case knowledgeFiles = "knowledge_files"
        case ownerProfile = "profiles"
    }
}

/// Knowledge file record from Supabase
struct SupabaseKnowledgeFile: Codable, Identifiable {
    let id: UUID
    let characterId: UUID
    var fileName: String
    var fileType: String
    var mimeType: String?
    var storagePath: String
    var content: String?
    var fileSizeBytes: Int?
    var wordCount: Int?
    var sourceUrl: String?
    var sourceTitle: String?
    let createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case characterId = "character_id"
        case fileName = "file_name"
        case fileType = "file_type"
        case mimeType = "mime_type"
        case storagePath = "storage_path"
        case content
        case fileSizeBytes = "file_size_bytes"
        case wordCount = "word_count"
        case sourceUrl = "source_url"
        case sourceTitle = "source_title"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// Character share record
struct SupabaseCharacterShare: Codable, Identifiable {
    let id: UUID
    let characterId: UUID
    let sharedWith: UUID
    let permission: SharePermission
    let sharedBy: UUID
    let createdAt: Date

    // Joined data
    var sharedWithProfile: SupabaseProfile?

    enum CodingKeys: String, CodingKey {
        case id
        case characterId = "character_id"
        case sharedWith = "shared_with"
        case permission
        case sharedBy = "shared_by"
        case createdAt = "created_at"
        case sharedWithProfile = "profiles"
    }
}

// MARK: - Insert/Update DTOs

struct CharacterInsert: Encodable {
    let ownerId: UUID
    let name: String
    let slug: String
    let description: String?
    let visibility: String
    let personaStoragePath: String?
    let personaContent: String?
    let systemPromptType: String
    let version: Int
    let sourceType: String?
    let sourceUrls: [String]?

    enum CodingKeys: String, CodingKey {
        case ownerId = "owner_id"
        case name
        case slug
        case description
        case visibility
        case personaStoragePath = "persona_storage_path"
        case personaContent = "persona_content"
        case systemPromptType = "system_prompt_type"
        case version
        case sourceType = "source_type"
        case sourceUrls = "source_urls"
    }
}

struct KnowledgeFileInsert: Encodable {
    let characterId: UUID
    let fileName: String
    let fileType: String
    let storagePath: String
    let content: String?
    let fileSizeBytes: Int?
    let wordCount: Int?
    let sourceUrl: String?
    let sourceTitle: String?

    enum CodingKeys: String, CodingKey {
        case characterId = "character_id"
        case fileName = "file_name"
        case fileType = "file_type"
        case storagePath = "storage_path"
        case content
        case fileSizeBytes = "file_size_bytes"
        case wordCount = "word_count"
        case sourceUrl = "source_url"
        case sourceTitle = "source_title"
    }
}

struct CharacterShareInsert: Encodable {
    let characterId: UUID
    let sharedWith: UUID
    let permission: String
    let sharedBy: UUID

    enum CodingKeys: String, CodingKey {
        case characterId = "character_id"
        case sharedWith = "shared_with"
        case permission
        case sharedBy = "shared_by"
    }
}

// MARK: - Supabase Service

/// Main service for interacting with Supabase
actor SupabaseService {
    private let client: SupabaseClient

    init() throws {
        guard let config = SupabaseConfig.shared else {
            throw SupabaseServiceError.notConfigured
        }

        self.client = SupabaseClient(
            supabaseURL: config.url,
            supabaseKey: config.anonKey
        )
    }

    // Convenience initializer with explicit config
    init(url: URL, anonKey: String) {
        self.client = SupabaseClient(
            supabaseURL: url,
            supabaseKey: anonKey
        )
    }

    // MARK: - Authentication

    /// Get current user ID
    var currentUserId: UUID? {
        get async {
            try? await client.auth.session.user.id
        }
    }

    /// Sign in with email and password
    func signIn(email: String, password: String) async throws {
        try await client.auth.signIn(email: email, password: password)
    }

    /// Sign up with email and password
    func signUp(email: String, password: String, displayName: String? = nil) async throws {
        try await client.auth.signUp(
            email: email,
            password: password,
            data: displayName.map { ["display_name": .string($0)] } ?? [:]
        )
    }

    /// Sign out
    func signOut() async throws {
        try await client.auth.signOut()
    }

    /// Check if user is authenticated
    var isAuthenticated: Bool {
        get async {
            (try? await client.auth.session) != nil
        }
    }

    // MARK: - Characters

    /// Fetch all accessible characters (owned, shared, public)
    func fetchCharacters(includeKnowledgeFiles: Bool = false) async throws -> [SupabaseCharacter] {
        var query = client
            .from("characters")
            .select(includeKnowledgeFiles
                ? "*, knowledge_files(*), profiles!owner_id(id, display_name, avatar_url)"
                : "*, profiles!owner_id(id, display_name, avatar_url)"
            )

        let response: [SupabaseCharacter] = try await query
            .order("updated_at", ascending: false)
            .execute()
            .value

        return response
    }

    /// Fetch a single character by ID
    func fetchCharacter(id: UUID) async throws -> SupabaseCharacter {
        let response: SupabaseCharacter = try await client
            .from("characters")
            .select("*, knowledge_files(*), profiles!owner_id(id, display_name, avatar_url)")
            .eq("id", value: id.uuidString)
            .single()
            .execute()
            .value

        return response
    }

    /// Create a new character
    func createCharacter(_ character: CharacterInsert) async throws -> SupabaseCharacter {
        let response: SupabaseCharacter = try await client
            .from("characters")
            .insert(character)
            .select("*")
            .single()
            .execute()
            .value

        return response
    }

    /// Update an existing character
    func updateCharacter(id: UUID, updates: [String: AnyJSON]) async throws -> SupabaseCharacter {
        let response: SupabaseCharacter = try await client
            .from("characters")
            .update(updates)
            .eq("id", value: id.uuidString)
            .select("*")
            .single()
            .execute()
            .value

        return response
    }

    /// Delete a character
    func deleteCharacter(id: UUID) async throws {
        try await client
            .from("characters")
            .delete()
            .eq("id", value: id.uuidString)
            .execute()
    }

    // MARK: - Knowledge Files

    /// Fetch knowledge files for a character
    func fetchKnowledgeFiles(characterId: UUID) async throws -> [SupabaseKnowledgeFile] {
        let response: [SupabaseKnowledgeFile] = try await client
            .from("knowledge_files")
            .select("*")
            .eq("character_id", value: characterId.uuidString)
            .order("file_name", ascending: true)
            .execute()
            .value

        return response
    }

    /// Create a knowledge file
    func createKnowledgeFile(_ file: KnowledgeFileInsert) async throws -> SupabaseKnowledgeFile {
        let response: SupabaseKnowledgeFile = try await client
            .from("knowledge_files")
            .insert(file)
            .select("*")
            .single()
            .execute()
            .value

        return response
    }

    /// Update a knowledge file
    func updateKnowledgeFile(id: UUID, updates: [String: AnyJSON]) async throws -> SupabaseKnowledgeFile {
        let response: SupabaseKnowledgeFile = try await client
            .from("knowledge_files")
            .update(updates)
            .eq("id", value: id.uuidString)
            .select("*")
            .single()
            .execute()
            .value

        return response
    }

    /// Delete a knowledge file
    func deleteKnowledgeFile(id: UUID) async throws {
        try await client
            .from("knowledge_files")
            .delete()
            .eq("id", value: id.uuidString)
            .execute()
    }

    // MARK: - Sharing

    /// Fetch shares for a character
    func fetchCharacterShares(characterId: UUID) async throws -> [SupabaseCharacterShare] {
        let response: [SupabaseCharacterShare] = try await client
            .from("character_shares")
            .select("*, profiles!shared_with(id, display_name, email, avatar_url)")
            .eq("character_id", value: characterId.uuidString)
            .execute()
            .value

        return response
    }

    /// Share a character with a user
    func shareCharacter(_ share: CharacterShareInsert) async throws -> SupabaseCharacterShare {
        let response: SupabaseCharacterShare = try await client
            .from("character_shares")
            .insert(share)
            .select("*, profiles!shared_with(id, display_name, email, avatar_url)")
            .single()
            .execute()
            .value

        return response
    }

    /// Remove a share
    func removeShare(id: UUID) async throws {
        try await client
            .from("character_shares")
            .delete()
            .eq("id", value: id.uuidString)
            .execute()
    }

    /// Find a user by email (for sharing)
    func findUserByEmail(_ email: String) async throws -> SupabaseProfile? {
        let response: [SupabaseProfile] = try await client
            .from("profiles")
            .select("*")
            .eq("email", value: email)
            .execute()
            .value

        return response.first
    }

    // MARK: - Storage

    /// Upload persona file to storage
    func uploadPersonaFile(userId: UUID, characterId: UUID, content: String) async throws -> String {
        let path = "\(userId.uuidString)/\(characterId.uuidString)/persona.md"
        let data = Data(content.utf8)

        try await client.storage
            .from("personas")
            .upload(
                path: path,
                file: data,
                options: FileOptions(contentType: "text/markdown", upsert: true)
            )

        return path
    }

    /// Download persona file from storage
    func downloadPersonaFile(path: String) async throws -> String {
        let data = try await client.storage
            .from("personas")
            .download(path: path)

        guard let content = String(data: data, encoding: .utf8) else {
            throw SupabaseServiceError.invalidData("Could not decode persona file")
        }

        return content
    }

    /// Upload knowledge file to storage
    func uploadKnowledgeFile(userId: UUID, characterId: UUID, fileName: String, content: String) async throws -> String {
        let path = "\(userId.uuidString)/\(characterId.uuidString)/\(fileName)"
        let data = Data(content.utf8)

        let mimeType: String
        if fileName.hasSuffix(".jsonl") || fileName.hasSuffix(".json") {
            mimeType = "application/json"
        } else if fileName.hasSuffix(".md") {
            mimeType = "text/markdown"
        } else {
            mimeType = "text/plain"
        }

        try await client.storage
            .from("knowledge")
            .upload(
                path: path,
                file: data,
                options: FileOptions(contentType: mimeType, upsert: true)
            )

        return path
    }

    /// Download knowledge file from storage
    func downloadKnowledgeFile(path: String) async throws -> String {
        let data = try await client.storage
            .from("knowledge")
            .download(path: path)

        guard let content = String(data: data, encoding: .utf8) else {
            throw SupabaseServiceError.invalidData("Could not decode knowledge file")
        }

        return content
    }

    /// Delete file from storage
    func deleteStorageFile(bucket: String, path: String) async throws {
        try await client.storage
            .from(bucket)
            .remove(paths: [path])
    }

    // MARK: - System Prompts

    /// Fetch the active system prompt for a given type
    func fetchActiveSystemPrompt(type: SystemPromptType) async throws -> SystemPromptTemplate {
        let response: [SystemPromptTemplate] = try await client
            .from("system_prompts")
            .select("*")
            .eq("prompt_type", value: type.rawValue)
            .eq("is_active", value: true)
            .order("version", ascending: false)
            .limit(1)
            .execute()
            .value

        guard let template = response.first else {
            throw SupabaseServiceError.invalidData("No active system prompt found for type: \(type.rawValue)")
        }

        return template
    }

    /// Fetch all system prompts (for admin/debugging)
    func fetchAllSystemPrompts() async throws -> [SystemPromptTemplate] {
        let response: [SystemPromptTemplate] = try await client
            .from("system_prompts")
            .select("*")
            .order("prompt_type", ascending: true)
            .order("version", ascending: false)
            .execute()
            .value

        return response
    }

    /// Fetch all active system prompts (one per type)
    func fetchAllActiveSystemPrompts() async throws -> [SystemPromptTemplate] {
        var templates: [SystemPromptTemplate] = []

        for type in SystemPromptType.allCases {
            if let template = try? await fetchActiveSystemPrompt(type: type) {
                templates.append(template)
            }
        }

        return templates
    }
}

// MARK: - Errors

enum SupabaseServiceError: LocalizedError {
    case notConfigured
    case invalidConfiguration(String)
    case notAuthenticated
    case invalidData(String)
    case uploadFailed(String)
    case downloadFailed(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Supabase is not configured. Please add your Supabase URL and key in Settings."
        case .invalidConfiguration(let message):
            return "Invalid Supabase configuration: \(message)"
        case .notAuthenticated:
            return "You must be signed in to perform this action."
        case .invalidData(let message):
            return "Invalid data: \(message)"
        case .uploadFailed(let message):
            return "Upload failed: \(message)"
        case .downloadFailed(let message):
            return "Download failed: \(message)"
        }
    }
}
