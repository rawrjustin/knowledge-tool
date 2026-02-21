import Foundation

/// Repository for characters stored in Supabase
/// Bridges between Supabase models and local Character model
actor SupabaseCharacterRepository {
    private let supabase: SupabaseService

    /// Fixed storage path prefix for anonymous/no-auth usage
    private static let storagePath = "default"

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
    func createCharacter(
        name: String,
        markdownContent: String,
        systemPromptType: SystemPromptType = .conversational,
        sourceType: String? = nil,
        sourceUrls: [String]? = nil
    ) async throws -> Character {
        let slug = name.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "[^a-z0-9-]", with: "", options: .regularExpression)

        // Use authenticated user ID if available, otherwise nil (owner_id is nullable)
        let userId = await supabase.currentUserId

        // Create character record first
        let insert = CharacterInsert(
            ownerId: userId,
            name: name,
            slug: slug,
            description: nil,
            personaStoragePath: nil,
            personaContent: markdownContent,
            systemPromptType: systemPromptType.rawValue,
            version: 1,
            sourceType: sourceType,
            sourceUrls: sourceUrls
        )

        var supabaseCharacter = try await supabase.createCharacter(insert)

        // Try to upload persona to storage, fall back to DB-only storage
        let storagePrefix = userId?.uuidString ?? Self.storagePath
        do {
            let storagePath = try await supabase.uploadPersonaFile(
                userId: UUID(uuidString: storagePrefix) ?? UUID(),
                characterId: supabaseCharacter.id,
                content: markdownContent
            )

            supabaseCharacter = try await supabase.updateCharacter(
                id: supabaseCharacter.id,
                updates: ["persona_storage_path": .string(storagePath)]
            )
        } catch {
            NSLog("[SupabaseCharacterRepository] Storage upload failed, using DB content: %@", error.localizedDescription)
            // Content is already stored as persona_content in the insert
        }

        // Convert to local model
        var character = convertToLocal(supabaseCharacter)
        character.markdownContent = markdownContent

        return character
    }

    /// Update character persona content
    func updateCharacter(_ character: Character) async throws {
        let slug = character.name.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "[^a-z0-9-]", with: "", options: .regularExpression)

        // Update persona content in database directly
        try await supabase.updateCharacter(
            id: character.id,
            updates: [
                "name": .string(character.name),
                "slug": .string(slug),
                "persona_content": .string(character.markdownContent),
                "system_prompt_type": .string(character.systemPromptType.rawValue),
                "version": .integer(character.version)
            ]
        )

        // Also try to upload to storage if possible
        let userId = await supabase.currentUserId
        let storagePrefix = userId?.uuidString ?? Self.storagePath
        do {
            _ = try await supabase.uploadPersonaFile(
                userId: UUID(uuidString: storagePrefix) ?? UUID(),
                characterId: character.id,
                content: character.markdownContent
            )
        } catch {
            NSLog("[SupabaseCharacterRepository] Storage upload failed, DB content updated: %@", error.localizedDescription)
        }
    }

    /// Save character as a new version
    func saveCharacterAsNewVersion(_ character: Character) async throws -> Character {
        // Fetch current version
        let current = try await supabase.fetchCharacter(id: character.id)
        let newVersion = current.version + 1

        // Update version and content
        let updated = try await supabase.updateCharacter(
            id: character.id,
            updates: [
                "version": .integer(newVersion),
                "persona_content": .string(character.markdownContent)
            ]
        )

        // Also try storage upload
        let userId = await supabase.currentUserId
        let storagePrefix = userId?.uuidString ?? Self.storagePath
        do {
            _ = try await supabase.uploadPersonaFile(
                userId: UUID(uuidString: storagePrefix) ?? UUID(),
                characterId: character.id,
                content: character.markdownContent
            )
        } catch {
            NSLog("[SupabaseCharacterRepository] Storage upload failed: %@", error.localizedDescription)
        }

        var result = convertToLocal(updated)
        result.markdownContent = character.markdownContent
        return result
    }

    /// Delete a character
    func deleteCharacter(_ character: Character) async throws {
        try await supabase.deleteCharacter(id: character.id)
    }

    // MARK: - Knowledge File Management

    /// Detect file type from filename
    private func detectFileType(from fileName: String) -> String {
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
    func createKnowledgeFile(for character: Character, fileName: String, content: String, fileType: String? = nil, sourceUrl: String? = nil, sourceTitle: String? = nil) async throws -> KnowledgeFile {
        let resolvedFileType = fileType ?? detectFileType(from: fileName)

        // Calculate word count
        let wordCount = content.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .count

        // Try to upload to storage
        var storagePath = "\(Self.storagePath)/\(character.id.uuidString)/\(fileName)"
        let userId = await supabase.currentUserId
        let storagePrefix = userId?.uuidString ?? Self.storagePath
        do {
            storagePath = try await supabase.uploadKnowledgeFile(
                userId: UUID(uuidString: storagePrefix) ?? UUID(),
                characterId: character.id,
                fileName: fileName,
                content: content
            )
        } catch {
            NSLog("[SupabaseCharacterRepository] Storage upload failed, storing content in DB: %@", error.localizedDescription)
        }

        // Check if file already exists for this character
        let existingFiles = try await supabase.fetchKnowledgeFiles(characterId: character.id)
        if let existingFile = existingFiles.first(where: { $0.fileName == fileName }) {
            // Update existing file
            let updated = try await supabase.updateKnowledgeFile(
                id: existingFile.id,
                updates: [
                    "storage_path": .string(storagePath),
                    "content": .string(content),
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

        // Create new database record (store content in DB as fallback)
        let insert = KnowledgeFileInsert(
            characterId: character.id,
            fileName: fileName,
            fileType: resolvedFileType,
            storagePath: storagePath,
            content: content,
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
        // Update content in database
        let wordCount = file.wordCount
        try await supabase.updateKnowledgeFile(
            id: file.id,
            updates: [
                "content": .string(file.content),
                "word_count": .integer(wordCount),
                "file_size_bytes": .integer(file.content.utf8.count)
            ]
        )

        // Also try to upload to storage
        let userId = await supabase.currentUserId
        let storagePrefix = userId?.uuidString ?? Self.storagePath
        do {
            _ = try await supabase.uploadKnowledgeFile(
                userId: UUID(uuidString: storagePrefix) ?? UUID(),
                characterId: character.id,
                fileName: file.fileName,
                content: file.content
            )
        } catch {
            NSLog("[SupabaseCharacterRepository] Storage upload failed: %@", error.localizedDescription)
        }
    }

    /// Delete a knowledge file
    func deleteKnowledgeFile(_ file: KnowledgeFile) async throws {
        // Try to delete from storage (may fail if path is DB-only)
        do {
            try await supabase.deleteStorageFile(bucket: "knowledge", path: file.path)
        } catch {
            NSLog("[SupabaseCharacterRepository] Storage delete failed (may be DB-only): %@", error.localizedDescription)
        }

        // Delete database record
        try await supabase.deleteKnowledgeFile(id: file.id)
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

// MARK: - Errors

enum SupabaseCharacterRepositoryError: LocalizedError {
    case characterNotFound(UUID)

    var errorDescription: String? {
        switch self {
        case .characterNotFound(let id):
            return "Character not found: \(id)"
        }
    }
}
