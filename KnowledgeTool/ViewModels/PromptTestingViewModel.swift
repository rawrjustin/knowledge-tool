import Foundation

@MainActor
@Observable
final class PromptTestingViewModel {
    private(set) var currentTest: PromptTest
    private(set) var isExecuting = false
    private(set) var selectedVariantIndex: Int?

    private let openAIService: OpenAIService?
    private let diffHighlighter = DiffHighlighter()

    init(character: Character?, apiKeyManager: APIKeyManager) {
        self.currentTest = PromptTest.createNew(for: character)

        // Get OpenAI API key from manager
        if let apiKey = apiKeyManager.getAPIKey(for: .openAI) {
            self.openAIService = OpenAIService(apiKey: apiKey)
        } else {
            self.openAIService = nil
        }
    }

    // MARK: - Variant Management

    func updateVariantSystemPrompt(_ index: Int, systemPrompt: String) {
        guard index < currentTest.variants.count else { return }
        currentTest.variants[index].systemPrompt = systemPrompt
    }

    func updateVariantLabel(_ index: Int, label: String) {
        guard index < currentTest.variants.count else { return }
        currentTest.variants[index].label = label
    }

    // MARK: - Prompt Execution

    /// Send a message to all variants in parallel
    func sendMessage(_ userMessage: String) async {
        guard !userMessage.isEmpty else { return }

        isExecuting = true
        defer { isExecuting = false }

        // Add user message to all variants
        for index in currentTest.variants.indices {
            let message = ChatMessage(role: .user, content: userMessage)
            currentTest.variants[index].messages.append(message)
            currentTest.variants[index].isExecuting = true
            currentTest.variants[index].error = nil
        }

        // Execute all variants in parallel
        await withTaskGroup(of: (Int, Result<String, Error>).self) { group in
            for (index, variant) in currentTest.variants.enumerated() {
                group.addTask { [self] in
                    do {
                        let response = try await self.executeVariant(variant)
                        return (index, .success(response))
                    } catch {
                        return (index, .failure(error))
                    }
                }
            }

            // Collect results
            for await (index, result) in group {
                currentTest.variants[index].isExecuting = false

                switch result {
                case .success(let response):
                    let assistantMessage = ChatMessage(role: .assistant, content: response)
                    currentTest.variants[index].messages.append(assistantMessage)
                    currentTest.variants[index].error = nil

                case .failure(let error):
                    currentTest.variants[index].error = error.localizedDescription
                }
            }
        }

        currentTest.updatedAt = Date()
    }

    private func executeVariant(_ variant: ChatVariant) async throws -> String {
        guard let openAIService = openAIService else {
            throw PromptTestingError.noAPIKey
        }

        // Build conversation history with system prompt
        var messages: [[String: String]] = [
            ["role": "system", "content": variant.systemPrompt]
        ]

        // Add conversation history
        messages.append(contentsOf: variant.conversationHistory)

        // Call OpenAI API
        return try await openAIService.chat(messages: messages)
    }

    // MARK: - Diff Comparison

    /// Get diff comparison between a variant and the base variant (Variant A)
    func getDiff(forVariantIndex index: Int) async -> DiffResult? {
        guard index > 0 && index < currentTest.variants.count else { return nil }

        let baseVariant = currentTest.variants[0]
        let compareVariant = currentTest.variants[index]

        guard let baseResponse = baseVariant.latestAssistantMessage?.content,
              let compareResponse = compareVariant.latestAssistantMessage?.content else {
            return nil
        }

        return await diffHighlighter.compare(baseResponse, compareResponse)
    }

    /// Get similarity score between a variant and the base variant
    func getSimilarity(forVariantIndex index: Int) async -> Double? {
        guard index > 0 && index < currentTest.variants.count else { return nil }

        let baseVariant = currentTest.variants[0]
        let compareVariant = currentTest.variants[index]

        guard let baseResponse = baseVariant.latestAssistantMessage?.content,
              let compareResponse = compareVariant.latestAssistantMessage?.content else {
            return nil
        }

        return await diffHighlighter.similarity(baseResponse, compareResponse)
    }

    // MARK: - Test Management

    func resetTest(for character: Character?) {
        currentTest = PromptTest.createNew(for: character)
        selectedVariantIndex = nil
    }

    func clearVariantMessages(_ index: Int) {
        guard index < currentTest.variants.count else { return }
        currentTest.variants[index].messages.removeAll()
        currentTest.variants[index].error = nil
    }
}

// MARK: - Errors

enum PromptTestingError: LocalizedError {
    case noAPIKey

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "OpenAI API key not configured. Please add your API key in Settings."
        }
    }
}
