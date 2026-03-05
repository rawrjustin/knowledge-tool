import Foundation

@Observable
@MainActor
final class PersonaTestViewModel {
    // Dependencies
    private let character: Character
    private let repository: CombinedCharacterRepository
    private let apiKeyManager: APIKeyManager

    // State
    var status: PersonaTestStatus = .idle
    var conversation: [ConversationTurn] = []
    var evaluation: PersonaTestEvaluation?
    var testGoal: String = ""
    var maxTurns: Int = 5

    // Publish state
    var isPublished: Bool = false
    var configId: String?

    // Internal
    private var sessionId: String = ""
    private var openAIService: OpenAIService?
    private var testTask: Task<Void, Never>?

    init(character: Character, repository: CombinedCharacterRepository, apiKeyManager: APIKeyManager) {
        self.character = character
        self.repository = repository
        self.apiKeyManager = apiKeyManager
    }

    // MARK: - Load Publish State

    func loadPublishState() async {
        let metadata = await repository.loadPublishMetadata(characterName: character.name)
        if let storedConfigId = metadata?.configId, !storedConfigId.isEmpty {
            configId = storedConfigId
            isPublished = true
        } else {
            configId = nil
            isPublished = false
        }
    }

    // MARK: - Run Test

    func runTest() {
        guard !testGoal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard isPublished, let configId = configId else { return }

        guard let apiKey = apiKeyManager.getAPIKey(for: .openAI) else {
            status = .error("OpenAI API key not configured. Add it in Settings.")
            return
        }

        // Reset state
        conversation = []
        evaluation = nil
        sessionId = ""
        openAIService = OpenAIService(apiKey: apiKey)

        testTask = Task {
            do {
                // Start a new session with the persona (get greeting)
                let greetingResponse = try await GeniesPersonaService.shared.sendMessage(
                    input: "",
                    sessionId: "",
                    configId: configId
                )
                sessionId = greetingResponse.sessionId

                // Run conversation turns
                for turn in 1...maxTurns {
                    if Task.isCancelled { return }

                    status = .running(turn: turn, maxTurns: maxTurns)

                    // Generate a user message using OpenAI
                    let userMessage = try await generateUserMessage(turn: turn)

                    if Task.isCancelled { return }

                    // Send to persona via Genies API
                    let response = try await GeniesPersonaService.shared.sendMessage(
                        input: userMessage,
                        sessionId: sessionId,
                        configId: configId
                    )

                    if !response.sessionId.isEmpty {
                        sessionId = response.sessionId
                    }

                    let conversationTurn = ConversationTurn(
                        turnNumber: turn,
                        userMessage: userMessage,
                        personaResponse: response.message.content
                    )
                    conversation.append(conversationTurn)
                }

                if Task.isCancelled { return }

                // Evaluate the conversation
                status = .evaluating
                let result = try await evaluateConversation()
                evaluation = result
                status = .complete

            } catch {
                if !Task.isCancelled {
                    status = .error(error.localizedDescription)
                }
            }
        }
    }

    // MARK: - Cancel

    func cancelTest() {
        testTask?.cancel()
        testTask = nil
        if conversation.isEmpty {
            status = .idle
        } else {
            status = .error("Test cancelled after \(conversation.count) turn(s).")
        }
    }

    // MARK: - Reset

    func resetTest() {
        testTask?.cancel()
        testTask = nil
        conversation = []
        evaluation = nil
        sessionId = ""
        status = .idle
    }

    // MARK: - Generate User Message

