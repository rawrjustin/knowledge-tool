import Foundation

/// Protocol defining the interface for character storage
/// Both LocalCharacterRepository and SupabaseCharacterRepository conform to this
protocol CharacterRepositoryProtocol: Actor {
    /// Load all accessible characters
    func loadAllCharacters() async throws -> [Character]

    /// Save a character (overwrites existing)
    func saveCharacter(_ character: Character) async throws

    /// Save character as a new version
    func saveCharacterAsNewVersion(_ character: Character) async throws -> Character

    /// Create a new character
    func createCharacter(
        name: String,
        markdownContent: String,
        systemPromptType: SystemPromptType
    ) async throws -> Character

    /// Create or update a knowledge file for a character
    /// This is the key method for dialog examples - it handles upsert semantics
    func createKnowledgeFile(
        for character: Character,
        fileName: String,
        content: String
    ) async throws -> KnowledgeFile

    /// Save a knowledge file (update existing)
    func saveKnowledgeFile(_ knowledgeFile: KnowledgeFile) async throws

    /// Delete a knowledge file
    func deleteKnowledgeFile(_ knowledgeFile: KnowledgeFile) async throws

    /// Delete a character
    func deleteCharacter(_ character: Character) async throws
}

/// Configuration for Supabase sync
struct SupabaseSyncConfig: Sendable {
    let supabaseURL: String
    let supabaseAnonKey: String
    let syncEnabled: Bool

    var isConfigured: Bool {
        !supabaseURL.isEmpty && !supabaseAnonKey.isEmpty
    }
}

