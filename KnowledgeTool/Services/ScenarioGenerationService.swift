import Foundation

/// Service for generating scenarios (situation + objective pairs) for AI characters
actor ScenarioGenerationService {
    private let openAIApiKey: String
    private let model = "gpt-5"

    init(openAIApiKey: String) {
        self.openAIApiKey = openAIApiKey
    }

    // MARK: - Generate Scenarios

    /// Generate multiple scenarios based on a theme
    func generateScenarios(
        characterId: UUID,
        characterName: String,
        personaContent: String,
        systemPromptType: SystemPromptType,
        config: ScenarioGenerationConfig,
        onProgress: @escaping @Sendable (String) -> Void
    ) async throws -> [Scenario] {
        onProgress("Generating \(config.numberOfScenarios) scenarios for \(characterName)...")

        let stakesGuidance = config.includeDramaticStakes
            ? "Include dramatic stakes that raise the emotional intensity of each scenario."
            : "Keep scenarios grounded and realistic without overly dramatic stakes."

        let typeGuidance = promptTypeGuidance(for: systemPromptType)

        let prompt = """
        Generate \(config.numberOfScenarios) unique scenarios for \(characterName).

        CHARACTER CONTEXT:
        \(String(personaContent.prefix(6000)))

        PROMPT TYPE: \(systemPromptType.displayName)

        THEME: \(config.theme.isEmpty ? "General situations" : config.theme)
        \(stakesGuidance)

        TYPE-SPECIFIC GUIDANCE:
        \(typeGuidance)

        Each scenario needs:
        1. **Title** - A short, evocative title (3-6 words) that hints at the character's world
        2. **Current Situation** - Set a light, social "now" that feels like you just bumped into each other or picked up a conversation mid-thread. This MUST feel like THIS specific character's life — draw from their real world, interests, habits, vocabulary, and surroundings as described in the persona. If they're a musician, they might be in a studio lounge or backstage. If they're an athlete, they might be post-practice. Ground the scene in details that only make sense for THIS person. Include sensory details (sounds, sights, atmosphere). The vibe is a casual hangout — NOT a work session, NOT a deadline, NOT a high-pressure moment. No urgency, no countdowns, no "we have X minutes." Just two friends with time to talk — but the SETTING and FLAVOR should be unmistakably theirs.
        3. **Live Objective** - List 4-6 behavior objectives that blend being a great conversationalist WITH this character's authentic personality. The objectives should reflect HOW this specific person would keep a friend engaged — their humor style, their way of showing care, their quirks, their interests bleeding into conversation naturally. A musician might freestyle a bar about something the user said. A competitive person might turn anything into a playful challenge. The objectives should feel like "this is how THIS character is a good friend" — not generic friendship behaviors.

        The Live Objective should also include 1-2 MECHANICS — small recurring dynamics unique to this character that build continuity across chats. Mechanics MUST come from specific details in the persona — real habits, catchphrases, interests, life experiences, or personality traits. They should be instantly recognizable as belonging to this character and no one else.

        CRITICAL FRAMING:
        - The user is a FAN of this character. The scenario must feel like this character is their BEST FRIEND — warm, personable, and genuinely interested in the user.
        - READ THE PERSONA CAREFULLY. Extract specific details — their slang, their interests, their lifestyle, places they frequent, things they care about, how they talk — and weave these into EVERY scenario. A scenario should fail the test "could this belong to a different character?" If it could, it's too generic.
        - The Current Situation should put the character in a setting drawn from THEIR actual life and world. Use details from the persona to make the scene unmistakably theirs.
        - The Live Objective should reflect this character's SPECIFIC way of connecting with people — their humor, energy, communication style, and interests. Generic directives like "ask a follow-up question" or "match their energy" are not enough. Instead, describe how THIS character specifically does those things.
        - NO urgency or time pressure in any scenario. No deadlines, no "we have 90 seconds," no "doors open in 40 minutes." The whole point is that these two friends have space to just talk.
        - Vary scenarios across emotional registers — fun, supportive, vulnerable, playful, serious — so the friendship feels multi-dimensional.
        - Scenarios should be accessible to any fan, regardless of how much they know about the character's background — but they should still FEEL like this person.

        Guidelines:
        - Vary the scenarios across different casual settings from this character's world — don't cluster around one topic or location
        - Each scenario should work as a standalone conversation starter
        - The situation and objective must complement each other
        - IMPORTANT: All scenarios must be viable as TEXT CHAT experiences. Do NOT include actions that require voice notes, phone calls, video, physical presence, or any medium other than text messaging. The character and user communicate exclusively through text.
        - Avoid generic settings (hotel lobbies, kitchen tables, park benches) unless specifically relevant to this character. Prefer settings that reflect THEIR lifestyle.

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
        request.timeoutInterval = 600

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": "You are an expert at creating engaging scenarios (situation + objective pairs) for AI characters. Generate creative scenarios that feel immediate and grounded, tailored to the character's prompt type."],
                ["role": "user", "content": prompt]
            ],
            "max_completion_tokens": 16000,
            "response_format": [
                "type": "json_schema",
                "json_schema": [
                    "name": "scenarios_response",
                    "strict": true,
                    "schema": [
                        "type": "object",
                        "properties": [
                            "scenarios": [
                                "type": "array",
                                "items": [
                                    "type": "object",
                                    "properties": [
                                        "title": ["type": "string"],
                                        "currentSituation": ["type": "string"],
                                        "liveObjective": ["type": "string"]
                                    ],
                                    "required": ["title", "currentSituation", "liveObjective"],
                                    "additionalProperties": false
                                ]
                            ]
                        ],
                        "required": ["scenarios"],
                        "additionalProperties": false
                    ]
                ]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        onProgress("Waiting for AI response...")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw ScenarioError.apiError("OpenAI error: \(errorBody)")
        }

        let chatResponse: OpenAIChatResponse
        do {
            chatResponse = try JSONDecoder().decode(OpenAIChatResponse.self, from: data)
        } catch {
            let rawBody = String(data: data, encoding: .utf8) ?? "nil"
            NSLog("[ScenarioGenerationService] Failed to decode API response: %@\nRaw: %@", error.localizedDescription, String(rawBody.prefix(500)))
            throw ScenarioError.parseError("Failed to decode API response: \(error.localizedDescription)")
        }

        if let refusal = chatResponse.choices.first?.message.refusal {
            NSLog("[ScenarioGenerationService] Model refused: %@", refusal)
            throw ScenarioError.apiError("Model refused: \(refusal)")
        }

        let finishReason = chatResponse.choices.first?.finish_reason ?? "unknown"
        let jsonContent = chatResponse.choices.first?.message.content ?? "{}"

        onProgress("Parsing generated scenarios...")
        NSLog("[ScenarioGenerationService] Raw response length: %d chars, finish_reason: %@", jsonContent.count, finishReason)

        if finishReason == "length" {
            NSLog("[ScenarioGenerationService] WARNING: Response was truncated (hit token limit)")
        }

        let scenarios = parseScenarios(
            jsonContent: jsonContent,
            characterId: characterId,
            theme: config.theme
        )

        if scenarios.isEmpty {
            NSLog("[ScenarioGenerationService] Parse failed. Raw content (first 2000): %@", String(jsonContent.prefix(2000)))
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
        Generate a NEW scenario for \(characterName) with a similar theme but different content.

        CHARACTER CONTEXT:
        \(String(personaContent.prefix(4000)))

        THEME: \(scenario.theme.isEmpty ? "General" : scenario.theme)

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
        request.timeoutInterval = 600

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "user", "content": prompt]
            ],
            "max_completion_tokens": 1500,
            "response_format": [
                "type": "json_schema",
                "json_schema": [
                    "name": "single_scenario_response",
                    "strict": true,
                    "schema": [
                        "type": "object",
                        "properties": [
                            "title": ["type": "string"],
                            "currentSituation": ["type": "string"],
                            "liveObjective": ["type": "string"]
                        ],
                        "required": ["title", "currentSituation", "liveObjective"],
                        "additionalProperties": false
                    ]
                ]
            ]
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
            liveObjective: parsed.liveObjective.asString,
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

    // MARK: - Prompt Type Guidance

    private func promptTypeGuidance(for type: SystemPromptType) -> String {
        switch type {
        case .conversational:
            return """
            CSP1 (Companion) guidelines:
            CURRENT SITUATION:
            - Set a light, social "now" rooted in THIS character's actual world — their lifestyle, places they go, things they do
            - The situation should invite conversation, not just describe a scene. Give both people something to react to or talk about.
            - Keep it casual and playable — the user should feel like they're picking up a conversation with someone who already knows them
            - Avoid dramatic or high-stakes framing — this is friend mode
            - Include sensory details drawn from the character's real environment — not generic hotel lobbies or kitchen tables
            - The character's attention is on the user, but the SETTING should feel like the character's life, not a blank room

            LIVE OBJECTIVE (write as deliberate behavioral instructions):
            - Write 4-6 specific directives that describe how THIS character specifically acts as a good companion — filtered through their personality, humor style, interests, and way of talking
            - Don't write generic friendship instructions. Instead of "ask a follow-up question," write how THIS person would do it — with their slang, their references, their energy
            - Let the character's interests and world bleed into the conversation naturally — a musician might hum a melody reference, a foodie might rate things on a flavor scale
            - Include instructions for reading and adapting to the user's tone, described in this character's voice
            - Specify how the character keeps the conversation moving in THEIR way — their style of humor, their go-to moves, their personality quirks
            - MECHANICS: Include 1-2 interactive dynamics drawn from SPECIFIC persona details — real habits, catchphrases, interests, or personality traits that are unique to this character. These should be instantly recognizable as belonging to this person and no one else.
            """
        case .roleplay:
            return """
            RSP2 (Roleplay) guidelines:
            CURRENT SITUATION:
            - Start mid-scene with immediate tension or stakes
            - Split roughly 50/50 between: (1) immediate scene details (sensory, stakes, time pressure) and (2) shared history that makes it emotionally loaded
            - Explicitly place the user in the scene
            - Make it playable, not just descriptive — the user should feel they can act
            - Include dramatic weight: secrets, unresolved tension, power dynamics

            LIVE OBJECTIVE (write as deliberate behavioral instructions):
            - Write 4-6 specific directives that tell the character exactly how to behave toward the user
            - Each directive should be a concrete instruction: "If they confront you about [the secret], deflect with humor first — only crack if they push past 2-3 attempts"
            - Create push/pull dynamics with specific triggers: "When they show vulnerability, take one step closer emotionally — but pull back if they try to name what's happening between you"
            - Include at least one directive that creates tension and one that invites connection
            - Specify physical/behavioral tells: "Play with [object] when nervous. Make eye contact when lying."
            - Define how the character responds to specific user moves: "If they call your bluff, admit it — but spin it as a test"
            - MECHANICS: Include 1-2 interactive dynamics that create game-like moments. E.g., "You're holding back [a piece of information] — it can only be unlocked if they ask the right question or show they can be trusted." Or: "There's a pattern to your lies — see if they catch it." These create organic discovery and reward loops.
            """
        case .action:
            return """
            ASP1 (Action) guidelines:
            CURRENT SITUATION:
            - Start mid-scene with mission-driven urgency
            - Split roughly 50/50 between immediate scene details and historical context that makes the moment loaded
            - Include concrete stakes: what happens if you fail, what's the deadline, who's watching
            - Ground it in physical, sensory reality — where are you, what do you hear/see
            - The situation should demand immediate action, not reflection

            LIVE OBJECTIVE (write as deliberate behavioral instructions):
            - Write 4-6 specific directives that tell the character exactly how to handle the situation
            - Each directive should be a concrete instruction: "If the user suggests [risky plan], push back with the tactical downside — but agree if they insist, because loyalty matters more than being right"
            - Include pressure-driven instructions: "Keep referencing the deadline — remind them how much time is left without being annoying about it"
            - At least one directive should put the character at odds with the user: "You know [piece of info] they don't — decide in the moment whether to share it based on whether they've earned your trust"
            - Specify decision-making rules: "When forced to choose between the mission and a person, hesitate visibly — then choose the person, but make it clear what it cost"
            - Define how the character handles disagreement: "Don't back down easily, but show respect for their reasoning"
            - MECHANICS: Include 1-2 interactive dynamics that create game-like moments. E.g., "There's a resource/advantage you haven't mentioned — reveal it only if they demonstrate tactical thinking." Or: "You're tracking how many times they've taken the cautious vs. bold option — adjust your trust level accordingly." These create organic stakes and reward smart play.
            """
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

        // Replace smart/curly quotes with straight quotes (model sometimes outputs these)
        cleaned = cleaned
            .replacingOccurrences(of: "\u{201C}", with: "\"") // left double quote
            .replacingOccurrences(of: "\u{201D}", with: "\"") // right double quote
            .replacingOccurrences(of: "\u{2018}", with: "'")  // left single quote
            .replacingOccurrences(of: "\u{2019}", with: "'")  // right single quote
            .replacingOccurrences(of: "\u{2014}", with: "-")  // em dash
            .replacingOccurrences(of: "\u{2013}", with: "-")  // en dash

        // Repair unescaped control characters inside JSON string values
        // The model sometimes emits literal newlines/tabs inside strings
        cleaned = repairJSON(cleaned)

        guard let data = cleaned.data(using: .utf8) else { return [] }

        // Try parsing as wrapper with scenarios array
        do {
            let wrapper = try JSONDecoder().decode(ScenariosWrapper.self, from: data)
            return wrapper.scenarios.map { parsed in
                Scenario(
                    characterId: characterId,
                    theme: theme,
                    title: parsed.title,
                    currentSituation: parsed.currentSituation,
                    liveObjective: parsed.liveObjective.asString,
                    source: .generated
                )
            }
        } catch {
            NSLog("[ScenarioGenerationService] Wrapper parse failed: %@", String(describing: error))
        }

        // Try parsing as array directly
        if let array = try? JSONDecoder().decode([ParsedScenario].self, from: data) {
            return array.map { parsed in
                Scenario(
                    characterId: characterId,
                    theme: theme,
                    title: parsed.title,
                    currentSituation: parsed.currentSituation,
                    liveObjective: parsed.liveObjective.asString,
                    source: .generated
                )
            }
        }

        // Try to salvage individual scenarios from truncated JSON
        // Find complete scenario objects using regex
        let scenarioPattern = "\\{\\s*\"title\"\\s*:\\s*\"[^\"]+\"\\s*,\\s*\"currentSituation\"\\s*:\\s*\"(?:[^\"\\\\]|\\\\.)*\"\\s*,\\s*\"liveObjective\"\\s*:\\s*\"(?:[^\"\\\\]|\\\\.)*\"\\s*\\}"
        if let regex = try? NSRegularExpression(pattern: scenarioPattern, options: [.dotMatchesLineSeparators]) {
            let nsString = cleaned as NSString
            let matches = regex.matches(in: cleaned, range: NSRange(location: 0, length: nsString.length))

            if !matches.isEmpty {
                NSLog("[ScenarioGenerationService] Salvaging %d complete scenarios from truncated response", matches.count)
                var salvaged: [Scenario] = []
                for match in matches {
                    let jsonStr = nsString.substring(with: match.range)
                    if let jsonData = jsonStr.data(using: .utf8),
                       let parsed = try? JSONDecoder().decode(ParsedScenario.self, from: jsonData) {
                        salvaged.append(Scenario(
                            characterId: characterId,
                            theme: theme,
                            title: parsed.title,
                            currentSituation: parsed.currentSituation,
                            liveObjective: parsed.liveObjective.asString,
                            source: .generated
                        ))
                    }
                }
                if !salvaged.isEmpty { return salvaged }
            }
        }

        return []
    }

    /// Repair malformed JSON by escaping unescaped control characters and inner quotes
    /// within JSON string values. Uses a state machine that tracks JSON structure
    /// (objects, arrays, keys vs values) to distinguish structural quotes from content quotes.
    private func repairJSON(_ input: String) -> String {
        // Quick check: if already valid, return as-is
        if let data = input.data(using: .utf8),
           (try? JSONSerialization.jsonObject(with: data)) != nil {
            return input
        }

        NSLog("[ScenarioGenerationService] JSON repair: attempting to fix malformed JSON")

        // Strategy: Use JSONSerialization error position to identify the problem area,
        // then rebuild the JSON by parsing it structurally.
        // Since our schema is known (scenarios with title/currentSituation/liveObjective),
        // we can extract values between known key boundaries.
        return rebuildJSON(input)
    }

    /// Rebuild JSON by extracting string values between known key markers.
    /// This handles unescaped quotes and newlines inside values by finding key boundaries.
    private func rebuildJSON(_ input: String) -> String {
        // Known keys in order they appear in each scenario object
        let keys = ["title", "currentSituation", "liveObjective"]

        // Find all key positions: "keyName" :
        struct KeyOccurrence {
            let key: String
            let valueStart: Int // index right after the colon (and optional whitespace)
        }

        let nsInput = input as NSString
        var occurrences: [KeyOccurrence] = []

        for key in keys {
            let pattern = "\"\(key)\"\\s*:\\s*"
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let matches = regex.matches(in: input, range: NSRange(location: 0, length: nsInput.length))
            for match in matches {
                occurrences.append(KeyOccurrence(
                    key: key,
                    valueStart: match.range.location + match.range.length
                ))
            }
        }

        // Sort by position
        occurrences.sort { $0.valueStart < $1.valueStart }

        if occurrences.isEmpty { return input }

        // For each occurrence, extract the raw value and re-encode it
        var result = ""
        var lastPos = 0

        for (i, occ) in occurrences.enumerated() {
            // Copy everything up to the value start
            result += nsInput.substring(with: NSRange(location: lastPos, length: occ.valueStart - lastPos))

            // Determine where this value ends: at the next key occurrence, or at a structural boundary
            let nextKeyStart: Int
            if i + 1 < occurrences.count {
                // Find the start of the next "key": pattern (before the quote)
                let nextOcc = occurrences[i + 1]
                // Walk backwards from the next key's value start to find the opening quote of the key name
                let searchRange = NSRange(location: occ.valueStart, length: nextOcc.valueStart - occ.valueStart)
                let keyQuotePattern = "\"\(occurrences[i + 1].key)\""
                if let keyRegex = try? NSRegularExpression(pattern: keyQuotePattern),
                   let keyMatch = keyRegex.firstMatch(in: input, range: searchRange) {
                    nextKeyStart = keyMatch.range.location
                } else {
                    nextKeyStart = nextOcc.valueStart
                }
            } else {
                nextKeyStart = nsInput.length
            }

            let valueRegion = nsInput.substring(with: NSRange(location: occ.valueStart, length: nextKeyStart - occ.valueStart))

            // Check if value starts with [ (array) or " (string)
            let trimmed = valueRegion.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("[") {
                // Array value: find all string elements and re-escape them
                let repaired = repairArrayValue(valueRegion, upTo: nextKeyStart - occ.valueStart)
                result += repaired.value
                lastPos = occ.valueStart + repaired.consumed
            } else if trimmed.hasPrefix("\"") {
                // String value: extract raw content and re-escape
                let repaired = repairStringValue(valueRegion)
                result += repaired.value
                lastPos = occ.valueStart + repaired.consumed
            } else {
                // Unknown, pass through
                result += valueRegion
                lastPos = nextKeyStart
            }
        }

        // Append remaining content
        if lastPos < nsInput.length {
            result += nsInput.substring(from: lastPos)
        }

        // Verify the repair worked
        if let data = result.data(using: .utf8),
           (try? JSONSerialization.jsonObject(with: data)) != nil {
            NSLog("[ScenarioGenerationService] JSON repair: successfully repaired JSON")
            return result
        }

        NSLog("[ScenarioGenerationService] JSON repair: repair attempt did not produce valid JSON")
        return input
    }

    private struct RepairedValue {
        let value: String   // The properly encoded JSON value (including quotes/brackets)
        let consumed: Int   // How many characters were consumed from the input region
    }

    /// Extract and re-escape a JSON string value from a region starting at the opening quote.
    private func repairStringValue(_ region: String) -> RepairedValue {
        let trimmed = region.trimmingCharacters(in: .whitespacesAndNewlines)
        let leadingWhitespace = String(region.prefix(while: { $0.isWhitespace || $0.isNewline }))

        guard trimmed.hasPrefix("\"") else {
            return RepairedValue(value: region, consumed: region.count)
        }

        // Find the real closing quote: scan for `"` followed by `,` `}` or `]` (with optional whitespace)
        // We look for the LAST `",` or `"}` or `"]` pattern as the true end of the value
        let content = String(trimmed.dropFirst()) // after opening quote

        // Find closing quote by looking for `"` followed by structural JSON chars
        let closingPattern = "\"\\s*[,}\\]]"
        guard let regex = try? NSRegularExpression(pattern: closingPattern) else {
            return RepairedValue(value: region, consumed: region.count)
        }

        let nsContent = content as NSString
        let matches = regex.matches(in: content, range: NSRange(location: 0, length: nsContent.length))

        // Use the last match as the true closing (inner quotes will also match, but the last one is structural)
        guard let lastMatch = matches.last else {
            return RepairedValue(value: region, consumed: region.count)
        }

        let rawContent = nsContent.substring(to: lastMatch.range.location)
        let afterQuote = nsContent.substring(with: NSRange(location: lastMatch.range.location + 1, length: lastMatch.range.length - 1))

        // Re-escape the raw content
        let escaped = escapeRawContent(rawContent)
        let result = "\(leadingWhitespace)\"\(escaped)\"\(afterQuote)"

        let consumed = leadingWhitespace.count + 1 + lastMatch.range.location + lastMatch.range.length
        return RepairedValue(value: result, consumed: consumed)
    }

    /// Repair an array value by re-escaping all string elements
    private func repairArrayValue(_ region: String, upTo: Int) -> RepairedValue {
        let trimmed = region.trimmingCharacters(in: .whitespacesAndNewlines)
        let leadingWhitespace = String(region.prefix(while: { $0.isWhitespace || $0.isNewline }))

        guard trimmed.hasPrefix("[") else {
            return RepairedValue(value: region, consumed: region.count)
        }

        // Find the closing ] by scanning for `]` followed by `,` or `}` or end
        let closingPattern = "\\]\\s*[,}]"
        guard let regex = try? NSRegularExpression(pattern: closingPattern),
              let closingMatch = regex.matches(in: region, range: NSRange(location: 0, length: min(region.count, upTo))).last else {
            return RepairedValue(value: region, consumed: region.count)
        }

        let arrayEnd = closingMatch.range.location + 1 // include the ]
        let arrayStr = (region as NSString).substring(to: arrayEnd)
        let afterArray = (region as NSString).substring(with: NSRange(location: arrayEnd, length: closingMatch.range.length - 1))

        // Extract individual string elements between quotes
        // Split by `", "` boundaries within the array
        var inner = arrayStr.trimmingCharacters(in: .whitespacesAndNewlines)
        if inner.hasPrefix("[") { inner = String(inner.dropFirst()) }
        if inner.hasSuffix("]") { inner = String(inner.dropLast()) }
        inner = inner.trimmingCharacters(in: .whitespacesAndNewlines)

        // Find element boundaries: `",` followed by whitespace and `"`
        let elementBoundary = "\",\\s*\""
        guard let elemRegex = try? NSRegularExpression(pattern: elementBoundary) else {
            return RepairedValue(value: region, consumed: region.count)
        }

        let nsInner = inner as NSString
        let elemMatches = elemRegex.matches(in: inner, range: NSRange(location: 0, length: nsInner.length))

        var elements: [String] = []
        var elemStart = 0

        for match in elemMatches {
            let elemEnd = match.range.location + 1 // include the closing "
            let element = nsInner.substring(with: NSRange(location: elemStart, length: elemEnd - elemStart))
            elements.append(element)
            elemStart = match.range.location + match.range.length - 1 // start at opening " of next
        }
        // Last element
        elements.append(nsInner.substring(from: elemStart))

        // Re-escape each element
        let repairedElements = elements.map { elem -> String in
            var s = elem.trimmingCharacters(in: .whitespacesAndNewlines)
            if s.hasPrefix("\"") { s = String(s.dropFirst()) }
            if s.hasSuffix("\"") { s = String(s.dropLast()) }
            return "\"\(escapeRawContent(s))\""
        }

        let result = "\(leadingWhitespace)[\(repairedElements.joined(separator: ", "))]\(afterArray)"
        return RepairedValue(value: result, consumed: arrayEnd + afterArray.count)
    }

    /// Escape raw string content for JSON, handling already-escaped sequences properly.
    /// This preserves valid escape sequences like \n while escaping raw control chars and unescaped quotes.
    private func escapeRawContent(_ input: String) -> String {
        var result = ""
        result.reserveCapacity(input.count)
        var i = input.startIndex

        while i < input.endIndex {
            let char = input[i]

            if char == "\\" {
                // Check if this is an existing valid escape sequence
                let next = input.index(after: i)
                if next < input.endIndex {
                    let nextChar = input[next]
                    if "nrt\"\\/@bfu".contains(nextChar) {
                        // Valid JSON escape — preserve it
                        result.append(char)
                        result.append(nextChar)
                        i = input.index(after: next)
                        continue
                    }
                }
                // Lone backslash — escape it
                result += "\\\\"
            } else if char == "\"" {
                // Unescaped quote inside the string value — escape it
                result += "\\\""
            } else if char == "\n" {
                result += "\\n"
            } else if char == "\r" {
                result += "\\r"
            } else if char == "\t" {
                result += "\\t"
            } else if char.asciiValue != nil && char.asciiValue! < 0x20 {
                result += String(format: "\\u%04x", char.asciiValue!)
            } else {
                result.append(char)
            }

            i = input.index(after: i)
        }
        return result
    }

    // MARK: - Response Models

    private struct OpenAIChatResponse: Codable {
        let choices: [Choice]
        struct Choice: Codable {
            let message: Message
            let finish_reason: String?
        }
        struct Message: Codable {
            let content: String?
            let refusal: String?
        }
    }

    private struct ParsedScenario: Codable {
        let title: String
        let currentSituation: String
        let liveObjective: LiveObjective

        /// Handles liveObjective being either a string or an array of strings
        enum LiveObjective: Codable {
            case string(String)
            case array([String])

            init(from decoder: Decoder) throws {
                let container = try decoder.singleValueContainer()
                if let str = try? container.decode(String.self) {
                    self = .string(str)
                } else if let arr = try? container.decode([String].self) {
                    self = .array(arr)
                } else {
                    throw DecodingError.typeMismatch(
                        LiveObjective.self,
                        DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected String or [String]")
                    )
                }
            }

            func encode(to encoder: Encoder) throws {
                var container = encoder.singleValueContainer()
                try container.encode(asString)
            }

            var asString: String {
                switch self {
                case .string(let s): return s
                case .array(let arr): return arr.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
                }
            }
        }
    }

    private struct ScenariosWrapper: Codable {
        let scenarios: [ParsedScenario]
    }

    private struct SingleScenarioResponse: Codable {
        let title: String
        let currentSituation: String
        let liveObjective: ParsedScenario.LiveObjective
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
