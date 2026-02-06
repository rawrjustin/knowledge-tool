import Foundation

// MARK: - System Prompt Template

/// A system prompt template stored in Supabase
struct SystemPromptTemplate: Codable, Identifiable {
    let id: UUID
    let promptType: String       // 'ASP', 'CSP', 'RSP'
    let version: Int
    let templateContent: String
    let name: String
    let description: String?
    let isActive: Bool
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case promptType = "prompt_type"
        case version
        case templateContent = "template_content"
        case name
        case description
        case isActive = "is_active"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    /// Convert promptType string to SystemPromptType enum
    var systemPromptType: SystemPromptType? {
        SystemPromptType(rawValue: promptType)
    }
}

// MARK: - Cached System Prompt

/// Wrapper for cached system prompt with expiry tracking
struct CachedSystemPrompt: Codable {
    let template: SystemPromptTemplate
    let cachedAt: Date

    /// Cache expiry duration (24 hours)
    static let cacheExpiryInterval: TimeInterval = 24 * 60 * 60

    /// Check if the cache has expired
    var isStale: Bool {
        Date().timeIntervalSince(cachedAt) > Self.cacheExpiryInterval
    }

    init(template: SystemPromptTemplate) {
        self.template = template
        self.cachedAt = Date()
    }
}
