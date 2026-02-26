import Foundation

// MARK: - Genies Character Config (Top-Level)

/// Top-level config structure matching the Genies dev portal format
struct GeniesCharacterConfig: Codable {
    var llm: GeniesLLMConfig
    var characterConfig: GeniesCharacterFields

    private enum CodingKeys: String, CodingKey {
        case llm
        case characterConfig = "character_config"
    }

    /// Build a config from a Character with optional user overrides
    static func from(
        character: Character,
        overrides: GeniesConfigOverrides = GeniesConfigOverrides()
    ) -> GeniesCharacterConfig {
        let persona = character.markdownContent.trimmingCharacters(in: .whitespacesAndNewlines)

        return GeniesCharacterConfig(
            llm: GeniesLLMConfig(
                options: [GeniesLLMOption(id: "gpt-5", name: "gpt-5")],
                choose: overrides.llmModel ?? "gpt-5"
            ),
            characterConfig: GeniesCharacterFields(
                identity: GeniesBaseConfig(
                    title: "Identity",
                    valueType: "object",
                    value: "",
                    properties: GeniesIdentityProperties(
                        name: GeniesSimpleField(
                            title: "Name",
                            valueType: "string",
                            value: character.name
                        ),
                        age: GeniesSimpleField(
                            title: "Age",
                            valueType: "string",
                            value: overrides.age ?? ""
                        ),
                        persona: GeniesSimpleField(
                            title: "Persona",
                            valueType: "string",
                            value: persona
                        )
                    )
                ),
                description: GeniesBaseConfig(
                    title: "Description",
                    tips: "Brief description of the character",
                    valueType: "string",
                    value: overrides.description ?? ""
                ),
                dialogueStyle: GeniesBaseConfig(
                    title: "Dialogue Style",
                    valueType: "string",
                    value: overrides.dialogueStyle ?? ""
                ),
                behaviorControl: GeniesBaseConfig(
                    title: "Behavior Control",
                    valueType: "string",
                    value: overrides.behaviorControl ?? ""
                ),
                friends: GeniesBaseConfig(
                    title: "Friends",
                    valueType: "array",
                    value: "[]"
                ),
                hobbiesInterests: GeniesBaseConfig(
                    title: "Hobbies & Interests",
                    valueType: "array",
                    value: "[]"
                ),
                voiceId: GeniesBaseConfig(
                    title: "Voice ID",
                    valueType: "string",
                    value: ""
                ),
                useMemory: GeniesBaseConfig(
                    title: "Use Memory",
                    valueType: "string",
                    value: "false"
                ),
                useKnowledge: GeniesBaseConfig(
                    title: "Use Knowledge",
                    valueType: "string",
                    value: "false"
                ),
                moderation: GeniesBaseConfig(
                    title: "Moderation",
                    valueType: "string",
                    value: "relaxed"
                ),
                moderationPrompt: GeniesBaseConfig(
                    title: "Moderation Prompt",
                    valueType: "string",
                    value: ""
                ),
                greetingInstruction: GeniesBaseConfig(
                    title: "Greeting Instruction",
                    valueType: "string",
                    value: overrides.greetingInstruction ?? ""
                ),
                welcomeText: GeniesBaseConfig(
                    title: "Welcome Text",
                    valueType: "string",
                    value: overrides.welcomeText ?? ""
                ),
                chatPrompt: GeniesBaseConfig(
                    title: "Chat Prompt",
                    tips: "PromptLayer key for the system prompt template (derived from prompt type)",
                    valueType: "string",
                    value: overrides.chatPrompt ?? character.systemPromptType.chatPromptKey
                )
            )
        )
    }
}

// MARK: - LLM Config

struct GeniesLLMOption: Codable {
    let id: String
    let name: String
}

struct GeniesLLMConfig: Codable {
    var options: [GeniesLLMOption]
    var choose: String
}

// MARK: - Character Fields

struct GeniesCharacterFields: Codable {
    var identity: GeniesBaseConfig
    var description: GeniesBaseConfig
    var dialogueStyle: GeniesBaseConfig
    var behaviorControl: GeniesBaseConfig
    var friends: GeniesBaseConfig
    var hobbiesInterests: GeniesBaseConfig
    var voiceId: GeniesBaseConfig
    var useMemory: GeniesBaseConfig
    var useKnowledge: GeniesBaseConfig
    var moderation: GeniesBaseConfig
    var moderationPrompt: GeniesBaseConfig
    var greetingInstruction: GeniesBaseConfig
    var welcomeText: GeniesBaseConfig
    var chatPrompt: GeniesBaseConfig?

    private enum CodingKeys: String, CodingKey {
        case identity, description
        case dialogueStyle = "dialogue_style"
        case behaviorControl = "behavior_control"
        case friends
        case hobbiesInterests = "hobbies_interests"
        case voiceId = "voice_id"
        case useMemory = "use_memory"
        case useKnowledge = "use_knowledge"
        case moderation
        case moderationPrompt = "moderation_prompt"
        case greetingInstruction = "greeting_instruction"
        case welcomeText = "welcome_text"
        case chatPrompt = "chat_prompt"
    }
}

