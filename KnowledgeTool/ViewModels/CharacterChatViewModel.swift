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
    
    // Cached full system prompt (template + persona + scenario + dialog examples)
    private var cachedFullSystemPrompt: String?
    private var cachedFullSystemPromptKey: String?

    // OpenAI service (created lazily when needed)
    private var openAIService: OpenAIService?

    // System prompt service
    private let systemPromptService = SystemPromptService.shared
    
    // Chat model tuning (chat should be fast; heavier models can be used elsewhere)
    private static let chatModel = "gpt-5"
    private static let chatMaxCompletionTokens = 700
    private static let greetingMaxCompletionTokens = 250
    
    private static func durationMs(_ duration: Duration) -> Double {
        let c = duration.components
        return (Double(c.seconds) * 1_000) + (Double(c.attoseconds) / 1_000_000_000_000_000)
    }

    init(character: Character, apiKeyManager: APIKeyManager) {
        self.character = character
        self.selectedPromptType = character.systemPromptType
        self.apiKeyManager = apiKeyManager
    }

    // MARK: - System Prompt Loading

    func loadSystemPrompt() async {
        let clock = ContinuousClock()
        let t0 = clock.now
        
        isLoadingSystemPrompt = true
        error = nil

        // Reset chat state when loading new prompt
        messages = []
        conversationHistory = []
        hasStartedConversation = false
        invalidateFullSystemPromptCache()

        // For local characters without Supabase, use bundled template
        if character.isLocalOnly && SupabaseConfig.shared == nil {
            NSLog("[CharacterChatViewModel] Local character without Supabase, using bundled template")
            systemPromptContent = BundledSystemPromptTemplates.content(for: selectedPromptType)
            systemPromptLoaded = true
            isLoadingSystemPrompt = false
            _ = await getFullSystemPrompt() // warm cache for first send
            NSLog("[CharacterChatViewModel] loadSystemPrompt (bundled) took %.0fms", Self.durationMs(t0.duration(to: clock.now)))
            await startConversation()
            return
        }

        // Fetch system prompt from SystemPromptService (handles caching and fallbacks)
        let template = await systemPromptService.getTemplate(for: selectedPromptType)
        systemPromptContent = template
        systemPromptLoaded = true

        isLoadingSystemPrompt = false
        _ = await getFullSystemPrompt() // warm cache for first send
        NSLog("[CharacterChatViewModel] loadSystemPrompt took %.0fms", Self.durationMs(t0.duration(to: clock.now)))

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
            let systemPrompt = await getFullSystemPrompt()
            var apiMessages: [[String: String]] = [["role": "system", "content": systemPrompt]]

            // Add the hidden greeting prompt
            apiMessages.append(["role": "user", "content": Self.initialGreetingPrompt])

            // Call OpenAI
            let response = try await openAIService!.chat(
                messages: apiMessages,
                model: Self.chatModel,
                maxCompletionTokens: Self.greetingMaxCompletionTokens,
                temperature: 0.9,
                timeoutInterval: 45
            )

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

    // MARK: - Full System Prompt Cache
    
    private func invalidateFullSystemPromptCache() {
        cachedFullSystemPrompt = nil
        cachedFullSystemPromptKey = nil
    }
    
    private func fullSystemPromptCacheKey() -> String {
        let scenarioSHA = character.knowledgeFiles.first(where: { $0.fileName == "scenarios.jsonl" })?.sha ?? ""
        let dialogSHA = character.knowledgeFiles.first(where: { $0.fileName == "dialog_examples.jsonl" })?.sha ?? ""
        
        // Avoid storing the full template/persona in the key; hashes are enough to detect changes.
        return [
            selectedPromptType.rawValue,
            String(systemPromptContent.hashValue),
            String(character.markdownContent.hashValue),
            scenarioSHA,
            dialogSHA
        ].joined(separator: "|")
    }
    
    private func getFullSystemPrompt() async -> String {
        let key = fullSystemPromptCacheKey()
        if let cached = cachedFullSystemPrompt, cachedFullSystemPromptKey == key {
            return cached
        }
        
        // Snapshot inputs so building can happen off the main actor.
        let inputs = PromptBuildInputs(
            template: systemPromptContent,
            personaMarkdown: character.markdownContent,
            knowledgeFiles: character.knowledgeFiles
        )
        
        let clock = ContinuousClock()
        let t0 = clock.now
        let built = await Task.detached(priority: .userInitiated) {
            Self.buildFullSystemPrompt(inputs: inputs)
        }.value
        NSLog("[CharacterChatViewModel] Built full system prompt in %.0fms (chars=%d)", Self.durationMs(t0.duration(to: clock.now)), built.count)
        
        cachedFullSystemPrompt = built
        cachedFullSystemPromptKey = key
        return built
    }
    
    private struct PromptBuildInputs: Sendable {
        let template: String
        let personaMarkdown: String
        let knowledgeFiles: [KnowledgeFile]
    }
    
    nonisolated private static func buildFullSystemPrompt(inputs: PromptBuildInputs) -> String {
        var fullPrompt = inputs.template
        
        // 1) Replace persona placeholder with actual character markdown
        fullPrompt = replacePersonaSection(in: fullPrompt, with: inputs.personaMarkdown)
        
        // 2) Inject active scenario (if present)
        fullPrompt = injectActiveScenario(in: fullPrompt, knowledgeFiles: inputs.knowledgeFiles)
        
        // 3) Append dialogue examples (if present)
        let dialogueSection = buildDialogueExamplesSection(knowledgeFiles: inputs.knowledgeFiles)
        if !dialogueSection.isEmpty {
            fullPrompt += "\n\n" + dialogueSection
        }
        
        return fullPrompt
    }

    // MARK: - Persona Section Replacement

    /// Replace the "## Your Persona" placeholder section with actual character persona content
    nonisolated private static func replacePersonaSection(in template: String, with personaContent: String) -> String {
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

        // Replace the placeholder with actual persona content (literal replacement, not a regex template)
        let trimmedPersona = personaContent.trimmingCharacters(in: .whitespacesAndNewlines)
        let replacementSection: String
        if trimmedPersona.range(of: #"(?m)^##\s*Your Persona"#, options: .regularExpression) != nil {
            replacementSection = trimmedPersona
        } else {
            replacementSection = "## Your Persona\n\n" + trimmedPersona
        }

        guard let match = matches.first else {
            return template + "\n\n" + replacementSection
        }

        let before = nsString.substring(to: match.range.location)
        return before + replacementSection
    }

    // MARK: - Scenario Injection

    /// Inject active scenario content into the system prompt
    nonisolated private static func injectActiveScenario(in prompt: String, knowledgeFiles: [KnowledgeFile]) -> String {
        guard let activeScenario = loadActiveScenario(knowledgeFiles: knowledgeFiles) else {
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
    nonisolated private static func loadActiveScenario(knowledgeFiles: [KnowledgeFile]) -> Scenario? {
        guard let scenarioFile = knowledgeFiles.first(where: { $0.fileName == "scenarios.jsonl" }) else {
            return nil
        }

        let scenarios = parseScenariosJSONL(scenarioFile.content)
        return scenarios.first(where: { $0.isActive })
    }

    /// Parse scenarios.jsonl content into Scenario objects
    nonisolated private static func parseScenariosJSONL(_ content: String) -> [Scenario] {
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
    nonisolated private static func replaceOrInjectSection(in prompt: String, sectionName: String, content: String) -> String {
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
    nonisolated private static func buildDialogueExamplesSection(knowledgeFiles: [KnowledgeFile]) -> String {
        // Look for dialog_examples.jsonl in knowledge files
        guard let dialogFile = knowledgeFiles.first(where: { $0.fileName == "dialog_examples.jsonl" }) else {
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
    nonisolated private static func parseDialogExamplesJSONL(_ content: String) -> [DialogExample] {
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

        let clock = ContinuousClock()
        let t0 = clock.now
        
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

            let systemPrompt = await getFullSystemPrompt()
            let historySnapshot = conversationHistory
            let apiMessages: [[String: String]] = await Task.detached(priority: .userInitiated) {
                var result: [[String: String]] = [["role": "system", "content": systemPrompt]]
                result.reserveCapacity(historySnapshot.count + 1)
                for message in historySnapshot {
                    let role = message.role == .user ? "user" : "assistant"
                    result.append(["role": role, "content": message.content])
                }
                return result
            }.value

            // Call OpenAI
            let response = try await openAIService!.chat(
                messages: apiMessages,
                model: Self.chatModel,
                maxCompletionTokens: Self.chatMaxCompletionTokens,
                temperature: 0.9,
                timeoutInterval: 60
            )

            // Add assistant response to both histories
            let assistantMessage = ChatMessage(role: .assistant, content: response)
            messages.append(assistantMessage)
            conversationHistory.append(assistantMessage)
            
            NSLog("[CharacterChatViewModel] sendMessage total time %.0fms (history=%d, promptChars=%d)", Self.durationMs(t0.duration(to: clock.now)), conversationHistory.count, systemPrompt.count)

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
        if character.id != newCharacter.id ||
            character.name != newCharacter.name ||
            character.sha != newCharacter.sha ||
            character.systemPromptType != newCharacter.systemPromptType {
            character = newCharacter
            selectedPromptType = newCharacter.systemPromptType
            messages = []
            conversationHistory = []
            hasStartedConversation = false
            systemPromptLoaded = false
            invalidateFullSystemPromptCache()
            Task {
                await loadSystemPrompt()
            }
        }
    }
}
