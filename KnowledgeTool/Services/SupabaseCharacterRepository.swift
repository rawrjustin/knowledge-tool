import Foundation

/// Repository for characters stored in Supabase
/// Bridges between Supabase models and local Character model
actor SupabaseCharacterRepository {
    private let supabase: SupabaseService

    init(supabase: SupabaseService) {
        self.supabase = supabase
    }

    // MARK: - Character Loading

    /// Load all accessible characters from Supabase
    func loadAllCharacters() async throws -> [Character] {
        let supabaseCharacters = try await supabase.fetchCharacters(includeKnowledgeFiles: true)

        // Convert characters and load knowledge file content from storage
        var characters: [Character] = []
        for supabaseChar in supabaseCharacters {
            var character = convertToLocal(supabaseChar)

            // Load actual content from storage for each knowledge file
            if let files = supabaseChar.knowledgeFiles, !files.isEmpty {
                NSLog("[SupabaseCharacterRepository] Loading %d knowledge files for %@", files.count, supabaseChar.name)
                var loadedFiles: [KnowledgeFile] = []
                for file in files {
                    let content: String
                    if let dbContent = file.content, !dbContent.isEmpty {
                        NSLog("[SupabaseCharacterRepository] Using DB content for %@ (%d chars)", file.fileName, dbContent.count)
                        content = dbContent
                    } else {
                        // Fetch from storage
                        NSLog("[SupabaseCharacterRepository] Fetching from storage: %@", file.storagePath)
                        do {
                            content = try await supabase.downloadKnowledgeFile(path: file.storagePath)
                            NSLog("[SupabaseCharacterRepository] Downloaded %@ (%d chars)", file.fileName, content.count)
                        } catch {
                            NSLog("[SupabaseCharacterRepository] Failed to download knowledge file %@: %@", file.fileName, error.localizedDescription)
                            content = ""
                        }
                    }

                    loadedFiles.append(KnowledgeFile(
                        id: file.id,
                        fileName: file.fileName,
                        content: content,
                        path: file.storagePath,
                        sha: "",
                        createdAt: file.createdAt,
                        modifiedAt: file.updatedAt
                    ))
                }
                character.knowledgeFiles = loadedFiles
            }

            characters.append(character)
        }

        return characters
    }

    /// Load a specific character by ID
    func loadCharacter(id: UUID) async throws -> Character {
        let supabaseCharacter = try await supabase.fetchCharacter(id: id)
        var character = convertToLocal(supabaseCharacter)

        // Load actual content from storage for each knowledge file
        if let files = supabaseCharacter.knowledgeFiles, !files.isEmpty {
            var loadedFiles: [KnowledgeFile] = []
            for file in files {
                let content: String
                if let dbContent = file.content, !dbContent.isEmpty {
                    content = dbContent
                } else {
                    // Fetch from storage
                    do {
                        content = try await supabase.downloadKnowledgeFile(path: file.storagePath)
                    } catch {
                        NSLog("[SupabaseCharacterRepository] Failed to download knowledge file %@: %@", file.fileName, error.localizedDescription)
                        content = ""
                    }
                }

                loadedFiles.append(KnowledgeFile(
                    id: file.id,
                    fileName: file.fileName,
                    content: content,
                    path: file.storagePath,
                    sha: "",
                    createdAt: file.createdAt,
                    modifiedAt: file.updatedAt
                ))
            }
            character.knowledgeFiles = loadedFiles
        }

        return character
    }

    /// Load knowledge files for a character, fetching content from storage if needed
    func loadKnowledgeFiles(for characterId: UUID) async throws -> [KnowledgeFile] {
        let supabaseFiles = try await supabase.fetchKnowledgeFiles(characterId: characterId)

        var files: [KnowledgeFile] = []
        for file in supabaseFiles {
            // If content is stored in DB, use it; otherwise fetch from storage
            let content: String
            if let dbContent = file.content, !dbContent.isEmpty {
                content = dbContent
            } else {
                content = try await supabase.downloadKnowledgeFile(path: file.storagePath)
            }

            let localFile = KnowledgeFile(
                id: file.id,
                fileName: file.fileName,
                content: content,
                path: file.storagePath,
                sha: "", // Not used for Supabase
                createdAt: file.createdAt,
                modifiedAt: file.updatedAt
            )
            files.append(localFile)
        }

        return files.sorted { $0.fileName < $1.fileName }
    }

    // MARK: - Character Saving

    /// Create a new character in Supabase
    func createCharacter(name: String, markdownContent: String, sourceType: String? = nil, sourceUrls: [String]? = nil) async throws -> Character {
        guard let userId = await supabase.currentUserId else {
            throw SupabaseServiceError.notAuthenticated
        }

        let slug = name.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "[^a-z0-9-]", with: "", options: .regularExpression)

        // Create character record first
        let insert = CharacterInsert(
            ownerId: userId,
            name: name,
            slug: slug,
            description: nil,
            visibility: "private",
            personaStoragePath: nil, // Will update after upload
            personaContent: nil, // Store in storage, not DB
            systemPromptType: "CSP",
            version: 1,
            sourceType: sourceType,
            sourceUrls: sourceUrls
        )

        var supabaseCharacter = try await supabase.createCharacter(insert)

        // Upload persona to storage
        let storagePath = try await supabase.uploadPersonaFile(
            userId: userId,
            characterId: supabaseCharacter.id,
            content: markdownContent
        )

        // Update character with storage path
        supabaseCharacter = try await supabase.updateCharacter(
            id: supabaseCharacter.id,
            updates: ["persona_storage_path": .string(storagePath)]
        )

        // Convert to local model
        var character = convertToLocal(supabaseCharacter)
        character.markdownContent = markdownContent

        return character
    }

    /// Update character persona content
    func updateCharacter(_ character: Character) async throws {
        guard let userId = await supabase.currentUserId else {
            throw SupabaseServiceError.notAuthenticated
        }

        // Upload updated persona to storage
        _ = try await supabase.uploadPersonaFile(
            userId: userId,
            characterId: character.id,
            content: character.markdownContent
        )

        // Update metadata in database
        try await supabase.updateCharacter(
            id: character.id,
            updates: [
                "name": .string(character.name),
                "system_prompt_type": .string(character.systemPromptType.rawValue),
                "version": .integer(character.version)
            ]
        )
    }

    /// Save character as a new version
    func saveCharacterAsNewVersion(_ character: Character) async throws -> Character {
        guard let userId = await supabase.currentUserId else {
            throw SupabaseServiceError.notAuthenticated
        }

        // Fetch current version
        let current = try await supabase.fetchCharacter(id: character.id)
        let newVersion = current.version + 1

        // Upload new persona
        _ = try await supabase.uploadPersonaFile(
            userId: userId,
            characterId: character.id,
            content: character.markdownContent
        )

        // Update version
        let updated = try await supabase.updateCharacter(
            id: character.id,
            updates: ["version": .integer(newVersion)]
        )

        var result = convertToLocal(updated)
        result.markdownContent = character.markdownContent
        return result
    }

    /// Delete a character
    func deleteCharacter(_ character: Character) async throws {
        // Delete storage files first
        if let storagePath = character.directoryPath.components(separatedBy: "/").last {
            // Storage paths follow pattern: userId/characterId/
            // We need to delete all files in that directory
            // For now, the cascade delete on the database will handle cleanup
        }

        try await supabase.deleteCharacter(id: character.id)
    }

    // MARK: - Knowledge File Management

    /// Detect file type from filename
    private func detectFileType(from fileName: String) -> String {
        // Handle source folder paths: sources/{uuid}/filename
        let baseName = fileName.components(separatedBy: "/").last ?? fileName

        if baseName == "metadata.json" {
            return "metadata"
        } else if baseName == "dialog_examples.jsonl" || fileName == "dialog_examples.jsonl" {
            return "dialogue"
        } else if baseName == "transcript.txt" || baseName.hasPrefix("transcript_") {
            return "transcript"
        } else if baseName == "knowledge.jsonl" || baseName.hasPrefix("knowledge_") {
            return "knowledge"
        } else if baseName == "summary.md" {
            return "summary"
        } else if fileName.contains("combined") {
            return "combined"
        } else {
            return "custom"
        }
    }

    /// Create or update a knowledge file for a character
    /// This handles the upsert pattern needed for dialog_examples.jsonl which overwrites on each save
    func createKnowledgeFile(for character: Character, fileName: String, content: String, fileType: String? = nil, sourceUrl: String? = nil, sourceTitle: String? = nil) async throws -> KnowledgeFile {
        guard let userId = await supabase.currentUserId else {
            throw SupabaseServiceError.notAuthenticated
        }

        // Determine file type
        let resolvedFileType = fileType ?? detectFileType(from: fileName)

        // Upload to storage (upsert: true handles overwriting)
        let storagePath = try await supabase.uploadKnowledgeFile(
            userId: userId,
            characterId: character.id,
            fileName: fileName,
            content: content
        )

        // Calculate word count
        let wordCount = content.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .count

        // Check if file already exists for this character
        let existingFiles = try await supabase.fetchKnowledgeFiles(characterId: character.id)
        if let existingFile = existingFiles.first(where: { $0.fileName == fileName }) {
            // Update existing file
            let updated = try await supabase.updateKnowledgeFile(
                id: existingFile.id,
                updates: [
                    "storage_path": .string(storagePath),
                    "word_count": .integer(wordCount),
                    "file_size_bytes": .integer(content.utf8.count)
                ]
            )

            return KnowledgeFile(
                id: updated.id,
                fileName: updated.fileName,
                content: content,
                path: updated.storagePath,
                sha: "",
                createdAt: updated.createdAt,
                modifiedAt: updated.updatedAt
            )
        }

        // Create new database record
        let insert = KnowledgeFileInsert(
            characterId: character.id,
            fileName: fileName,
            fileType: resolvedFileType,
            storagePath: storagePath,
            content: nil, // Store in storage, not DB
            fileSizeBytes: content.utf8.count,
            wordCount: wordCount,
            sourceUrl: sourceUrl,
            sourceTitle: sourceTitle
        )

        let supabaseFile = try await supabase.createKnowledgeFile(insert)

        return KnowledgeFile(
            id: supabaseFile.id,
            fileName: supabaseFile.fileName,
            content: content,
            path: supabaseFile.storagePath,
            sha: "",
            createdAt: supabaseFile.createdAt,
            modifiedAt: supabaseFile.updatedAt
        )
    }

    /// Update a knowledge file
    func updateKnowledgeFile(_ file: KnowledgeFile, for character: Character) async throws {
        guard let userId = await supabase.currentUserId else {
            throw SupabaseServiceError.notAuthenticated
        }

        // Re-upload to storage
        _ = try await supabase.uploadKnowledgeFile(
            userId: userId,
            characterId: character.id,
            fileName: file.fileName,
            content: file.content
        )

        // Update word count in database
        let wordCount = file.wordCount

        try await supabase.updateKnowledgeFile(
            id: file.id,
            updates: [
                "word_count": .integer(wordCount),
                "file_size_bytes": .integer(file.content.utf8.count)
            ]
        )
    }

    /// Delete a knowledge file
    func deleteKnowledgeFile(_ file: KnowledgeFile) async throws {
        // Delete from storage
        try await supabase.deleteStorageFile(bucket: "knowledge", path: file.path)

        // Delete database record
        try await supabase.deleteKnowledgeFile(id: file.id)
    }

    // MARK: - Sharing

    /// Share a character with another user by email
    func shareCharacter(_ character: Character, withEmail email: String, permission: SharePermission) async throws {
        guard let userId = await supabase.currentUserId else {
            throw SupabaseServiceError.notAuthenticated
        }

        // Find user by email
        guard let targetUser = try await supabase.findUserByEmail(email) else {
            throw SupabaseCharacterRepositoryError.userNotFound(email)
        }

        let share = CharacterShareInsert(
            characterId: character.id,
            sharedWith: targetUser.id,
            permission: permission.rawValue,
            sharedBy: userId
        )

        _ = try await supabase.shareCharacter(share)

        // Update character visibility if needed
        let currentChar = try await supabase.fetchCharacter(id: character.id)
        if currentChar.visibility == .private {
            try await supabase.updateCharacter(
                id: character.id,
                updates: ["visibility": .string("shared")]
            )
        }
    }

    /// Get shares for a character
    func getShares(for character: Character) async throws -> [CharacterShare] {
        let supabaseShares = try await supabase.fetchCharacterShares(characterId: character.id)
        return supabaseShares.map { share in
            CharacterShare(
                id: share.id,
                userEmail: share.sharedWithProfile?.email ?? "Unknown",
                userName: share.sharedWithProfile?.displayName ?? "Unknown",
                permission: share.permission,
                createdAt: share.createdAt
            )
        }
    }

    /// Remove a share
    func removeShare(id: UUID) async throws {
        try await supabase.removeShare(id: id)
    }

    /// Update character visibility
    func updateVisibility(_ character: Character, to visibility: CharacterVisibility) async throws {
        try await supabase.updateCharacter(
            id: character.id,
            updates: ["visibility": .string(visibility.rawValue)]
        )
    }

    // MARK: - Conversion Helpers

    /// Convert Supabase character to local Character model
    private func convertToLocal(_ supabase: SupabaseCharacter) -> Character {
        let knowledgeFiles = supabase.knowledgeFiles?.map { file in
            KnowledgeFile(
                id: file.id,
                fileName: file.fileName,
                content: file.content ?? "",
                path: file.storagePath,
                sha: "",
                createdAt: file.createdAt,
                modifiedAt: file.updatedAt
            )
        } ?? []

        let systemPromptType: SystemPromptType
        switch supabase.systemPromptType {
        case "ASP": systemPromptType = .action
        case "RSP": systemPromptType = .roleplay
        default: systemPromptType = .conversational
        }

        return Character(
            id: supabase.id,
            name: supabase.name,
            directoryPath: "Supabase/\(supabase.slug)",
            personaFileName: "persona.md",
            markdownContent: supabase.personaContent ?? "",
            knowledgeFiles: knowledgeFiles,
            sha: "",
            systemPromptType: systemPromptType,
            version: supabase.version,
            createdAt: supabase.createdAt,
            lastModified: supabase.updatedAt,
            isLocalOnly: false
        )
    }
}

// MARK: - Supporting Types

/// Represents a character share in the UI
struct CharacterShare: Identifiable {
    let id: UUID
    let userEmail: String
    let userName: String
    let permission: SharePermission
    let createdAt: Date

    var permissionDisplayName: String {
        switch permission {
        case .viewer: return "Can view"
        case .editor: return "Can edit"
        case .admin: return "Admin"
        }
    }
}

// MARK: - Errors

enum SupabaseCharacterRepositoryError: LocalizedError {
    case userNotFound(String)
    case characterNotFound(UUID)
    case insufficientPermissions

    var errorDescription: String? {
        switch self {
        case .userNotFound(let email):
            return "No user found with email: \(email)"
        case .characterNotFound(let id):
            return "Character not found: \(id)"
        case .insufficientPermissions:
            return "You don't have permission to perform this action."
        }
    }
}
