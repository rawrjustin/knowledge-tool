import Foundation

/// Local file system-based character repository
/// Used when GitHub is not available or for local-only characters
actor LocalCharacterRepository {
    private let baseURL: URL

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

        return Character(
            name: characterName,
            directoryPath: relativePath,
            personaFileName: file.lastPathComponent,
            markdownContent: markdownContent,
            knowledgeFiles: knowledgeFiles,
            sha: "",
            systemPromptType: .conversational,
            version: version,
            createdAt: createdAt,
            lastModified: lastModified,
            isLocalOnly: true
        )
    }

    /// Load knowledge files from character's Knowledge directory
    private func loadKnowledgeFiles(from characterURL: URL) async throws -> [KnowledgeFile] {
        let knowledgeURL = characterURL.appendingPathComponent("Knowledge")

        guard FileManager.default.fileExists(atPath: knowledgeURL.path) else {
            return []
        }

        let files = try FileManager.default.contentsOfDirectory(
            at: knowledgeURL,
            includingPropertiesForKeys: [.creationDateKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )

        var knowledgeFiles: [KnowledgeFile] = []

        // Support both .txt and .jsonl knowledge files
        let supportedExtensions = ["txt", "jsonl", "json", "md"]

        for fileURL in files where supportedExtensions.contains(fileURL.pathExtension) {
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

        return knowledgeFiles.sorted { $0.fileName < $1.fileName }
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
    }

    /// Create a new character
    func createCharacter(name: String, markdownContent: String) async throws -> Character {
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
            systemPromptType: .conversational,
            lastModified: Date(),
            isLocalOnly: true
        )

        try await saveCharacter(character)

        return character
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
}

// MARK: - Errors

enum LocalRepositoryError: LocalizedError {
    case directoryNotFound(String)
    case personaFileNotFound(String)
    case invalidFileFormat(String)

    var errorDescription: String? {
        switch self {
        case .directoryNotFound(let path):
            return "Directory not found: \(path)"
        case .personaFileNotFound(let name):
            return "Persona file not found for: \(name)"
        case .invalidFileFormat(let message):
            return "Invalid file format: \(message)"
        }
    }
}