/// Combined repository that syncs between local and Supabase
/// Uses local as primary with Supabase as secondary/sync target
/// This should be the ONLY repository used by ViewModels to ensure consistent sync
actor CombinedCharacterRepository {
    private let local: LocalCharacterRepository
    private var supabase: SupabaseCharacterRepository?
    private var syncEnabled: Bool

    init(localBaseURL: URL, syncConfig: SupabaseSyncConfig) {
        self.local = LocalCharacterRepository(baseURL: localBaseURL)
        self.syncEnabled = syncConfig.syncEnabled && syncConfig.isConfigured

        // Initialize Supabase if configured
        if syncConfig.isConfigured, let url = URL(string: syncConfig.supabaseURL) {
            let service = SupabaseService(url: url, anonKey: syncConfig.supabaseAnonKey)
            self.supabase = SupabaseCharacterRepository(supabase: service)
        }
    }

    /// Update sync configuration (call when settings change)
    func updateSyncConfiguration(_ config: SupabaseSyncConfig) {
        syncEnabled = config.syncEnabled && config.isConfigured

        if config.isConfigured, let url = URL(string: config.supabaseURL) {
            let service = SupabaseService(url: url, anonKey: config.supabaseAnonKey)
            supabase = SupabaseCharacterRepository(supabase: service)
        } else {
            supabase = nil
        }

        NSLog("[CombinedRepository] Sync configuration updated. Enabled: %@", syncEnabled ? "true" : "false")
    }

    /// Whether sync is currently enabled and configured
    var isSyncEnabled: Bool {
        syncEnabled && supabase != nil
    }

    // MARK: - Character Operations

    /// Load all characters from local, merging with Supabase if sync enabled
    func loadAllCharacters() async throws -> [Character] {
        var characters = try await local.loadAllCharacters()

        // If sync enabled, also fetch from Supabase and merge
        if syncEnabled, let supabase = supabase {
            do {
                let remoteCharacters = try await supabase.loadAllCharacters()
                // Merge: prefer local versions, add remote-only characters
                let localNames = Set(characters.map { $0.name.lowercased() })
                let remoteOnly = remoteCharacters.filter { !localNames.contains($0.name.lowercased()) }
                characters.append(contentsOf: remoteOnly)
                NSLog("[CombinedRepository] Merged %d remote-only characters", remoteOnly.count)
            } catch {
                NSLog("[CombinedRepository] Failed to fetch from Supabase: %@", error.localizedDescription)
            }
        }

        return characters.sorted { $0.name < $1.name }
    }

    /// Save a character to local, then sync to Supabase if enabled
    func saveCharacter(_ character: Character) async throws {
        // Save locally first
        try await local.saveCharacter(character)
        NSLog("[CombinedRepository] Saved character locally: %@", character.name)

        // Sync to Supabase
        if syncEnabled, let supabase = supabase {
            Task {
                do {
                    try await supabase.updateCharacter(character)
                    NSLog("[CombinedRepository] Synced character to Supabase: %@", character.name)
                } catch {
                    NSLog("[CombinedRepository] Failed to sync character to Supabase: %@", error.localizedDescription)
                }
            }
        }
    }

    /// Create a new character locally, then sync to Supabase
    func createCharacter(
        name: String,
        markdownContent: String,
        systemPromptType: SystemPromptType = .conversational
    ) async throws -> Character {
        let character = try await local.createCharacter(
            name: name,
            markdownContent: markdownContent,
            systemPromptType: systemPromptType
        )
        NSLog("[CombinedRepository] Created character locally: %@", name)

        // Sync to Supabase
        if syncEnabled, let supabase = supabase {
            Task {
                do {
                    _ = try await supabase.createCharacter(
                        name: name,
                        markdownContent: markdownContent,
                        systemPromptType: systemPromptType
                    )
                    NSLog("[CombinedRepository] Synced new character to Supabase: %@", name)
                } catch {
                    NSLog("[CombinedRepository] Failed to sync new character to Supabase: %@", error.localizedDescription)
                }
            }
        }

        return character
    }

    /// Save character as new version
    func saveCharacterAsNewVersion(_ character: Character) async throws -> Character {
        let newVersion = try await local.saveCharacterAsNewVersion(character)
        NSLog("[CombinedRepository] Saved new version locally: %@ v%d", character.name, newVersion.version)

        if syncEnabled, let supabase = supabase {
            Task {
                do {
                    _ = try await supabase.saveCharacterAsNewVersion(character)
                    NSLog("[CombinedRepository] Synced new version to Supabase: %@", character.name)
                } catch {
                    NSLog("[CombinedRepository] Failed to sync new version to Supabase: %@", error.localizedDescription)
                }
            }
        }

        return newVersion
    }

    /// Load all versions of a character
    func loadAllVersions(for characterName: String) async throws -> [Character] {
        return try await local.loadAllVersions(for: characterName)
    }

    // MARK: - Knowledge File Operations

    /// Create or update a knowledge file locally, then sync to Supabase
    /// This is the key method for dialog examples - handles upsert semantics
    func createKnowledgeFile(
        for character: Character,
        fileName: String,
        content: String
    ) async throws -> KnowledgeFile {
        // Save locally first
        let file = try await local.createKnowledgeFile(
            for: character,
            fileName: fileName,
            content: content
        )
        NSLog("[CombinedRepository] Created/updated knowledge file locally: %@/%@", character.name, fileName)

        // Sync to Supabase
        if syncEnabled, let supabase = supabase {
            Task {
                do {
                    // Look up the remote character by name to get the correct Supabase ID
                    let remoteChar = try await self.resolveRemoteCharacter(character, supabase: supabase)
                    _ = try await supabase.createKnowledgeFile(
                        for: remoteChar,
                        fileName: fileName,
                        content: content
                    )
                    NSLog("[CombinedRepository] Synced knowledge file to Supabase: %@/%@", character.name, fileName)
                } catch {
                    NSLog("[CombinedRepository] Failed to sync knowledge file to Supabase: %@", error.localizedDescription)
                }
            }
        }

        return file
    }

    /// Save/update a knowledge file with character context for proper sync
    func saveKnowledgeFile(_ knowledgeFile: KnowledgeFile, for character: Character) async throws {
        try await local.saveKnowledgeFile(knowledgeFile)
        NSLog("[CombinedRepository] Saved knowledge file locally: %@", knowledgeFile.fileName)

        // Sync to Supabase - use createKnowledgeFile which handles upsert
        if syncEnabled, let supabase = supabase {
            Task {
                do {
                    // Look up the remote character by name to get the correct Supabase ID
                    let remoteChar = try await self.resolveRemoteCharacter(character, supabase: supabase)
                    _ = try await supabase.createKnowledgeFile(
                        for: remoteChar,
                        fileName: knowledgeFile.fileName,
                        content: knowledgeFile.content
                    )
                    NSLog("[CombinedRepository] Synced knowledge file update to Supabase: %@", knowledgeFile.fileName)
                } catch {
                    NSLog("[CombinedRepository] Failed to sync knowledge file update to Supabase: %@", error.localizedDescription)
                }
            }
        }
    }

    /// Delete a knowledge file locally, then sync deletion to Supabase
    func deleteKnowledgeFile(_ knowledgeFile: KnowledgeFile) async throws {
        try await local.deleteKnowledgeFile(knowledgeFile)
        NSLog("[CombinedRepository] Deleted knowledge file locally: %@", knowledgeFile.fileName)

        if syncEnabled, let supabase = supabase {
            Task {
                do {
                    try await supabase.deleteKnowledgeFile(knowledgeFile)
                    NSLog("[CombinedRepository] Synced knowledge file deletion to Supabase: %@", knowledgeFile.fileName)
                } catch {
                    NSLog("[CombinedRepository] Failed to sync knowledge file deletion to Supabase: %@", error.localizedDescription)
                }
            }
        }
    }

    /// Create a knowledge file in a source folder (Knowledge/sources/{uuid}/)
    /// This is used for the new source-based organization
    func createKnowledgeFileInSourceFolder(
        for character: Character,
        sourceId: UUID,
        fileName: String,
        content: String
    ) async throws -> KnowledgeFile {
        // Save locally first using source folder structure
        let file = try await local.createKnowledgeFileInSourceFolder(
            for: character,
            sourceId: sourceId,
            fileName: fileName,
            content: content
        )
        NSLog("[CombinedRepository] Created knowledge file in source folder: %@/sources/%@/%@", character.name, sourceId.uuidString, fileName)

        // Sync to Supabase - use the full path for proper storage
        if syncEnabled, let supabase = supabase {
            Task {
                do {
                    // For Supabase, we include the source path in the filename to preserve structure
                    let supabaseFileName = "sources/\(sourceId.uuidString)/\(fileName)"
                    _ = try await supabase.createKnowledgeFile(
                        for: character,
                        fileName: supabaseFileName,
                        content: content
                    )
                    NSLog("[CombinedRepository] Synced source folder file to Supabase: %@/%@", character.name, supabaseFileName)
                } catch {
                    NSLog("[CombinedRepository] Failed to sync source folder file to Supabase: %@", error.localizedDescription)
                }
            }
        }

        return file
    }

    /// Delete an entire source folder
    func deleteSourceFolder(for character: Character, sourceId: UUID) async throws {
        try await local.deleteSourceFolder(for: character, sourceId: sourceId)
        NSLog("[CombinedRepository] Deleted source folder locally: %@/sources/%@", character.name, sourceId.uuidString)

        // TODO: Sync deletion to Supabase (need to delete all files with matching source path prefix)
        if syncEnabled, let _ = supabase {
            NSLog("[CombinedRepository] Note: Supabase source folder cleanup not yet implemented")
        }
    }

    /// Save a knowledge file (update existing) - convenience method that finds character by ID
    /// Note: Supabase sync requires character context, so this attempts to find it
    func saveKnowledgeFile(_ knowledgeFile: KnowledgeFile) async throws {
        try await local.saveKnowledgeFile(knowledgeFile)
        NSLog("[CombinedRepository] Saved knowledge file locally: %@", knowledgeFile.fileName)

        // For Supabase sync, we need to find the character this file belongs to
        if syncEnabled, let supabase = supabase {
            Task {
                do {
                    // Find character by matching knowledge file
                    let characters = try await local.loadAllCharacters()
                    if let character = characters.first(where: { char in
                        char.knowledgeFiles.contains { $0.id == knowledgeFile.id }
                    }) {
                        _ = try await supabase.createKnowledgeFile(
                            for: character,
                            fileName: knowledgeFile.fileName,
                            content: knowledgeFile.content
                        )
                        NSLog("[CombinedRepository] Synced knowledge file update to Supabase: %@", knowledgeFile.fileName)
                    } else {
                        NSLog("[CombinedRepository] Could not find character for knowledge file: %@", knowledgeFile.fileName)
                    }
                } catch {
                    NSLog("[CombinedRepository] Failed to sync knowledge file update to Supabase: %@", error.localizedDescription)
                }
            }
        }
    }

    // MARK: - Character Deletion

    /// Delete a character from local and/or Supabase
    func deleteCharacter(_ character: Character) async throws {
        // Try local deletion (may not exist if remote-only)
        do {
            try await local.deleteCharacter(character)
            NSLog("[CombinedRepository] Deleted character locally: %@", character.name)
        } catch {
            NSLog("[CombinedRepository] Local deletion skipped (may be remote-only): %@", error.localizedDescription)
        }

        // Try Supabase deletion
        if let supabase = supabase {
            do {
                try await supabase.deleteCharacter(character)
                NSLog("[CombinedRepository] Deleted character from Supabase: %@", character.name)
            } catch {
                NSLog("[CombinedRepository] Supabase deletion skipped: %@", error.localizedDescription)
            }
        }
    }

    // MARK: - Remote Character Resolution

    /// Look up the remote character by name to get the correct Supabase-assigned ID.
    /// Falls back to the local character if no remote match is found.
    private func resolveRemoteCharacter(_ character: Character, supabase: SupabaseCharacterRepository) async throws -> Character {
        let remoteCharacters = try await supabase.loadAllCharacters()
        if let remote = remoteCharacters.first(where: { $0.name.lowercased() == character.name.lowercased() }) {
            return remote
        }
        return character
    }

    // MARK: - Bulk Sync Operations

    /// Sync all local characters to Supabase (for initial sync or manual sync)
    func syncAllToSupabase() async throws {
        guard syncEnabled, let supabase = supabase else {
            return
        }

        let localCharacters = try await local.loadAllCharacters()
        NSLog("[CombinedRepository] Starting bulk sync of %d characters", localCharacters.count)

        // Fetch existing remote characters to avoid duplicate inserts
        let remoteCharacters = try await supabase.loadAllCharacters()
        var remoteByName: [String: Character] = [:]
        for rc in remoteCharacters {
            remoteByName[rc.name.lowercased()] = rc
        }

        for character in localCharacters {
            do {
                if let existing = remoteByName[character.name.lowercased()] {
                    // Update existing remote character using a copy with the remote ID
                    let synced = Character(
                        id: existing.id,
                        name: character.name,
                        directoryPath: character.directoryPath,
                        personaFileName: character.personaFileName,
                        markdownContent: character.markdownContent,
                        knowledgeFiles: character.knowledgeFiles,
                        sha: character.sha,
                        systemPromptType: character.systemPromptType,
                        version: character.version
                    )
                    try await supabase.updateCharacter(synced)
                    NSLog("[CombinedRepository] Updated existing character: %@", character.name)
                } else {
                    // Create new remote character and track the returned character with Supabase ID
                    let created = try await supabase.createCharacter(
                        name: character.name,
                        markdownContent: character.markdownContent,
                        systemPromptType: character.systemPromptType
                    )
                    remoteByName[character.name.lowercased()] = created
                    NSLog("[CombinedRepository] Created new character: %@", character.name)
                }

                // Sync knowledge files using the remote ID
                let remoteChar = remoteByName[character.name.lowercased()] ?? character
                for knowledgeFile in character.knowledgeFiles {
                    _ = try await supabase.createKnowledgeFile(
                        for: remoteChar,
                        fileName: knowledgeFile.fileName,
                        content: knowledgeFile.content
                    )
                }

                NSLog("[CombinedRepository] Synced character with %d knowledge files: %@", character.knowledgeFiles.count, character.name)
            } catch {
                NSLog("[CombinedRepository] Failed to sync character '%@': %@", character.name, error.localizedDescription)
            }
        }

        NSLog("[CombinedRepository] Bulk sync completed")
    }

    /// Pull all characters from Supabase to local (for initial download)
    func pullAllFromSupabase() async throws {
        guard syncEnabled, let supabase = supabase else {
            return
        }

        let remoteCharacters = try await supabase.loadAllCharacters()
        NSLog("[CombinedRepository] Pulling %d characters from Supabase", remoteCharacters.count)

        for character in remoteCharacters {
            do {
                // Check if character exists locally
                let localCharacters = try await local.loadAllCharacters()
                let existsLocally = localCharacters.contains { $0.name.lowercased() == character.name.lowercased() }

                if !existsLocally {
                    // Create locally
                    _ = try await local.createCharacter(
                        name: character.name,
                        markdownContent: character.markdownContent,
                        systemPromptType: character.systemPromptType
                    )

                    // TODO: Also pull knowledge files
                    NSLog("[CombinedRepository] Pulled new character from Supabase: %@", character.name)
                }
            } catch {
                NSLog("[CombinedRepository] Failed to pull character '%@': %@", character.name, error.localizedDescription)
            }
        }

        NSLog("[CombinedRepository] Pull completed")
    }
}
