import Foundation

actor CharacterRepository {
    private let githubAPI: GitHubAPIService

    init(githubAPI: GitHubAPIService) {
        self.githubAPI = githubAPI
    }

        // MARK: - Character Loading
    
        /// Load all characters from the CharacterPrompts repository
        func loadAllCharacters() async throws -> [Character] {
            // List all directories in Personas/
            let personaFiles = try await githubAPI.listContents(at: "Personas")
            NSLog("[KnowledgeTool] Found %d items in Personas directory", personaFiles.count)
    
            var characters: [Character] = []
    
            for file in personaFiles where file.type == "dir" {
                // Try to load character from this directory
                do {
                    let character = try await loadCharacter(name: file.name)
                    characters.append(character)
                } catch {
                    NSLog("[KnowledgeTool] Failed to load character '%@': %@", file.name, error.localizedDescription)
                }
            }
    
            // Sort by name
            return characters.sorted { $0.name < $1.name }
        }
    
        /// Load a specific character by name
        func loadCharacter(name: String) async throws -> Character {
            let characterPath = "Personas/\(name)"
    
            // List files in character directory
            let files = try await githubAPI.listContents(at: characterPath)
    
            // Find the persona markdown file
            // Priority:
            // 1. Exact match: {name}.md
            // 2. Any .md file that doesn't start with "."
            var personaFile: GitHubFile?
    
            // Try exact match first (case insensitive)
            personaFile = files.first(where: { file in
                file.type == "file" &&
                file.name.lowercased() == "\(name.lowercased()).md"
            })
    
            // Fallback to any markdown file
            if personaFile == nil {
                personaFile = files.first(where: { file in
                    file.type == "file" &&
                    file.name.hasSuffix(".md") &&
                    !file.name.hasPrefix(".")
                })
            }
    
            guard let targetFile = personaFile else {
                throw CharacterRepositoryError.personaFileNotFound(name)
            }
    
            // Fetch the persona file content
            let personaFileData = try await githubAPI.getFile(at: targetFile.path)
    
            guard let markdownContent = personaFileData.decodedContent else {
                throw CharacterRepositoryError.invalidFileFormat("Could not decode persona file")
            }
    
            // Parse last modified date from GitHub
            let lastModified = Date() // GitHub API doesn't provide file mod date directly, would need commit history
    
            // Load knowledge files if they exist
            let knowledgeFiles = try await loadKnowledgeFiles(for: name)
    
            // Create character
            let character = Character(
                name: name,
                directoryPath: characterPath,
                personaFileName: targetFile.name,
                markdownContent: markdownContent,
                knowledgeFiles: knowledgeFiles,
                sha: personaFileData.sha, // Store GitHub SHA for updates
                systemPromptType: .conversational,  // Default, can be changed
                lastModified: lastModified,
                isLocalOnly: false
            )
    
            return character
        }
    /// Load knowledge files from a character's Knowledge/ directory
    private func loadKnowledgeFiles(for characterName: String) async throws -> [KnowledgeFile] {
        let knowledgePath = "Personas/\(characterName)/Knowledge"

        // Check if Knowledge directory exists
        guard let files = try? await githubAPI.listContents(at: knowledgePath) else {
            return []
        }

        var knowledgeFiles: [KnowledgeFile] = []

        for file in files where file.type == "file" && file.name.hasSuffix(".txt") {
            // Fetch file content
            let fileData = try await githubAPI.getFile(at: file.path)

            guard let content = fileData.decodedContent else {
                continue
            }

            let knowledgeFile = KnowledgeFile(
                fileName: file.name,
                content: content,
                path: file.path,
                sha: fileData.sha,
                createdAt: Date(), // Would need commit history to get actual date
                modifiedAt: Date()
            )

            knowledgeFiles.append(knowledgeFile)
        }

        // Sort by filename for now (since we don't have creation dates without commit history)
        return knowledgeFiles.sorted { $0.fileName < $1.fileName }
    }

    // MARK: - Character Saving

    /// Save character markdown to GitHub
    func saveCharacter(_ character: Character) async throws {
        let path = "\(character.directoryPath)/\(character.personaFileName)"

        let commitMessage = "Update \(character.name) persona"

        _ = try await githubAPI.updateFile(
            at: path,
            content: character.markdownContent,
            message: commitMessage,
            sha: character.sha
        )
    }

    /// Create a new knowledge file for a character
    func createKnowledgeFile(
        for character: Character,
        content: String,
        fileName: String
    ) async throws -> KnowledgeFile {
        let path = "\(character.directoryPath)/Knowledge/\(fileName)"

        let commitMessage = "Add knowledge file: \(fileName) for \(character.name)"

        let result = try await githubAPI.updateFile(
            at: path,
            content: content,
            message: commitMessage,
            sha: nil // New file, no SHA
        )

        return KnowledgeFile(
            fileName: fileName,
            content: content,
            path: path,
            sha: result.sha,
            createdAt: Date(),
            modifiedAt: Date()
        )
    }

    /// Update an existing knowledge file
    func updateKnowledgeFile(_ knowledgeFile: KnowledgeFile) async throws {
        let commitMessage = "Update knowledge file: \(knowledgeFile.fileName)"

        _ = try await githubAPI.updateFile(
            at: knowledgeFile.path,
            content: knowledgeFile.content,
            message: commitMessage,
            sha: knowledgeFile.sha
        )
    }

    // MARK: - System Prompts

    /// Load a system prompt template
    func loadSystemPrompt(type: SystemPromptType, version: Int = 1) async throws -> String {
        let fileName = "\(type.rawValue)\(version).md"
        let path = "SystemPrompts/\(type.rawValue)/\(fileName)"

        let fileData = try await githubAPI.getFile(at: path)

        guard let content = fileData.decodedContent else {
            throw CharacterRepositoryError.invalidFileFormat("Could not decode system prompt file")
        }

        return content
    }

    /// List all available versions of a system prompt type
    func listSystemPromptVersions(type: SystemPromptType) async throws -> [Int] {
        let path = "SystemPrompts/\(type.rawValue)"

        guard let files = try? await githubAPI.listContents(at: path) else {
            return []
        }

        var versions: [Int] = []

        for file in files where file.type == "file" && file.name.hasSuffix(".md") {
            // Pattern: ASP1.md, ASP2.md, etc.
            let pattern = "\(type.rawValue)(\\d+)\\.md"
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: file.name, range: NSRange(file.name.startIndex..., in: file.name)),
               let versionRange = Range(match.range(at: 1), in: file.name) {
                let versionString = String(file.name[versionRange])
                if let version = Int(versionString) {
                    versions.append(version)
                }
            }
        }

        return versions.sorted()
    }

    // MARK: - Version History

    /// Get commit history for a character
    func getCharacterHistory(for character: Character, limit: Int = 10) async throws -> [GitHubCommit] {
        let path = "\(character.directoryPath)/\(character.personaFileName)"
        return try await githubAPI.getCommits(path: path, limit: limit)
    }

    /// Get commit history for a knowledge file
    func getKnowledgeFileHistory(for knowledgeFile: KnowledgeFile, limit: Int = 10) async throws -> [GitHubCommit] {
        return try await githubAPI.getCommits(path: knowledgeFile.path, limit: limit)
    }

    /// Compare two versions of a character
    func compareCharacterVersions(character: Character, baseSHA: String, headSHA: String) async throws -> GitHubComparison {
        return try await githubAPI.compareCommits(base: baseSHA, head: headSHA)
    }
}

// MARK: - Errors

enum CharacterRepositoryError: LocalizedError {
    case repositoryNotFound(String)
    case characterNotFound(String)
    case personaFileNotFound(String)
    case systemPromptNotFound(SystemPromptType, Int)
    case invalidFileFormat(String)

    var errorDescription: String? {
        switch self {
        case .repositoryNotFound(let path):
            return "CharacterPrompts repository not found at: \(path)"
        case .characterNotFound(let name):
            return "Character '\(name)' not found in repository"
        case .personaFileNotFound(let characterName):
            return "Persona file not found for character: \(characterName)"
        case .systemPromptNotFound(let type, let version):
            return "System prompt not found: \(type.rawValue)\(version).md"
        case .invalidFileFormat(let message):
            return "Invalid file format: \(message)"
        }
    }
}
