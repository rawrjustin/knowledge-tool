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

    // System prompt service
    private let systemPromptService = SystemPromptService.shared

    init(character: Character, apiKeyManager: APIKeyManager) {
        self.character = character
        self.selectedPromptType = character.systemPromptType
        self.apiKeyManager = apiKeyManager
    }

    // MARK: - System Prompt Loading

    func loadSystemPrompt() async {
        isLoadingSystemPrompt = true
        error = nil

        // Reset chat state when loading new prompt
        messages = []
        conversationHistory = []
        hasStartedConversation = false

        // For local characters without Supabase, use bundled template
        if character.isLocalOnly && SupabaseConfig.shared == nil {
            NSLog("[CharacterChatViewModel] Local character without Supabase, using bundled template")
            systemPromptContent = ASP1Template.content
            systemPromptLoaded = true
            isLoadingSystemPrompt = false
            await startConversation()
            return
        }

        // Fetch system prompt from SystemPromptService (handles caching and fallbacks)
        let template = await systemPromptService.getTemplate(for: selectedPromptType)
        systemPromptContent = template
        systemPromptLoaded = true

        isLoadingSystemPrompt = false

        // Automatically start conversation with greeting
        await startConversation()
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
        var fullPrompt = systemPromptContent

        // 1. Replace "## Your Persona" section with actual character content
        fullPrompt = replacePersonaSection(in: fullPrompt, with: character.markdownContent)

        // 2. Inject active scenario (Current Situation and Live Objective)
        fullPrompt = injectActiveScenario(in: fullPrompt)

        // 3. Append dialogue examples section
        let dialogueSection = buildDialogueExamplesSection()
        if !dialogueSection.isEmpty {
            fullPrompt += "\n\n" + dialogueSection
        }

        return fullPrompt
    }

    // MARK: - Persona Section Replacement

    /// Replace the "## Your Persona" placeholder section with actual character persona content
    private func replacePersonaSection(in template: String, with personaContent: String) -> String {
        // Pattern to match from "## Your Persona" through to the end of the template
        // This replaces the entire placeholder section including My Persona and Example Dialog placeholders
        // since the character's persona content already includes those sections
        let pattern = "## Your Persona[:\\s]*\\[?[^\\]]*\\]?[\\s\\S]*\\z"

        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            // If regex fails, just append persona at the end
            NSLog("[CharacterChatViewModel] Regex failed, appending persona to end")
            return template + "\n\n## Your Persona\n\n" + personaContent
        }

        let nsString = template as NSString
        let range = NSRange(location: 0, length: nsString.length)
        let matches = regex.matches(in: template, range: range)

        if matches.isEmpty {
            // No placeholder found, append persona section
            NSLog("[CharacterChatViewModel] No persona placeholder found, appending to end")
            return template + "\n\n## Your Persona\n\n" + personaContent
        }

        // Replace the placeholder with actual persona content
        let replacementSection = "## Your Persona\n\n" + personaContent
        let result = regex.stringByReplacingMatches(
            in: template,
            range: range,
            withTemplate: replacementSection
        )

        return result
    }

    // MARK: - Scenario Injection

    /// Inject active scenario content into the system prompt
    private func injectActiveScenario(in prompt: String) -> String {
        guard let activeScenario = loadActiveScenario() else {
            return prompt
        }

        var result = prompt

        // Replace or inject Current Situation
        result = replaceOrInjectSection(
            in: result,
            sectionName: "Current Situation",
            content: activeScenario.currentSituation
        )

        // Replace or inject Live Objective
        result = replaceOrInjectSection(
            in: result,
            sectionName: "Live Objective",
            content: activeScenario.liveObjective
        )

        return result
    }

    /// Load the active scenario from scenarios.jsonl
    private func loadActiveScenario() -> Scenario? {
        guard let scenarioFile = character.knowledgeFiles.first(where: { $0.fileName == "scenarios.jsonl" }) else {
            return nil
        }

        let scenarios = parseScenariosJSONL(scenarioFile.content)
        return scenarios.first(where: { $0.isActive })
    }

    /// Parse scenarios.jsonl content into Scenario objects
    private func parseScenariosJSONL(_ content: String) -> [Scenario] {
        let lines = content.components(separatedBy: .newlines)
        var scenarios: [Scenario] = []

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            guard let data = trimmed.data(using: .utf8) else { continue }

            do {
                let scenario = try decoder.decode(Scenario.self, from: data)
                scenarios.append(scenario)
            } catch {
                NSLog("[CharacterChatViewModel] Failed to parse scenario: %@", error.localizedDescription)
            }
        }

        return scenarios
    }

    /// Replace or inject a section in the prompt
    private func replaceOrInjectSection(in prompt: String, sectionName: String, content: String) -> String {
        // Pattern to match "### Section Name" followed by content until the next section or end
        let pattern = "###\\s*\(NSRegularExpression.escapedPattern(for: sectionName))\\s*\\n[\\s\\S]*?(?=\\n###|\\n##|$)"

        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            // If regex fails, try to append after persona section
            return prompt + "\n\n### \(sectionName)\n\(content)"
        }

        let nsString = prompt as NSString
        let range = NSRange(location: 0, length: nsString.length)
        let matches = regex.matches(in: prompt, range: range)

        if matches.isEmpty {
            // Section not found - try to insert after "## Your Persona" section
            let personaPattern = "##\\s*Your Persona[\\s\\S]*?(?=\\n##|$)"
            if let personaRegex = try? NSRegularExpression(pattern: personaPattern, options: [.caseInsensitive]),
               let personaMatch = personaRegex.firstMatch(in: prompt, range: range) {
                let insertPoint = personaMatch.range.location + personaMatch.range.length
                let before = nsString.substring(to: insertPoint)
                let after = nsString.substring(from: insertPoint)
                return before + "\n\n### \(sectionName)\n\(content)" + after
            }
            // Fallback: append at end
            return prompt + "\n\n### \(sectionName)\n\(content)"
        }

        // Replace existing section
        let replacement = "### \(sectionName)\n\(content)"
        return regex.stringByReplacingMatches(
            in: prompt,
            range: range,
            withTemplate: replacement
        )
    }

    // MARK: - Dialogue Examples

    /// Build the dialogue examples section from character's knowledge files
    private func buildDialogueExamplesSection() -> String {
        // Look for dialog_examples.jsonl in knowledge files
        guard let dialogFile = character.knowledgeFiles.first(where: { $0.fileName == "dialog_examples.jsonl" }) else {
            return ""
        }

        // Parse JSONL content
        let examples = parseDialogExamplesJSONL(dialogFile.content)

        if examples.isEmpty {
            return ""
        }

        // Group examples by category
        let grouped = Dictionary(grouping: examples) { $0.categoryId }

        var section = "## Dialogue Examples\n"

        // Build each category section (limit 5 examples per category)
        for category in DialogCategories.all {
            guard let categoryExamples = grouped[category.id], !categoryExamples.isEmpty else {
                continue
            }

            section += "\n### \(category.name)\n"

            let limitedExamples = Array(categoryExamples.prefix(5))
            for example in limitedExamples {
                // Format as quoted dialog
                let cleanDialog = example.dialog
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: "\n", with: " ")
                section += "- \"\(cleanDialog)\"\n"
            }
        }

        return section
    }

    /// Parse dialog_examples.jsonl content into DialogExample objects
    private func parseDialogExamplesJSONL(_ content: String) -> [DialogExample] {
        let lines = content.components(separatedBy: .newlines)
        var examples: [DialogExample] = []

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            guard let data = trimmed.data(using: .utf8) else { continue }

            do {
                let example = try decoder.decode(DialogExample.self, from: data)
                examples.append(example)
            } catch {
                // Skip malformed lines
                NSLog("[CharacterChatViewModel] Failed to parse dialog example: %@", error.localizedDescription)
            }
        }

        return examples
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
