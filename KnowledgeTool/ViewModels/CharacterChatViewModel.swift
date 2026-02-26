import Foundation
import SwiftUI

// MARK: - Character Chat ViewModel
@Observable
@MainActor
class CharacterChatViewModel {
    // Character and configuration
    var character: Character

    // Chat state
    var messages: [ChatMessage] = []
    var inputText: String = ""
    var isLoading: Bool = false
    var isLoadingChat: Bool = false
    var error: String?
    private var hasStartedConversation: Bool = false

    // Genies publish state
    var isPublished: Bool = false
    var configId: String?
    private var sessionId: String = ""

    // Genies service
    private let geniesService = GeniesPersonaService.shared

    init(character: Character, repository: CombinedCharacterRepository) {
        self.character = character
        self._repository = repository
    }

    private let _repository: CombinedCharacterRepository

    // MARK: - Load Chat (replaces loadSystemPrompt)

    func loadChat() async {
        isLoadingChat = true
        error = nil

        // Reset chat state
        messages = []
        hasStartedConversation = false
        sessionId = ""

        // Read publish metadata from character.json
        let metadata = await _repository.loadPublishMetadata(characterName: character.name)

        if let storedConfigId = metadata?.configId, !storedConfigId.isEmpty {
            configId = storedConfigId
            isPublished = true
            isLoadingChat = false

            // Auto-start conversation with greeting
            await startConversation()
        } else {
            configId = nil
            isPublished = false
            isLoadingChat = false
            NSLog("[CharacterChatViewModel] Character '%@' not published — chat blocked", character.name)
        }
    }

    // MARK: - Start Conversation (get greeting from Genies API)

    func startConversation() async {
        guard !hasStartedConversation else { return }
        guard isPublished, let configId = configId else {
            error = "Character must be published before chatting."
            return
        }

        hasStartedConversation = true
        isLoading = true
        error = nil

        do {
            // Send empty input with empty session_id to start a new session
            let response = try await geniesService.sendMessage(
                input: "",
                sessionId: "",
                configId: configId
            )

            // Store the session ID for subsequent messages
            sessionId = response.sessionId

            // Display greeting
            let greetingMessage = ChatMessage(role: .assistant, content: response.message.content)
            messages.append(greetingMessage)

            NSLog("[CharacterChatViewModel] Started conversation, session: %@", sessionId)
        } catch {
            self.error = "Failed to get greeting: \(error.localizedDescription)"
            hasStartedConversation = false
        }

        isLoading = false
    }

    // MARK: - Send Message

    func sendMessage() async {
        let userMessage = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !userMessage.isEmpty else { return }
        guard isPublished, let configId = configId else {
            error = "Character must be published before chatting."
            return
        }

        // Add user message to display
        let userChatMessage = ChatMessage(role: .user, content: userMessage)
        messages.append(userChatMessage)

        // Clear input
        inputText = ""

        // Set loading state
        isLoading = true
        error = nil

        do {
            let response = try await geniesService.sendMessage(
                input: userMessage,
                sessionId: sessionId,
                configId: configId
            )

            // Update session ID (in case API returns a new one)
            if !response.sessionId.isEmpty {
                sessionId = response.sessionId
            }

            // Add assistant response
            let assistantMessage = ChatMessage(role: .assistant, content: response.message.content)
            messages.append(assistantMessage)

        } catch {
            self.error = "Failed to get response: \(error.localizedDescription)"
        }

        isLoading = false
    }

    // MARK: - Clear Chat

    func clearChat() {
        messages = []
        hasStartedConversation = false
        sessionId = ""
        error = nil

        // Restart conversation with new greeting
        Task {
            await startConversation()
        }
    }

    // MARK: - Update Character

    func updateCharacter(_ newCharacter: Character) {
        if character.id != newCharacter.id ||
            character.name != newCharacter.name ||
            character.sha != newCharacter.sha ||
            character.systemPromptType != newCharacter.systemPromptType {
            character = newCharacter
            messages = []
            hasStartedConversation = false
            sessionId = ""
            isPublished = false
            configId = nil
            Task {
                await loadChat()
            }
        }
    }
}
