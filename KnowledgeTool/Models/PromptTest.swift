import Foundation

// MARK: - Chat Message

struct ChatMessage: Identifiable, Codable, Hashable {
    let id: UUID
    let role: MessageRole
    let content: String
    let timestamp: Date

    init(id: UUID = UUID(), role: MessageRole, content: String, timestamp: Date = Date()) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
    }

    enum MessageRole: String, Codable {
        case system
        case user
        case assistant
    }
}

// MARK: - Chat Variant

struct ChatVariant: Identifiable, Codable, Hashable {
    let id: UUID
    var label: String
    var systemPrompt: String
    var messages: [ChatMessage]
    var isExecuting: Bool
    var error: String?

    init(
        id: UUID = UUID(),
        label: String,
        systemPrompt: String,
        messages: [ChatMessage] = [],
        isExecuting: Bool = false,
        error: String? = nil
    ) {
        self.id = id
        self.label = label
        self.systemPrompt = systemPrompt
        self.messages = messages
        self.isExecuting = isExecuting
        self.error = error
    }

    var conversationHistory: [[String: String]] {
        messages.map { message in
            [
                "role": message.role.rawValue,
                "content": message.content
            ]
        }
    }

    var latestAssistantMessage: ChatMessage? {
        messages.last(where: { $0.role == .assistant })
    }
}

// MARK: - Prompt Test

struct PromptTest: Identifiable, Codable {
    let id: UUID
    var name: String
    var characterID: UUID?
    var variants: [ChatVariant]
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        characterID: UUID? = nil,
        variants: [ChatVariant] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.characterID = characterID
        self.variants = variants
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Maximum number of variants allowed
    static let maxVariants = 4

    /// Variant labels in order
    static let variantLabels = ["Variant A", "Variant B", "Variant C", "Variant D"]

    /// Create a new test with 1 variant (Variant A)
    static func createNew(for character: Character?) -> PromptTest {
        // Get base system prompt from character or use default
        let baseSystemPrompt = character?.markdownContent ?? "You are a helpful assistant."

        let variants = [
            ChatVariant(label: "Variant A", systemPrompt: baseSystemPrompt)
        ]

        return PromptTest(
            name: "New Prompt Test",
            characterID: character?.id,
            variants: variants
        )
    }

    /// Check if more variants can be added
    var canAddVariant: Bool {
        variants.count < Self.maxVariants
    }

    /// Get the next variant label
    var nextVariantLabel: String {
        Self.variantLabels[variants.count]
    }
}

// Note: DiffResult, DiffSegment, and DiffType are defined in Models.swift