    private func generateUserMessage(turn: Int) async throws -> String {
        guard let openAIService = openAIService else {
            throw PersonaTestError.missingService
        }

        var conversationContext = ""
        for t in conversation {
            conversationContext += "User: \(t.userMessage)\nPersona: \(t.personaResponse)\n\n"
        }

        let systemPrompt = """
        You are simulating a realistic user who is testing an AI persona/character. \
        Your goal is to probe and evaluate the persona based on the following test goal:

        TEST GOAL: \(testGoal)

        This is turn \(turn) of \(maxTurns).

        CONVERSATION SO FAR:
        \(conversationContext.isEmpty ? "(This is the first message)" : conversationContext)

        INSTRUCTIONS:
        - Write a single, natural user message that a real person might send
        - Your message should probe the persona's ability to fulfill the test goal
        - Vary your approach: ask questions, share scenarios, challenge the persona, or seek advice
        - Early turns should establish context; later turns should dig deeper or test edge cases
        - Keep messages concise (1-3 sentences)
        - Do NOT include any meta-commentary or instructions — just the user message itself
        """

        let messages: [[String: String]] = [
            ["role": "system", "content": systemPrompt],
            ["role": "user", "content": "Generate the next user message."]
        ]

        return try await openAIService.chat(
            messages: messages,
            model: "gpt-4.1-mini",
            temperature: 0.8,
            timeoutInterval: 30
        )
    }

    // MARK: - Evaluate Conversation

    private func evaluateConversation() async throws -> PersonaTestEvaluation {
        guard let openAIService = openAIService else {
            throw PersonaTestError.missingService
        }

        var transcript = ""
        for turn in conversation {
            transcript += "Turn \(turn.turnNumber):\n"
            transcript += "User: \(turn.userMessage)\n"
            transcript += "Persona: \(turn.personaResponse)\n\n"
        }

        let systemPrompt = """
        You are an expert evaluator assessing an AI persona's performance in a test conversation.

        TEST GOAL: \(testGoal)
        CHARACTER NAME: \(character.name)

        FULL CONVERSATION TRANSCRIPT:
        \(transcript)

        Evaluate the persona's performance and respond with ONLY a JSON object (no markdown, no code fences) with these exact fields:
        {
            "overall_score": <1-10>,
            "goal_achievement": <1-10>,
            "character_consistency": <1-10>,
            "conversation_quality": <1-10>,
            "summary": "<2-3 sentence overall assessment>",
            "strengths": ["<strength 1>", "<strength 2>", ...],
            "weaknesses": ["<weakness 1>", "<weakness 2>", ...],
            "recommendations": ["<recommendation 1>", "<recommendation 2>", ...]
        }

        SCORING RUBRIC:
        - overall_score: Holistic rating of the persona's test performance
        - goal_achievement: How well did the persona fulfill the stated test goal?
        - character_consistency: Did the persona maintain a consistent character/personality throughout?
        - conversation_quality: Was the conversation natural, engaging, and contextually appropriate?

        Provide 2-4 items for strengths, weaknesses, and recommendations each.
        """

        let messages: [[String: String]] = [
            ["role": "system", "content": systemPrompt],
            ["role": "user", "content": "Evaluate the conversation and return the JSON."]
        ]

        let response = try await openAIService.chat(
            messages: messages,
            model: "gpt-4.1-mini",
            temperature: 0.3,
            timeoutInterval: 60
        )

        // Clean up response — remove markdown fences if present
        var cleanedResponse = response.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanedResponse.hasPrefix("```json") {
            cleanedResponse = String(cleanedResponse.dropFirst(7))
        } else if cleanedResponse.hasPrefix("```") {
            cleanedResponse = String(cleanedResponse.dropFirst(3))
        }
        if cleanedResponse.hasSuffix("```") {
            cleanedResponse = String(cleanedResponse.dropLast(3))
        }
        cleanedResponse = cleanedResponse.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = cleanedResponse.data(using: .utf8) else {
            throw PersonaTestError.evaluationParseFailed
        }

        return try JSONDecoder().decode(PersonaTestEvaluation.self, from: data)
    }
}

// MARK: - Errors

enum PersonaTestError: LocalizedError {
    case missingService
    case evaluationParseFailed

    var errorDescription: String? {
        switch self {
        case .missingService:
            return "OpenAI service not initialized"
        case .evaluationParseFailed:
            return "Failed to parse evaluation response"
        }
    }
}
