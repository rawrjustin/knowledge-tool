import Foundation

// MARK: - System Prompt Type
enum SystemPromptType: String, CaseIterable, Codable {
    case action = "ASP"
    case conversational = "CSP"
    case roleplay = "RSP"

    var displayName: String {
        switch self {
        case .action:
            return "Action System Prompt"
        case .conversational:
            return "Conversational System Prompt"
        case .roleplay:
            return "Roleplay System Prompt"
        }
    }

    var description: String {
        switch self {
        case .action:
            return "High-energy, mission-driven, mid-scene action orientation"
        case .conversational:
            return "Friendly, witty companion mode with dry humor"
        case .roleplay:
            return "Reserved for future roleplay scenarios"
        }
    }
}

// MARK: - Knowledge File
struct KnowledgeFile: Identifiable, Codable, Hashable {
    let id: UUID
    let fileName: String
    var content: String
    let path: String            // GitHub path (e.g., "Personas/Jake Paul/Knowledge/interview.txt")
    var sha: String             // GitHub SHA for updates
    let createdAt: Date
    var modifiedAt: Date

    init(id: UUID = UUID(), fileName: String, content: String, path: String, sha: String = "", createdAt: Date = Date(), modifiedAt: Date = Date()) {
        self.id = id
        self.fileName = fileName
        self.content = content
        self.path = path
        self.sha = sha
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }

    // Display name without extension and formatting
    var displayName: String {
        fileName
            .replacingOccurrences(of: "_summary.txt", with: "")
            .replacingOccurrences(of: "_", with: " ")
    }

    // Word count for summary display
    var wordCount: Int {
        content.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .count
    }
}

// MARK: - Character
struct Character: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String                    // "Jake Paul"
    let directoryPath: String           // GitHub path (e.g., "Personas/Jake Paul")
    let personaFileName: String         // "jakepaul.md" or "jakepaulv2.md"
    var markdownContent: String         // Full persona markdown
    var knowledgeFiles: [KnowledgeFile]
    var sha: String                     // GitHub SHA for updates
    var systemPromptType: SystemPromptType
    var version: Int                    // 1 for base, 2+ for versions
    var createdAt: Date                 // When this version was created
    var lastModified: Date              // When this version was last modified
    var isLocalOnly: Bool               // Not yet in git repo

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
        createdAt: Date = Date(),
        lastModified: Date = Date(),
        isLocalOnly: Bool = false
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
        self.createdAt = createdAt
        self.lastModified = lastModified
        self.isLocalOnly = isLocalOnly
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

    // Version display string
    var versionDisplay: String {
        version == 1 ? "v1" : "v\(version)"
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
