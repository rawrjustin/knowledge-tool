import Foundation

/// Service for generating roleplay scenarios for AI characters
actor ScenarioGenerationService {
    private let openAIApiKey: String
    private let model = "gpt-4o"

    init(openAIApiKey: String) {
        self.openAIApiKey = openAIApiKey
    }

    // MARK: - Generate Scenarios

    /// Generate multiple scenarios based on a theme
    func generateScenarios(
        characterId: UUID,
        characterName: String,
        personaContent: String,
        config: ScenarioGenerationConfig,
        onProgress: @escaping @Sendable (String) -> Void
    ) async throws -> [Scenario] {
        onProgress("Generating \(config.numberOfScenarios) scenarios for \(characterName)...")

        let stakesGuidance = config.includeDramaticStakes
            ? "Include dramatic stakes that raise the emotional intensity of each scenario."
            : "Keep scenarios grounded and realistic without overly dramatic stakes."

        let prompt = """
        Generate \(config.numberOfScenarios) unique roleplay scenarios for \(characterName).

        CHARACTER CONTEXT:
        \(String(personaContent.prefix(6000)))

        THEME: \(config.theme.isEmpty ? "General roleplay situations" : config.theme)
        \(stakesGuidance)

        Each scenario needs:
        1. **Title** - A short, evocative title (3-6 words)
        2. **Current Situation** - What's happening RIGHT NOW (1-2 paragraphs with sensory details, setting, and immediate context)
        3. **Live Objective** - What the character is actively trying to accomplish (1 paragraph, specific and achievable within the conversation)

        Guidelines:
        - Make situations feel immediate and present-tense
        - Include sensory details (sounds, sights, atmosphere)
        - Objectives should be concrete and actionable
        - Vary the scenarios to cover different aspects of the character
        - Each scenario should work as a standalone conversation starter

        Output as JSON:
        {
          "scenarios": [
            {
              "title": "Brief Title Here",
              "currentSituation": "Detailed current situation...",
              "liveObjective": "What the character wants to accomplish..."
            }
          ]
        }
        """

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(openAIApiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": "You are an expert at creating immersive roleplay scenarios that bring characters to life. Generate creative, engaging scenarios that feel immediate and grounded."],
                ["role": "user", "content": prompt]
            ],
            "max_tokens": 4000,
            "temperature": 0.85,
            "response_format": ["type": "json_object"]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        onProgress("Waiting for AI response...")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw ScenarioError.apiError("OpenAI error: \(errorBody)")
        }

        let chatResponse = try JSONDecoder().decode(OpenAIChatResponse.self, from: data)
        let jsonContent = chatResponse.choices.first?.message.content ?? "{}"

        onProgress("Parsing generated scenarios...")

        let scenarios = parseScenarios(
            jsonContent: jsonContent,
            characterId: characterId,
            theme: config.theme
        )

        if scenarios.isEmpty {
            throw ScenarioError.noScenariosGenerated
        }

        onProgress("Generated \(scenarios.count) scenarios")
        return scenarios
    }

    // MARK: - Regenerate Single Scenario

    /// Regenerate a single scenario with a new variation
    func regenerateScenario(
        scenario: Scenario,
        characterName: String,
        personaContent: String
    ) async throws -> Scenario {
        let prompt = """
        Generate a NEW roleplay scenario for \(characterName) with a similar theme but different content.

        CHARACTER CONTEXT:
        \(String(personaContent.prefix(4000)))

        THEME: \(scenario.theme.isEmpty ? "General roleplay" : scenario.theme)

        Previous scenario to avoid duplicating:
        - Title: \(scenario.title)
        - Situation: \(scenario.currentSituation.prefix(200))...

        Generate ONE new scenario that is different from the previous one but fits the same theme.

        Output as JSON:
        {
          "title": "Brief Title Here",
          "currentSituation": "Detailed current situation...",
          "liveObjective": "What the character wants to accomplish..."
        }
        """

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(openAIApiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "user", "content": prompt]
            ],
            "max_tokens": 1500,
            "temperature": 0.9,
            "response_format": ["type": "json_object"]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw ScenarioError.apiError("Failed to regenerate scenario")
        }

        let chatResponse = try JSONDecoder().decode(OpenAIChatResponse.self, from: data)
        let jsonContent = chatResponse.choices.first?.message.content ?? "{}"

        guard let jsonData = jsonContent.data(using: .utf8),
              let parsed = try? JSONDecoder().decode(SingleScenarioResponse.self, from: jsonData) else {
            throw ScenarioError.parseError("Failed to parse regenerated scenario")
        }

        return Scenario(
            characterId: scenario.characterId,
            theme: scenario.theme,
            title: parsed.title,
            currentSituation: parsed.currentSituation,
            liveObjective: parsed.liveObjective,
            source: .generated,
            isActive: false
        )
    }

    // MARK: - JSONL Conversion

    /// Convert scenarios to JSONL format for storage
    func scenariosToJSONL(_ scenarios: [Scenario]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = []
        encoder.dateEncodingStrategy = .iso8601

        return scenarios.compactMap { scenario -> String? in
            guard let data = try? encoder.encode(scenario),
                  let json = String(data: data, encoding: .utf8) else {
                return nil
            }
            return json
        }.joined(separator: "\n")
    }

    /// Parse JSONL content into scenarios
    func parseJSONL(_ content: String) -> [Scenario] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return content.components(separatedBy: .newlines).compactMap { line -> Scenario? in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty,
                  let data = trimmed.data(using: .utf8) else {
                return nil
            }
            return try? decoder.decode(Scenario.self, from: data)
        }
    }

    // MARK: - Private Helpers

    private func parseScenarios(jsonContent: String, characterId: UUID, theme: String) -> [Scenario] {
        // Clean markdown code blocks if present
        var cleaned = jsonContent
        if cleaned.hasPrefix("```") {
            let lines = cleaned.components(separatedBy: "\n")
            cleaned = lines.dropFirst().dropLast().joined(separator: "\n")
        }

        guard let data = cleaned.data(using: .utf8) else { return [] }

        // Try parsing as wrapper with scenarios array
        if let wrapper = try? JSONDecoder().decode(ScenariosWrapper.self, from: data) {
            return wrapper.scenarios.map { parsed in
                Scenario(
                    characterId: characterId,
                    theme: theme,
                    title: parsed.title,
                    currentSituation: parsed.currentSituation,
                    liveObjective: parsed.liveObjective,
                    source: .generated
                )
            }
        }

        // Try parsing as array directly
        if let array = try? JSONDecoder().decode([ParsedScenario].self, from: data) {
            return array.map { parsed in
                Scenario(
                    characterId: characterId,
                    theme: theme,
                    title: parsed.title,
                    currentSituation: parsed.currentSituation,
                    liveObjective: parsed.liveObjective,
                    source: .generated
                )
            }
        }

        return []
    }

    // MARK: - Response Models

    private struct OpenAIChatResponse: Codable {
        let choices: [Choice]
        struct Choice: Codable {
            let message: Message
        }
        struct Message: Codable {
            let content: String
        }
    }

    private struct ParsedScenario: Codable {
        let title: String
        let currentSituation: String
        let liveObjective: String
    }

    private struct ScenariosWrapper: Codable {
        let scenarios: [ParsedScenario]
    }

    private struct SingleScenarioResponse: Codable {
        let title: String
        let currentSituation: String
        let liveObjective: String
    }
}

// MARK: - Errors

enum ScenarioError: LocalizedError {
    case missingAPIKey
    case apiError(String)
    case parseError(String)
    case noScenariosGenerated

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "OpenAI API key not configured"
        case .apiError(let message):
            return message
        case .parseError(let message):
            return "Parse error: \(message)"
        case .noScenariosGenerated:
            return "No scenarios were generated"
        }
    }
}
