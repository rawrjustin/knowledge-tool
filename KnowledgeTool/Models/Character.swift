import Foundation

// MARK: - System Prompt Type
enum SystemPromptType: String, CaseIterable, Codable {
    case action = "ASP"
    case conversational = "CSP"
    case roleplay = "RSP"

    /// Short code used in UI where prompt families are shown as versions.
    /// Note: this reflects the bundled/default prompt version, not necessarily the active Supabase version.
    var shortDisplayName: String {
        switch self {
        case .action:
            return "ASP1"
        case .conversational:
            return "CSP1"
        case .roleplay:
            return "RSP2"
        }
    }

    var displayName: String {
        switch self {
        case .action:
            return "Action (ASP1)"
        case .conversational:
            return "Companion (CSP1)"
        case .roleplay:
            return "Roleplay (RSP2)"
        }
    }

    var description: String {
        switch self {
        case .action:
            return "High-energy, mission-driven, mid-scene action orientation"
        case .conversational:
            return "Companion friend mode: warm, witty, curiosity-driven conversation"
        case .roleplay:
            return "Interactive roleplay with co-creation tools (RSP2 fallback)"
        }
    }

    /// Types available for selection in UI
    static let availableTypes: [SystemPromptType] = [.conversational, .roleplay, .action]
}

// MARK: - Knowledge File
struct KnowledgeFile: Identifiable, Codable, Hashable {
    let id: UUID
    let fileName: String
    var content: String
    let path: String            // Path (e.g., "Personas/Jake Paul/Knowledge/interview.txt" or "Personas/.../Knowledge/sources/{uuid}/transcript.txt")
    var sha: String             // Content hash for change tracking
    let createdAt: Date
    var modifiedAt: Date

    // Source folder support - for new source-based organization
    var sourceId: UUID?         // UUID of the source folder (nil for root-level files)
    var sourceMetadata: SourceMetadata?  // Loaded metadata from source folder

    init(
        id: UUID = UUID(),
        fileName: String,
        content: String,
        path: String,
        sha: String = "",
        createdAt: Date = Date(),
        modifiedAt: Date = Date(),
        sourceId: UUID? = nil,
        sourceMetadata: SourceMetadata? = nil
    ) {
        self.id = id
        self.fileName = fileName
        self.content = content
        self.path = path
        self.sha = sha
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.sourceId = sourceId
        self.sourceMetadata = sourceMetadata
    }

    // Display name - prefers source metadata title if available
    var displayName: String {
        if let metadata = sourceMetadata {
            return metadata.resolvedDisplayName
        }
        return fileName
            .replacingOccurrences(of: "_summary.txt", with: "")
            .replacingOccurrences(of: "_", with: " ")
    }

    // Word count for summary display
    var wordCount: Int {
        content.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .count
    }

    // Check if this file is in a source folder
    var isInSourceFolder: Bool {
        sourceId != nil
    }

    // Hashable conformance - exclude sourceMetadata (complex type)
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(fileName)
        hasher.combine(path)
    }

    static func == (lhs: KnowledgeFile, rhs: KnowledgeFile) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Character
