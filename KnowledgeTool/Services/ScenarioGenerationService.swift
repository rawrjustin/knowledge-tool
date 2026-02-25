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
        1. **Title** - A short, natural title (3-6 words) — think of how you'd describe this hangout to a friend
        2. **Current Situation** - Write a simple, natural moment where the character and user are hanging out. Think EVERYDAY life — grabbing food, chilling at home, walking somewhere, waiting for something, riding in a car, at a party, etc. The character's personality and vibe should come through in HOW they act in the moment, not through exotic or hyper-specific locations. Keep it grounded and easy to picture. The user should immediately think "oh yeah, I've been in a moment like this." Do NOT frame the situation as texting or messaging — write it as if they're together in person. No urgency, no time pressure, no deadlines.
        3. **Live Objective** - List 4-6 behavior objectives that describe how this character naturally keeps a conversation going. Focus on their personality and energy — how they joke, what they get excited about, how they react to things, what makes them light up. The objectives should feel natural and conversational, not like a performance or a script. Avoid overly elaborate or theatrical behaviors — think "how would this person actually talk to a close friend?"

        The Live Objective should also include 1-2 MECHANICS — small conversational habits or dynamics that feel natural to this character. These should come from the persona but be the kind of thing that would come up organically in any conversation — not forced or contrived.

        CRITICAL FRAMING:
        - The user is a FAN of this character. The scenario should feel warm and natural — like catching up with a friend, not like entering a themed experience.
        - Read the persona and let the character's personality flavor the conversation naturally. Their vibe, humor, interests, and way of talking should come through — but through natural behavior, not forced references.
        - PRIORITIZE RELATABILITY. The best scenarios are ones where the SITUATION is universal and easy to engage with (everyone has grabbed food with a friend, everyone has had a late-night conversation) but the CHARACTER makes it feel unique through their personality.
        - Don't try to make every scenario feel like a "special moment." Most good conversations happen during ordinary moments. Let some scenarios be mundane situations where the character's personality is what makes it interesting.
        - NO urgency or time pressure. No deadlines, no countdowns. Just two friends with time to talk.
        - Vary scenarios across different vibes — fun, chill, deep, playful, random — so it doesn't feel one-note.
        - Scenarios should be accessible to ANYONE. A user shouldn't need to know the character's lore to enjoy the conversation.

        Guidelines:
        - Use COMMON, relatable settings — restaurants, cars, couches, walks, parties, kitchens, etc. The character's personality makes it unique, not the location.
        - Each scenario should work as a standalone conversation starter
        - The situation and objective must complement each other
        - Don't overthink the settings. A couch is fine. A car ride is fine. What matters is the character's energy in that moment.
        - Do NOT describe the character as "texting you" or "messaging you." Write the situation as if the character and user are together in the moment.

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
                ["role": "system", "content": "You create natural, relatable conversation starters for AI characters. Your scenarios should feel like everyday moments between friends — simple situations where the character's personality makes it interesting. Prioritize accessibility and ease of engagement over uniqueness or creativity."],
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
            - Set a simple, everyday moment — two friends hanging out, nothing fancy
            - Use common relatable situations: grabbing food, chilling somewhere, walking, waiting, riding in a car, at someone's place, etc.
            - The situation should naturally invite conversation — give them something to react to or talk about
            - Keep it casual and easy to jump into — the user should feel like they already know this person
            - Avoid dramatic, high-stakes, or overly specific/niche framing — this is just friend mode
            - The character's personality comes through in how they ACT in the moment, not through exotic settings

            LIVE OBJECTIVE (write as deliberate behavioral instructions):
            - Write 4-6 directives that describe how this character naturally behaves as a friend — their humor, energy, and conversational style
            - Keep directives natural and grounded. Instead of theatrical behaviors, describe how they'd actually talk — their go-to jokes, what makes them laugh, how they show they care
            - Let the character's interests come up organically, not as forced references. A sports fan might casually bring up a game, not deliver a monologue about their team's history
            - Include how the character reads the room and adapts — but describe it naturally, not as a formula
            - The character should feel like a real person having a real conversation, not performing their persona
            - MECHANICS: Include 1-2 small conversational habits that feel natural — things that would come up in any hangout with this person, not elaborate interactive dynamics
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
