import Foundation
import SwiftUI

// MARK: - Character Chat ViewModel
@Observable
@MainActor
class CharacterChatViewModel {
    // Initial greeting prompt (invisible to user)
    private static let initialGreetingPrompt = "I just ran into you. Greet me in character and begin a conversation naturally, don't force a question if not required"

    // Character and configuration
    var character: Character
    var selectedPromptType: SystemPromptType
    private let apiKeyManager: APIKeyManager

    // Chat state
    var messages: [ChatMessage] = []  // Visible messages only
    private var conversationHistory: [ChatMessage] = []  // Full history including hidden messages
    var inputText: String = ""
    var isLoading: Bool = false
    var isLoadingSystemPrompt: Bool = false
    var error: String?
    private var hasStartedConversation: Bool = false

    // System prompt content
    var systemPromptContent: String = ""
    var systemPromptLoaded: Bool = false

    // OpenAI service (created lazily when needed)
    private var openAIService: OpenAIService?

    // GitHub API for fetching system prompts
    private var githubAPI: GitHubAPIService?

    init(character: Character, apiKeyManager: APIKeyManager) {
        self.character = character
        self.selectedPromptType = character.systemPromptType
        self.apiKeyManager = apiKeyManager

        // Create GitHub API service with the hardcoded PAT
        let authService = GitHubAuthService()
        self.githubAPI = GitHubAPIService(
            getToken: { authService.token },
            isReadOnly: { authService.isReadOnly }
        )
    }

    // MARK: - System Prompt Loading

    func loadSystemPrompt() async {
        guard let githubAPI = githubAPI else {
            error = "GitHub API not initialized"
            return
        }

        isLoadingSystemPrompt = true
        error = nil

        do {
            // Fetch the system prompt from GitHub
            let promptPath = "SystemPrompts/\(selectedPromptType.rawValue)/\(selectedPromptType.rawValue)1.md"
            let file = try await githubAPI.getFile(at: promptPath)

            // Decode the content from base64
            guard let content = file.decodedContent else {
                throw KnowledgeToolError.apiError("Could not decode system prompt content")
            }

            systemPromptContent = content
            systemPromptLoaded = true

            // Reset chat when switching prompts
            messages = []
            conversationHistory = []
            hasStartedConversation = false

        } catch {
            self.error = "Failed to load system prompt: \(error.localizedDescription)"
            systemPromptLoaded = false
        }

        isLoadingSystemPrompt = false

        // Automatically start conversation with greeting
        if systemPromptLoaded {
            await startConversation()
        }
    }

    // MARK: - Start Conversation with Greeting

    func startConversation() async {
        guard !hasStartedConversation else { return }
        guard systemPromptLoaded else { return }

        // Check for OpenAI API key
        guard let apiKey = apiKeyManager.getAPIKey(for: .openAI), !apiKey.isEmpty else {
            error = "OpenAI API key not configured. Please add it in Settings."
            return
        }

        hasStartedConversation = true
        isLoading = true
        error = nil

        do {
            // Create OpenAI service if needed
            if openAIService == nil {
                openAIService = OpenAIService(apiKey: apiKey)
            }

            // Add hidden user message to conversation history (not visible)
            let hiddenUserMessage = ChatMessage(role: .user, content: Self.initialGreetingPrompt)
            conversationHistory.append(hiddenUserMessage)

            // Build messages for OpenAI API
            var apiMessages: [[String: String]] = [
                ["role": "system", "content": buildFullSystemPrompt()]
            ]

            // Add the hidden greeting prompt
            apiMessages.append(["role": "user", "content": Self.initialGreetingPrompt])

            // Call OpenAI
            let response = try await openAIService!.chat(messages: apiMessages)

            // Add assistant response to both histories
            let assistantMessage = ChatMessage(role: .assistant, content: response)
            conversationHistory.append(assistantMessage)
            messages.append(assistantMessage)  // This one is visible

        } catch {
            self.error = "Failed to get greeting: \(error.localizedDescription)"
            hasStartedConversation = false  // Allow retry
        }

        isLoading = false
    }

    // MARK: - Build Full System Prompt

    private func buildFullSystemPrompt() -> String {
        var fullPrompt = ""

        // Add system prompt template
        if !systemPromptContent.isEmpty {
            fullPrompt += systemPromptContent
            fullPrompt += "\n\n"
        }

        // Add character persona
        fullPrompt += "# Your Persona\n\n"
        fullPrompt += character.markdownContent

        return fullPrompt
    }

    // MARK: - Send Message

    func sendMessage() async {
        let userMessage = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !userMessage.isEmpty else { return }

        // Check for OpenAI API key
        guard let apiKey = apiKeyManager.getAPIKey(for: .openAI), !apiKey.isEmpty else {
            error = "OpenAI API key not configured. Please add it in Settings."
            return
        }

        // Ensure system prompt is loaded and conversation started
        if !systemPromptLoaded {
            await loadSystemPrompt()
            if !systemPromptLoaded {
                return
            }
        }

        // Add user message to both histories
        let userChatMessage = ChatMessage(role: .user, content: userMessage)
        messages.append(userChatMessage)
        conversationHistory.append(userChatMessage)

        // Clear input
        inputText = ""

        // Set loading state
        isLoading = true
        error = nil

        do {
            // Create OpenAI service if needed
            if openAIService == nil {
                openAIService = OpenAIService(apiKey: apiKey)
            }

            // Build messages for OpenAI API
            var apiMessages: [[String: String]] = [
                ["role": "system", "content": buildFullSystemPrompt()]
            ]

            // Add full conversation history (includes hidden initial prompt)
            for message in conversationHistory {
                let role = message.role == .user ? "user" : "assistant"
                apiMessages.append(["role": role, "content": message.content])
            }

            // Call OpenAI
            let response = try await openAIService!.chat(messages: apiMessages)

            // Add assistant response to both histories
            let assistantMessage = ChatMessage(role: .assistant, content: response)
            messages.append(assistantMessage)
            conversationHistory.append(assistantMessage)

        } catch {
            self.error = "Failed to get response: \(error.localizedDescription)"
        }

        isLoading = false
    }

    // MARK: - Clear Chat

    func clearChat() {
        messages = []
        conversationHistory = []
        hasStartedConversation = false
        error = nil

        // Restart conversation with new greeting
        Task {
            await startConversation()
        }
    }

    // MARK: - Update Character

    func updateCharacter(_ newCharacter: Character) {
        if character.id != newCharacter.id || character.name != newCharacter.name {
            character = newCharacter
            selectedPromptType = newCharacter.systemPromptType
            messages = []
            conversationHistory = []
            hasStartedConversation = false
            systemPromptLoaded = false
            Task {
                await loadSystemPrompt()
            }
        }
    }
}