struct Character: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String                    // "Jake Paul"
    let directoryPath: String           // Logical path (e.g., "Personas/Jake Paul")
    let personaFileName: String         // "jakepaul.md" or "jakepaulv2.md"
    var markdownContent: String         // Full persona markdown
    var knowledgeFiles: [KnowledgeFile]
    var sha: String                     // Content hash for change tracking
    var systemPromptType: SystemPromptType
    var version: Int                    // 1 for base, 2+ for versions
    var versionName: String?            // Optional user-provided name (e.g., "justin", "new information")
    var createdAt: Date                 // When this version was created
    var lastModified: Date              // When this version was last modified
    var isLocalOnly: Bool               // Not yet in git repo
    var isGenerating: Bool               // In-memory placeholder while generating

    init(
        id: UUID = UUID(),
        name: String,
        directoryPath: String,
        personaFileName: String,
        markdownContent: String,
        knowledgeFiles: [KnowledgeFile] = [],
        sha: String = "",
        systemPromptType: SystemPromptType = .conversational,
        version: Int = 1,
        versionName: String? = nil,
        createdAt: Date = Date(),
        lastModified: Date = Date(),
        isLocalOnly: Bool = false,
        isGenerating: Bool = false
    ) {
        self.id = id
        self.name = name
        self.directoryPath = directoryPath
        self.personaFileName = personaFileName
        self.markdownContent = markdownContent
        self.knowledgeFiles = knowledgeFiles
        self.sha = sha
        self.systemPromptType = systemPromptType
        self.version = version
        self.versionName = versionName
        self.createdAt = createdAt
        self.lastModified = lastModified
        self.isLocalOnly = isLocalOnly
        self.isGenerating = isGenerating
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case id, name, directoryPath, personaFileName, markdownContent, knowledgeFiles
        case sha, systemPromptType, version, versionName, createdAt, lastModified, isLocalOnly, isGenerating
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        directoryPath = try container.decode(String.self, forKey: .directoryPath)
        personaFileName = try container.decode(String.self, forKey: .personaFileName)
        markdownContent = try container.decode(String.self, forKey: .markdownContent)
        knowledgeFiles = try container.decode([KnowledgeFile].self, forKey: .knowledgeFiles)
        sha = try container.decode(String.self, forKey: .sha)
        systemPromptType = try container.decode(SystemPromptType.self, forKey: .systemPromptType)
        version = try container.decode(Int.self, forKey: .version)
        versionName = try container.decodeIfPresent(String.self, forKey: .versionName)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        lastModified = try container.decode(Date.self, forKey: .lastModified)
        isLocalOnly = try container.decode(Bool.self, forKey: .isLocalOnly)
        isGenerating = try container.decodeIfPresent(Bool.self, forKey: .isGenerating) ?? false
    }

    // Full file path to persona markdown
    var personaFilePath: String {
        "\(directoryPath)/\(personaFileName)"
    }

    // Knowledge base directory path
    var knowledgeDirectoryPath: String {
        "\(directoryPath)/Knowledge"
    }

    // Check if character has knowledge base
    var hasKnowledgeBase: Bool {
        !knowledgeFiles.isEmpty
    }

    // Total knowledge word count
    var totalKnowledgeWords: Int {
        knowledgeFiles.reduce(0) { $0 + $1.wordCount }
    }

    // Extract character name from file name (e.g., "jakepaul" -> "Jake Paul")
    static func formatNameFromFileName(_ fileName: String) -> String {
        let nameWithoutExtension = fileName.replacingOccurrences(of: ".md", with: "")

        // Common patterns
        let specialCases: [String: String] = [
            "jakepaul": "Jake Paul",
            "shawnmendes": "Shawn Mendes",
            "kobebryant": "Kobe Bryant",
            "candaceparker": "Candace Parker",
            "jaredgoff": "Jared Goff",
            "laybankz": "Lay Bankz",
            "duchesscat": "Duchess",
            "woodypride": "Woody Pride",
            "crunchthompson": "Crunch Thompson",
            "marvwentworth": "Marv Wentworth",
            "siredric": "Sir Edric",
            "nagiinoue": "Nagi Inoue",
            "serenamoonflower": "Serena Moonflower",
            "luffy": "Monkey D. Luffy"
        ]

        if let formatted = specialCases[nameWithoutExtension.lowercased()] {
            return formatted
        }

        // Fallback: capitalize first letter
        return nameWithoutExtension.prefix(1).uppercased() + nameWithoutExtension.dropFirst()
    }

    // Parse persona sections from markdown
    func extractSection(_ sectionTitle: String) -> String? {
        let pattern = "##\\s*\(sectionTitle)[\\s\\S]*?(?=\\n##|\\z)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return nil
        }

        let nsString = markdownContent as NSString
        let matches = regex.matches(in: markdownContent, range: NSRange(location: 0, length: nsString.length))

        guard let match = matches.first else {
            return nil
        }

        return nsString.substring(with: match.range)
    }

    // Get a preview of the persona (first 500 characters)
    var preview: String {
        let preview = markdownContent.prefix(500)
        return String(preview) + (markdownContent.count > 500 ? "..." : "")
    }

    // Extract version number from filename (e.g., "jakepaulv2.md" -> 2, "jakepaul.md" -> 1)
    static func extractVersion(from fileName: String) -> Int {
        let nameWithoutExtension = fileName.replacingOccurrences(of: ".md", with: "")

        // Match pattern like "jakepaulv2" -> version 2
        let pattern = "v(\\d+)$"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return 1
        }

        let nsString = nameWithoutExtension as NSString
        let matches = regex.matches(in: nameWithoutExtension, range: NSRange(location: 0, length: nsString.length))

        guard let match = matches.first,
              match.numberOfRanges > 1 else {
            return 1 // No version suffix means v1
        }

        let versionRange = match.range(at: 1)
        let versionString = nsString.substring(with: versionRange)
        return Int(versionString) ?? 1
    }

    // Get base filename without version (e.g., "jakepaulv2.md" -> "jakepaul")
    static func extractBaseName(from fileName: String) -> String {
        let nameWithoutExtension = fileName.replacingOccurrences(of: ".md", with: "")

        // Remove version suffix if exists
        let pattern = "v\\d+$"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return nameWithoutExtension
        }

        return regex.stringByReplacingMatches(
            in: nameWithoutExtension,
            range: NSRange(nameWithoutExtension.startIndex..., in: nameWithoutExtension),
            withTemplate: ""
        )
    }

    // Version display string (e.g., "v2 (justin)" or just "v2")
    var versionDisplay: String {
        let base = "v\(version)"
        if let name = versionName, !name.isEmpty {
            return "\(base) (\(name))"
        }
        return base
    }
}

// MARK: - Character Creation Type
enum CharacterCreationType {
    case fromWikipedia(url: String)
    case original(name: String, description: String)
}

// MARK: - Git Status
struct GitStatus {
    let hasUncommittedChanges: Bool
    let modifiedFiles: [String]
    let branch: String
    let lastCommitMessage: String?
    let lastCommitDate: Date?
}
