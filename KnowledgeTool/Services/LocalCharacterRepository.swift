import Foundation

/// Local file system-based character repository
/// Used for local-only characters and offline access
actor LocalCharacterRepository {
    private let baseURL: URL
    private static let characterMetadataFileName = "character.json"

    private struct CharacterMetadata: Codable {
        var systemPromptType: SystemPromptType
        var versionNames: [String: String]?  // "2" -> "justin", "3" -> "new information"
    }

    init(baseURL: URL) {
        self.baseURL = baseURL
    }

    // MARK: - Character Loading

    /// Load all characters from local Personas directory
    func loadAllCharacters() async throws -> [Character] {
        let personasURL = baseURL.appendingPathComponent("Personas")

        // Create the Personas directory if it doesn't exist
        if !FileManager.default.fileExists(atPath: personasURL.path) {
            try FileManager.default.createDirectory(at: personasURL, withIntermediateDirectories: true)
            NSLog("[LocalCharacterRepository] Created Personas directory at: %@", personasURL.path)
            return [] // No characters yet
        }

        let contents = try FileManager.default.contentsOfDirectory(
            at: personasURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        var characters: [Character] = []

        for directoryURL in contents {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                continue
            }

            if let character = try? await loadCharacter(from: directoryURL) {
                characters.append(character)
            }
        }

        return characters.sorted { $0.name < $1.name }
    }

    /// Load a specific character from a directory (loads latest version by default)
    private func loadCharacter(from directoryURL: URL) async throws -> Character {
        let characterName = directoryURL.lastPathComponent

        // Find all persona markdown files
        let files = try FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.creationDateKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )

        let personaFiles = files.filter { url in
            url.pathExtension == "md" && !url.lastPathComponent.hasPrefix(".")
        }

        guard !personaFiles.isEmpty else {
            throw LocalRepositoryError.personaFileNotFound(characterName)
        }

        // Find the latest version
        var latestFile = personaFiles[0]
        var latestVersion = Character.extractVersion(from: latestFile.lastPathComponent)

        for file in personaFiles {
            let version = Character.extractVersion(from: file.lastPathComponent)
            if version > latestVersion {
                latestVersion = version
                latestFile = file
            }
        }

        return try await loadCharacterVersion(from: directoryURL, file: latestFile)
    }

    /// Load all versions of a character
    func loadAllVersions(for characterName: String) async throws -> [Character] {
        let characterURL = baseURL.appendingPathComponent("Personas").appendingPathComponent(characterName)

        guard FileManager.default.fileExists(atPath: characterURL.path) else {
            throw LocalRepositoryError.directoryNotFound(characterURL.path)
        }

        let files = try FileManager.default.contentsOfDirectory(
            at: characterURL,
            includingPropertiesForKeys: [.creationDateKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )

        let personaFiles = files.filter { url in
            url.pathExtension == "md" && !url.lastPathComponent.hasPrefix(".")
        }

        var versions: [Character] = []
        for file in personaFiles {
            let character = try await loadCharacterVersion(from: characterURL, file: file)
            versions.append(character)
        }

        // Sort by version number
        return versions.sorted { $0.version < $1.version }
    }

    /// Load a specific version of a character
    private func loadCharacterVersion(from directoryURL: URL, file: URL) async throws -> Character {
        let characterName = directoryURL.lastPathComponent

        let markdownContent = try String(contentsOf: file, encoding: .utf8)

        // Get file dates
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        let createdAt = attributes[.creationDate] as? Date ?? Date()
        let lastModified = attributes[.modificationDate] as? Date ?? Date()

        // Extract version from filename
        let version = Character.extractVersion(from: file.lastPathComponent)

        // Load knowledge files
        let knowledgeFiles = try await loadKnowledgeFiles(from: directoryURL)

        // Get relative path from base
        let relativePath = directoryURL.path.replacingOccurrences(
            of: baseURL.path + "/",
            with: ""
        )

        let metadata = loadCharacterMetadata(from: directoryURL)
        let systemPromptType = metadata?.systemPromptType ?? .conversational
        let versionName = metadata?.versionNames?[String(version)]

        return Character(
            name: characterName,
            directoryPath: relativePath,
            personaFileName: file.lastPathComponent,
            markdownContent: markdownContent,
            knowledgeFiles: knowledgeFiles,
            sha: "",
            systemPromptType: systemPromptType,
            version: version,
            versionName: versionName,
            createdAt: createdAt,
            lastModified: lastModified,
            isLocalOnly: true
        )
    }

    /// Load knowledge files from character's Knowledge directory
    /// Supports both new source-based folders (Knowledge/sources/{uuid}/) and legacy flat files
    private func loadKnowledgeFiles(from characterURL: URL) async throws -> [KnowledgeFile] {
        let knowledgeURL = characterURL.appendingPathComponent("Knowledge")

        guard FileManager.default.fileExists(atPath: knowledgeURL.path) else {
            return []
        }

        var knowledgeFiles: [KnowledgeFile] = []

        // 1. Check for sources/ directory (new structure)
        let sourcesURL = knowledgeURL.appendingPathComponent("sources")
        if FileManager.default.fileExists(atPath: sourcesURL.path) {
            let sourceFiles = try await loadKnowledgeFromSourceFolders(from: sourcesURL)
            knowledgeFiles.append(contentsOf: sourceFiles)
        }

        // 2. Load root-level files (legacy + consolidated files like dialog_examples.jsonl)
        let rootFiles = try await loadRootLevelKnowledgeFiles(from: knowledgeURL)
        knowledgeFiles.append(contentsOf: rootFiles)

        return knowledgeFiles.sorted { $0.fileName < $1.fileName }
    }

    /// Load knowledge files from the new sources/ folder structure
    private func loadKnowledgeFromSourceFolders(from sourcesURL: URL) async throws -> [KnowledgeFile] {
        var knowledgeFiles: [KnowledgeFile] = []

        let contents = try FileManager.default.contentsOfDirectory(
            at: sourcesURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        for folderURL in contents {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: folderURL.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                continue
            }

            // Try to load metadata.json to get human-readable info
            let metadataURL = folderURL.appendingPathComponent("metadata.json")
            var sourceMetadata: SourceMetadata?

            if FileManager.default.fileExists(atPath: metadataURL.path) {
                let metadataData = try Data(contentsOf: metadataURL)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                sourceMetadata = try? decoder.decode(SourceMetadata.self, from: metadataData)
            }

            // Load files from this source folder
            let folderFiles = try FileManager.default.contentsOfDirectory(
                at: folderURL,
                includingPropertiesForKeys: [.creationDateKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )

            let supportedExtensions = ["txt", "jsonl", "json", "md"]
            let sourceId = folderURL.lastPathComponent // UUID string

            for fileURL in folderFiles where supportedExtensions.contains(fileURL.pathExtension) {
                // Skip metadata.json - it's not a knowledge file
                if fileURL.lastPathComponent == "metadata.json" {
                    continue
                }

                let content = try String(contentsOf: fileURL, encoding: .utf8)

                let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
                let createdAt = sourceMetadata?.processedAt ?? (attributes[.creationDate] as? Date ?? Date())
                let modifiedAt = attributes[.modificationDate] as? Date ?? Date()

                let relativePath = fileURL.path.replacingOccurrences(
                    of: baseURL.path + "/",
                    with: ""
                )

                // Use source title for display if available
                let displayFileName: String
                if let metadata = sourceMetadata {
                    let baseName = fileURL.deletingPathExtension().lastPathComponent
                    displayFileName = "\(metadata.resolvedDisplayName) - \(baseName).\(fileURL.pathExtension)"
                } else {
                    displayFileName = "\(sourceId)/\(fileURL.lastPathComponent)"
                }

                let knowledgeFile = KnowledgeFile(
                    fileName: displayFileName,
                    content: content,
                    path: relativePath,
                    sha: "",
                    createdAt: createdAt,
                    modifiedAt: modifiedAt,
                    sourceId: UUID(uuidString: sourceId),
                    sourceMetadata: sourceMetadata
                )

                knowledgeFiles.append(knowledgeFile)
            }
        }

        return knowledgeFiles
    }

    /// Load root-level knowledge files (legacy flat files and consolidated files)
    private func loadRootLevelKnowledgeFiles(from knowledgeURL: URL) async throws -> [KnowledgeFile] {
        var knowledgeFiles: [KnowledgeFile] = []

        let files = try FileManager.default.contentsOfDirectory(
            at: knowledgeURL,
            includingPropertiesForKeys: [.creationDateKey, .contentModificationDateKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        // Support both .txt and .jsonl knowledge files
        let supportedExtensions = ["txt", "jsonl", "json", "md"]

        for fileURL in files {
            // Skip directories (like sources/)
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDirectory),
               isDirectory.boolValue {
                continue
            }

            guard supportedExtensions.contains(fileURL.pathExtension) else {
                continue
            }

            let content = try String(contentsOf: fileURL, encoding: .utf8)

            let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            let createdAt = attributes[.creationDate] as? Date ?? Date()
            let modifiedAt = attributes[.modificationDate] as? Date ?? Date()

            let relativePath = fileURL.path.replacingOccurrences(
                of: baseURL.path + "/",
                with: ""
            )

            let knowledgeFile = KnowledgeFile(
                fileName: fileURL.lastPathComponent,
                content: content,
                path: relativePath,
                sha: "",
                createdAt: createdAt,
                modifiedAt: modifiedAt
            )

            knowledgeFiles.append(knowledgeFile)
        }

        return knowledgeFiles
    }

    // MARK: - Character Saving

    /// Save character as new version (creates v2, v3, etc.)
    func saveCharacterAsNewVersion(_ character: Character) async throws -> Character {
        let characterURL = baseURL.appendingPathComponent(character.directoryPath)

        // Ensure directory exists
        try FileManager.default.createDirectory(
            at: characterURL,
            withIntermediateDirectories: true
        )

        // Get all existing versions
        let files = try FileManager.default.contentsOfDirectory(
            at: characterURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        let personaFiles = files.filter { url in
            url.pathExtension == "md" && !url.lastPathComponent.hasPrefix(".")
        }

        // Find highest version number
        var highestVersion = 0
        for file in personaFiles {
            let version = Character.extractVersion(from: file.lastPathComponent)
            if version > highestVersion {
                highestVersion = version
            }
        }

        // Create new version number
        let newVersion = highestVersion + 1

        // Generate new filename
        let baseName = Character.extractBaseName(from: character.personaFileName)
        let newFileName = newVersion == 1 ? "\(baseName).md" : "\(baseName)v\(newVersion).md"

        let personaURL = characterURL.appendingPathComponent(newFileName)

        // Write markdown content
        try character.markdownContent.write(
            to: personaURL,
            atomically: true,
            encoding: .utf8
        )

        // Merge version name into existing metadata
        var existingMetadata = loadCharacterMetadata(from: characterURL)
        var versionNames = existingMetadata?.versionNames ?? [:]
        if let vName = character.versionName, !vName.isEmpty {
            versionNames[String(newVersion)] = vName
        }

        try saveCharacterMetadata(
            CharacterMetadata(systemPromptType: character.systemPromptType, versionNames: versionNames),
            to: characterURL
        )

        // Return updated character with new version info
        return Character(
            id: UUID(), // Generate new UUID for new version
            name: character.name,
            directoryPath: character.directoryPath,
            personaFileName: newFileName,
            markdownContent: character.markdownContent,
            knowledgeFiles: character.knowledgeFiles,
            sha: character.sha,
            systemPromptType: character.systemPromptType,
            version: newVersion,
            versionName: character.versionName,
            createdAt: Date(), // New version gets new creation date
            lastModified: Date(),
            isLocalOnly: true
        )
    }

    /// Save character to local file system (overwrites existing file)
    func saveCharacter(_ character: Character) async throws {
        let characterURL = baseURL.appendingPathComponent(character.directoryPath)
        let personaURL = characterURL.appendingPathComponent(character.personaFileName)

        // Ensure directory exists
        try FileManager.default.createDirectory(
            at: characterURL,
            withIntermediateDirectories: true
        )

        // Write markdown content
        try character.markdownContent.write(
            to: personaURL,
            atomically: true,
            encoding: .utf8
        )

        // Preserve existing version names when overwriting
        let existingMetadata = loadCharacterMetadata(from: characterURL)
        try saveCharacterMetadata(
            CharacterMetadata(systemPromptType: character.systemPromptType, versionNames: existingMetadata?.versionNames),
            to: characterURL
        )
    }

    /// Create a new character
    func createCharacter(
        name: String,
        markdownContent: String,
        systemPromptType: SystemPromptType = .conversational
    ) async throws -> Character {
        // Sanitize name for directory/file
        let sanitizedName = name.replacingOccurrences(of: " ", with: "")
            .lowercased()

        let directoryPath = "Personas/\(name)"
        let personaFileName = "\(sanitizedName).md"

        let character = Character(
            name: name,
            directoryPath: directoryPath,
            personaFileName: personaFileName,
            markdownContent: markdownContent,
            knowledgeFiles: [],
            sha: "",
            systemPromptType: systemPromptType,
            lastModified: Date(),
            isLocalOnly: true
        )

        try await saveCharacter(character)

        return character
    }

    /// Rename a character by moving its folder and renaming persona markdown files.
    /// This updates the "## Your Persona: ..." header in each persona file if present.
    func renameCharacter(_ character: Character, to newName: String) async throws -> Character {
        let trimmedNewName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedNewName.isEmpty else {
            throw LocalRepositoryError.invalidCharacterName("Name cannot be empty")
        }

        let oldCharacterURL = baseURL.appendingPathComponent(character.directoryPath)
        guard FileManager.default.fileExists(atPath: oldCharacterURL.path) else {
            throw LocalRepositoryError.directoryNotFound(oldCharacterURL.path)
        }

        let newDirectoryPath = "Personas/\(trimmedNewName)"
        let newCharacterURL = baseURL.appendingPathComponent(newDirectoryPath)
        if FileManager.default.fileExists(atPath: newCharacterURL.path) {
            throw LocalRepositoryError.destinationAlreadyExists(newCharacterURL.path)
        }

        // 1) Move the entire directory (includes Knowledge/ and metadata)
        try FileManager.default.moveItem(at: oldCharacterURL, to: newCharacterURL)

        // 2) Rename persona markdown files to match new sanitized base name
        let sanitizedBase = trimmedNewName
            .replacingOccurrences(of: " ", with: "")
            .lowercased()

        let files = try FileManager.default.contentsOfDirectory(
            at: newCharacterURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        let personaFiles = files.filter { url in
            url.pathExtension == "md" && !url.lastPathComponent.hasPrefix(".")
        }

        for fileURL in personaFiles {
            let version = Character.extractVersion(from: fileURL.lastPathComponent)
            let newFileName = version == 1 ? "\(sanitizedBase).md" : "\(sanitizedBase)v\(version).md"
            let newFileURL = newCharacterURL.appendingPathComponent(newFileName)

            // Update "## Your Persona:" header if present
            do {
                var content = try String(contentsOf: fileURL, encoding: .utf8)
                if content.range(of: #"(?m)^##\s*Your Persona:\s*.*$"#, options: .regularExpression) != nil {
                    content = content.replacingOccurrences(
                        of: #"(?m)^##\s*Your Persona:\s*.*$"#,
                        with: "## Your Persona: \(trimmedNewName)",
                        options: .regularExpression
                    )
                    try content.write(to: fileURL, atomically: true, encoding: .utf8)
                }
            } catch {
                // Non-fatal: still allow rename to proceed
                NSLog("[LocalCharacterRepository] Failed to update persona header for %@: %@", fileURL.lastPathComponent, error.localizedDescription)
            }

            // Rename file if needed
            if fileURL.lastPathComponent != newFileName {
                // Avoid collision if a file with the target name somehow exists
                if FileManager.default.fileExists(atPath: newFileURL.path) {
                    throw LocalRepositoryError.destinationAlreadyExists(newFileURL.path)
                }
                try FileManager.default.moveItem(at: fileURL, to: newFileURL)
            }
        }

        // 3) Reload and return latest version from the new directory
        return try await loadCharacter(from: newCharacterURL)
    }

    // MARK: - Character Deletion

    /// Delete a character by removing its entire directory
    func deleteCharacter(_ character: Character) async throws {
        let characterURL = baseURL.appendingPathComponent(character.directoryPath)

        guard FileManager.default.fileExists(atPath: characterURL.path) else {
            throw LocalRepositoryError.directoryNotFound(characterURL.path)
        }

        try FileManager.default.removeItem(at: characterURL)
        NSLog("[LocalCharacterRepository] Deleted character directory: %@", characterURL.path)
    }

    // MARK: - Metadata

    private func loadCharacterMetadata(from directoryURL: URL) -> CharacterMetadata? {
        let metadataURL = directoryURL.appendingPathComponent(Self.characterMetadataFileName)
        guard FileManager.default.fileExists(atPath: metadataURL.path) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: metadataURL)
            return try JSONDecoder().decode(CharacterMetadata.self, from: data)
        } catch {
            NSLog(
                "[LocalCharacterRepository] Failed to load character metadata at %@: %@",
                metadataURL.path,
                error.localizedDescription
            )
            return nil
        }
    }

    private func saveCharacterMetadata(_ metadata: CharacterMetadata, to directoryURL: URL) throws {
        let metadataURL = directoryURL.appendingPathComponent(Self.characterMetadataFileName)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(metadata)
        try data.write(to: metadataURL, options: [.atomic])
    }

    // MARK: - Knowledge File Management

    /// Save a knowledge file
    func saveKnowledgeFile(_ knowledgeFile: KnowledgeFile) async throws {
        let fileURL = baseURL.appendingPathComponent(knowledgeFile.path)

        // Ensure directory exists
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        try knowledgeFile.content.write(
            to: fileURL,
            atomically: true,
            encoding: .utf8
        )
    }

    /// Create a new knowledge file for a character
    func createKnowledgeFile(
        for character: Character,
        fileName: String,
        content: String
    ) async throws -> KnowledgeFile {
        let knowledgePath = "\(character.directoryPath)/Knowledge/\(fileName)"

        let knowledgeFile = KnowledgeFile(
            fileName: fileName,
            content: content,
            path: knowledgePath,
            sha: "",
            createdAt: Date(),
            modifiedAt: Date()
        )

        try await saveKnowledgeFile(knowledgeFile)

        return knowledgeFile
    }

    /// Delete a knowledge file
    func deleteKnowledgeFile(_ knowledgeFile: KnowledgeFile) async throws {
        let fileURL = baseURL.appendingPathComponent(knowledgeFile.path)
        try FileManager.default.removeItem(at: fileURL)
    }

    // MARK: - Source Folder Management

    /// Create a source folder for a new knowledge source
    /// Returns the URL of the created folder (Knowledge/sources/{uuid}/)
    func createSourceFolder(for character: Character, sourceId: UUID) async throws -> URL {
        let sourcesPath = "\(character.directoryPath)/Knowledge/sources"
        let sourcesURL = baseURL.appendingPathComponent(sourcesPath)

        // Ensure sources directory exists
        try FileManager.default.createDirectory(
            at: sourcesURL,
            withIntermediateDirectories: true
        )

        let folderURL = sourcesURL.appendingPathComponent(sourceId.uuidString)
        try FileManager.default.createDirectory(
            at: folderURL,
            withIntermediateDirectories: true
        )

        return folderURL
    }

    /// Save metadata.json to a source folder
    func saveSourceMetadata(_ metadata: SourceMetadata, to folderURL: URL) async throws {
        let metadataURL = folderURL.appendingPathComponent("metadata.json")

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let data = try encoder.encode(metadata)
        try data.write(to: metadataURL)
    }

    /// Save a file to a source folder
    func saveFileToSourceFolder(fileName: String, content: String, folderURL: URL) async throws {
        let fileURL = folderURL.appendingPathComponent(fileName)
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    /// Create a knowledge file in a source folder
    func createKnowledgeFileInSourceFolder(
        for character: Character,
        sourceId: UUID,
        fileName: String,
        content: String
    ) async throws -> KnowledgeFile {
        let folderURL = try await createSourceFolder(for: character, sourceId: sourceId)
        try await saveFileToSourceFolder(fileName: fileName, content: content, folderURL: folderURL)

        let relativePath = "\(character.directoryPath)/Knowledge/sources/\(sourceId.uuidString)/\(fileName)"

        return KnowledgeFile(
            fileName: fileName,
            content: content,
            path: relativePath,
            sha: "",
            createdAt: Date(),
            modifiedAt: Date(),
            sourceId: sourceId
        )
    }

    /// Delete an entire source folder
    func deleteSourceFolder(for character: Character, sourceId: UUID) async throws {
        let folderPath = "\(character.directoryPath)/Knowledge/sources/\(sourceId.uuidString)"
        let folderURL = baseURL.appendingPathComponent(folderPath)

        if FileManager.default.fileExists(atPath: folderURL.path) {
            try FileManager.default.removeItem(at: folderURL)
        }
    }
}

// MARK: - Errors

enum LocalRepositoryError: LocalizedError {
    case directoryNotFound(String)
    case personaFileNotFound(String)
    case invalidFileFormat(String)
    case destinationAlreadyExists(String)
    case invalidCharacterName(String)

    var errorDescription: String? {
        switch self {
        case .directoryNotFound(let path):
            return "Directory not found: \(path)"
        case .personaFileNotFound(let name):
            return "Persona file not found for: \(name)"
        case .invalidFileFormat(let message):
            return "Invalid file format: \(message)"
        case .destinationAlreadyExists(let path):
            return "A character already exists at: \(path)"
        case .invalidCharacterName(let message):
            return message
        }
    }
}