// MARK: - Identity Properties (uses simple value fields, not recursive)

struct GeniesIdentityProperties: Codable {
    var name: GeniesSimpleField
    var age: GeniesSimpleField
    var persona: GeniesSimpleField
}

struct GeniesSimpleField: Codable {
    var title: String
    var valueType: String
    var value: String

    private enum CodingKeys: String, CodingKey {
        case title
        case valueType = "value_type"
        case value
    }
}

// MARK: - Base Config

struct GeniesBaseConfig: Codable {
    var title: String
    var tips: String?
    var valueType: String
    var value: String
    var placeholder: String?
    var properties: GeniesIdentityProperties?

    private enum CodingKeys: String, CodingKey {
        case title, tips
        case valueType = "value_type"
        case value, placeholder, properties
    }
}

// MARK: - Config Overrides (for publish sheet)

struct GeniesConfigOverrides {
    var llmModel: String?
    var description: String?
    var age: String?
    var dialogueStyle: String?
    var behaviorControl: String?
    var greetingInstruction: String?
    var welcomeText: String?
    var chatPrompt: String?
}

// MARK: - API Response Types

struct GeniesConfigResponse: Codable {
    let configId: String
    let name: String
    let config: GeniesCharacterConfig?
    let orgId: String?
    let userId: String?
    let createdAt: String?
    let lastUpdatedAt: String?

    /// Convenience alias matching the field name used throughout the app
    var id: String { configId }

    private enum CodingKeys: String, CodingKey {
        case configId = "config_id"
        case name, config
        case orgId = "org_id"
        case userId = "user_id"
        case createdAt = "created_at"
        case lastUpdatedAt = "last_updated_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        configId = try container.decode(String.self, forKey: .configId)
        name = try container.decode(String.self, forKey: .name)
        // Gracefully handle config decode failures (API configs may have unexpected structures)
        config = try? container.decode(GeniesCharacterConfig.self, forKey: .config)
        orgId = try container.decodeIfPresent(String.self, forKey: .orgId)
        userId = try container.decodeIfPresent(String.self, forKey: .userId)
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
        lastUpdatedAt = try container.decodeIfPresent(String.self, forKey: .lastUpdatedAt)
    }

    init(configId: String, name: String, config: GeniesCharacterConfig?, orgId: String?, userId: String?, createdAt: String?, lastUpdatedAt: String?) {
        self.configId = configId
        self.name = name
        self.config = config
        self.orgId = orgId
        self.userId = userId
        self.createdAt = createdAt
        self.lastUpdatedAt = lastUpdatedAt
    }
}

struct GeniesConfigListResponse: Codable {
    let configs: [GeniesConfigResponse]
    let nextCursor: String?

    private enum CodingKeys: String, CodingKey {
        case configs
        case nextCursor = "next_cursor"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        nextCursor = try container.decodeIfPresent(String.self, forKey: .nextCursor)

        // Decode configs array, skipping any that fail to decode
        var configsContainer = try container.nestedUnkeyedContainer(forKey: .configs)
        var decoded: [GeniesConfigResponse] = []
        while !configsContainer.isAtEnd {
            if let config = try? configsContainer.decode(GeniesConfigResponse.self) {
                decoded.append(config)
            } else {
                // Skip the failed element by decoding as throwaway
                _ = try? configsContainer.decode(AnyCodable.self)
            }
        }
        configs = decoded
    }
}

/// Throwaway type for skipping undecodable JSON elements
private struct AnyCodable: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { return }
        if let _ = try? container.decode(Bool.self) { return }
        if let _ = try? container.decode(Int.self) { return }
        if let _ = try? container.decode(Double.self) { return }
        if let _ = try? container.decode(String.self) { return }
        if let _ = try? container.decode([AnyCodable].self) { return }
        if let _ = try? container.decode([String: AnyCodable].self) { return }
    }

    func encode(to encoder: Encoder) throws {}
}

struct GeniesChatMessage: Codable {
    let role: String
    let content: String
}

struct GeniesChatResponse: Codable {
    let sessionId: String
    let message: GeniesChatMessage

    private enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case message
    }
}

struct GeniesSessionInfo: Codable {
    let id: String
    let configId: String?
    let createdAt: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case configId = "config_id"
        case createdAt = "created_at"
    }
}

struct GeniesSessionListResponse: Codable {
    let data: [GeniesSessionInfo]
    let cursor: String?
}

struct GeniesChatHistoryMessage: Codable {
    let role: String
    let content: String
    let createdAt: String?

    private enum CodingKeys: String, CodingKey {
        case role, content
        case createdAt = "created_at"
    }
}

struct GeniesChatHistoryResponse: Codable {
    let data: [GeniesChatHistoryMessage]
    let cursor: String?
}
