import Foundation

@MainActor
@Observable
final class CharacterCreationViewModel {
    // Wizard state
    enum Step {
        case pathSelection
        case wikipediaInput
        case wikipediaPreview
        case originalInput
        case generating
        case review
    }

    enum CreationPath {
        case wikipedia
        case original
    }

    private(set) var currentStep: Step = .pathSelection
    private(set) var selectedPath: CreationPath?

    // Input state
    var wikipediaURL: String = ""
    var originalDescription: String = ""
    var useHighEffort: Bool = false

    // Preview state
    private(set) var previewCharacterName: String?
    private(set) var previewSnippet: String?
    private(set) var wikipediaContent: String?

    // Generation state
    private(set) var progressLogs: [String] = []
    private(set) var generatedContent: String = ""
    private(set) var sources: [String] = []

    // Result
    private(set) var savedCharacter: Character?

    // Error state
    var error: String?

    // Services
    private let localRepository: LocalCharacterRepository
    private let openAIService: OpenAIService?
    private let perplexityService: PerplexityService?
    private let asp1Template: String

    init(localRepository: LocalCharacterRepository, apiKeyManager: APIKeyManager) {
        self.localRepository = localRepository

        // Get OpenAI service
        if let apiKey = apiKeyManager.getAPIKey(for: .openAI) {
            self.openAIService = OpenAIService(apiKey: apiKey)
        } else {
            self.openAIService = nil
        }

        // Get Perplexity service for deep research
        if let apiKey = apiKeyManager.getAPIKey(for: .perplexity) {
            self.perplexityService = PerplexityService(apiKey: apiKey)
        } else {
            self.perplexityService = nil
        }

        // Load ASP-1 template
        let templatePath = "/Users/justin-genies/Code/CharacterPrompts/SystemPrompts/ASP/ASP1.md"
        self.asp1Template = (try? String(contentsOfFile: templatePath, encoding: .utf8)) ?? ""
    }

    // MARK: - Navigation

    func selectPath(_ path: CreationPath) {
        selectedPath = path
        error = nil

        switch path {
        case .wikipedia:
            currentStep = .wikipediaInput
        case .original:
            currentStep = .originalInput
        }
    }

    func goBack() {
        currentStep = .pathSelection
        error = nil
    }

    func discard() {
        currentStep = .pathSelection
        wikipediaURL = ""
        originalDescription = ""
        generatedContent = ""
        progressLogs = []
        error = nil
    }

    // MARK: - Wikipedia Preview

    func fetchWikipediaPreview() async {
        error = nil

        do {
            addLog("Fetching Wikipedia preview...")

            // Fetch Wikipedia content
            let content = try await fetchWikipediaContent(url: wikipediaURL)
            wikipediaContent = content

            // Extract title
            previewCharacterName = extractWikipediaTitle(from: wikipediaURL)?.replacingOccurrences(of: "_", with: " ")

            // Get first 300 characters as snippet
            previewSnippet = String(content.prefix(300)) + "..."

            currentStep = .wikipediaPreview

        } catch {
            self.error = "Failed to fetch Wikipedia content: \(error.localizedDescription)"
        }
    }

    // MARK: - Wikipedia Generation

    func generateFromWikipedia() async {
        guard let openAIService = openAIService else {
            error = "OpenAI API key not configured"
            return
        }

        guard let perplexityService = perplexityService else {
            error = "Perplexity API key not configured. Deep research requires Perplexity."
            return
        }

        error = nil
        currentStep = .generating
        progressLogs = []
        sources = []

        do {
            // Use cached content if available, otherwise fetch
            let wikiContent: String
            if let cached = wikipediaContent {
                wikiContent = cached
                addLog("Using cached Wikipedia content...")
            } else {
                addLog("Fetching Wikipedia content...")
                wikiContent = try await fetchWikipediaContent(url: wikipediaURL)
            }

            addLog("Retrieved \(wikiContent.count) characters from Wikipedia")

            // Extract character name for research query
            let characterName = previewCharacterName ?? extractWikipediaTitle(from: wikipediaURL)?.replacingOccurrences(of: "_", with: " ") ?? "Unknown"

            // Step 1: Deep research with Perplexity
            let effort: ReasoningEffort = useHighEffort ? .high : .medium
            addLog("Starting deep research on \(characterName) with Perplexity...")
            addLog("Reasoning effort: \(effort.displayName)")

            let researchResult = try await perplexityService.deepResearch(
                query: """
                Research everything about \(characterName) for building a comprehensive AI character profile.

                Include:
                - Complete biography and background
                - Personality traits and psychological profile
                - Communication style, catchphrases, and speech patterns
                - Core values and beliefs
                - Key relationships (family, friends, rivals, partners)
                - Career milestones and achievements
                - Recent news and current situation
                - Physical appearance and style
                - Behavioral mannerisms
                - Transformative life moments
                - Cultural impact and legacy
                - Controversies and challenges
                - Direct quotes that reveal character
                - Interests and passions

                Wikipedia context:
                \(wikiContent.prefix(3000))
                """,
                effort: effort,
                onProgress: { [weak self] message in
                    Task { @MainActor in
                        self?.addLog(message)
                    }
                }
            )

            sources = researchResult.citations
            addLog("Deep research complete with \(researchResult.citations.count) sources")
            addLog("Research content: \(researchResult.content.count) characters")

            // Step 2: Generate character using OpenAI with the research
            addLog("Generating rich character profile using ASP-1 template...")

            let prompt = buildResearchBasedPrompt(
                characterName: characterName,
                research: researchResult.content,
                citations: researchResult.citations
            )

            generatedContent = try await openAIService.chat(messages: [
                ["role": "system", "content": "You are an expert character designer that creates incredibly detailed, rich character personas. Your characters feel alive, with deep backstories, nuanced personalities, and authentic voices. Follow the ASP-1 template structure exactly."],
                ["role": "user", "content": prompt]
            ], model: "gpt-4o")

            addLog("Character generated successfully!")
            addLog("Word count: \(generatedContent.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count)")

            currentStep = .review

        } catch {
            self.error = "Failed to generate character: \(error.localizedDescription)"
            currentStep = .wikipediaPreview
        }
    }

    func goBackFromPreview() {
        currentStep = .wikipediaInput
        previewCharacterName = nil
        previewSnippet = nil
        wikipediaContent = nil
        error = nil
    }

    // MARK: - Original Generation

    func generateOriginal() async {
        guard let openAIService = openAIService else {
            error = "OpenAI API key not configured"
            return
        }

        error = nil
        currentStep = .generating
        progressLogs = []
        sources = []

        do {
            // Check if description mentions a real person we can research
            let isRealPerson = await checkIfRealPerson(originalDescription)

            if isRealPerson, let perplexityService = perplexityService {
                // Deep research path for real people
                let effort: ReasoningEffort = useHighEffort ? .high : .medium
                addLog("Detected real person. Starting deep research with Perplexity...")
                addLog("Reasoning effort: \(effort.displayName)")

                let researchResult = try await perplexityService.deepResearch(
                    query: """
                    Research everything about the following person for building a comprehensive AI character profile:

                    \(originalDescription)

                    Include:
                    - Complete biography and background
                    - Personality traits and psychological profile
                    - Communication style, catchphrases, and speech patterns
                    - Core values and beliefs
                    - Key relationships (family, friends, rivals, partners)
                    - Career milestones and achievements
                    - Recent news and current situation
                    - Physical appearance and style
                    - Behavioral mannerisms
                    - Transformative life moments
                    - Cultural impact and legacy
                    - Controversies and challenges
                    - Direct quotes that reveal character
                    - Interests and passions
                    """,
                    effort: effort,
                    onProgress: { [weak self] message in
                        Task { @MainActor in
                            self?.addLog(message)
                        }
                    }
                )

                sources = researchResult.citations
                addLog("Deep research complete with \(researchResult.citations.count) sources")

                // Extract name from description or research
                let characterName = extractNameFromDescription(originalDescription) ?? "Character"

                // Generate with research
                addLog("Generating rich character profile using ASP-1 template...")

                let prompt = buildResearchBasedPrompt(
                    characterName: characterName,
                    research: researchResult.content,
                    citations: researchResult.citations
                )

                generatedContent = try await openAIService.chat(messages: [
                    ["role": "system", "content": "You are an expert character designer that creates incredibly detailed, rich character personas. Your characters feel alive, with deep backstories, nuanced personalities, and authentic voices. Follow the ASP-1 template structure exactly."],
                    ["role": "user", "content": prompt]
                ], model: "gpt-4o")

            } else {
                // Creative generation path for fictional characters
                addLog("Creating original fictional character...")
                addLog("Generating character using ASP-1 template...")

                let prompt = buildOriginalPrompt(description: originalDescription)
                generatedContent = try await openAIService.chat(messages: [
                    ["role": "system", "content": "You are a creative character generation assistant that creates detailed character personas following the ASP-1 template. Make the character feel real with rich backstory and authentic voice."],
                    ["role": "user", "content": prompt]
                ], model: "gpt-4o")
            }

            addLog("Character generated successfully!")
            addLog("Word count: \(generatedContent.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count)")

            currentStep = .review

        } catch {
            self.error = "Failed to generate character: \(error.localizedDescription)"
            currentStep = .originalInput
        }
    }

    /// Check if the description refers to a real person using quick heuristics
    private func checkIfRealPerson(_ description: String) async -> Bool {
        // Simple heuristics: look for indicators of real people
        let realPersonIndicators = [
            "celebrity", "athlete", "actor", "actress", "singer", "musician",
            "politician", "president", "ceo", "founder", "influencer",
            "youtuber", "tiktoker", "boxer", "fighter", "player",
            "born in", "famous for", "known for", "real person"
        ]

        let lowercased = description.lowercased()
        return realPersonIndicators.contains { lowercased.contains($0) }
    }

    /// Extract a name from the description
    private func extractNameFromDescription(_ description: String) -> String? {
        // Look for patterns like "Create a character for X" or names at the start
        let lines = description.components(separatedBy: .newlines)
        if let firstLine = lines.first {
            // If it starts with a capitalized name pattern
            let words = firstLine.components(separatedBy: " ")
            if words.count >= 2 {
                let potentialName = words.prefix(3).joined(separator: " ")
                if potentialName.first?.isUppercase == true {
                    return potentialName
                }
            }
        }
        return nil
    }

    // MARK: - Save

    func saveCharacter(content: String) async {
        do {
            // Extract character name from content
            let characterName = extractCharacterName(from: content) ?? "New Character"

            // Create character
            let character = try await localRepository.createCharacter(
                name: characterName,
                markdownContent: content
            )

            savedCharacter = character

        } catch {
            self.error = "Failed to save character: \(error.localizedDescription)"
        }
    }

    // MARK: - Private Helpers

    private func addLog(_ message: String) {
        progressLogs.append(message)
    }

    private func fetchWikipediaContent(url: String) async throws -> String {
        // Parse Wikipedia URL to get article title
        guard let articleTitle = extractWikipediaTitle(from: url) else {
            throw CharacterCreationError.invalidWikipediaURL
        }

        // Fetch from Wikipedia API
        let apiURL = "https://en.wikipedia.org/w/api.php?action=query&prop=extracts&exintro=false&explaintext=true&titles=\(articleTitle)&format=json"

        guard let requestURL = URL(string: apiURL.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "") else {
            throw CharacterCreationError.invalidWikipediaURL
        }

        let (data, _) = try await URLSession.shared.data(from: requestURL)

        // Parse JSON response
        struct WikiResponse: Codable {
            let query: Query
            struct Query: Codable {
                let pages: [String: Page]
            }
            struct Page: Codable {
                let extract: String?
            }
        }

        let response = try JSONDecoder().decode(WikiResponse.self, from: data)

        guard let page = response.query.pages.values.first,
              let extract = page.extract else {
            throw CharacterCreationError.wikipediaContentNotFound
        }

        return extract
    }

    private func extractWikipediaTitle(from url: String) -> String? {
        // Extract title from URL like: https://en.wikipedia.org/wiki/Jake_Paul
        guard let components = URLComponents(string: url),
              components.host?.contains("wikipedia.org") == true,
              let path = components.path.components(separatedBy: "/").last else {
            return nil
        }
        return path
    }

    private func buildWikipediaPrompt(wikipediaContent: String) -> String {
        """
        Using the following ASP-1 template and Wikipedia content, generate a complete character persona.

        REQUIREMENTS:
        - Minimum 1000 words
        - High-impact details only - no filler, no repetition, no fluff
        - Follow the ASP-1 structure exactly
        - Write in active, kinetic language
        - Replace all placeholder sections with real content
        - Make it feel like the character is in the middle of action RIGHT NOW

        ASP-1 TEMPLATE:
        \(asp1Template)

        WIKIPEDIA CONTENT:
        \(wikipediaContent)

        Generate the complete character persona now:
        """
    }

    private func buildOriginalPrompt(description: String) -> String {
        """
        Using the following ASP-1 template and character description, creatively expand this into a complete character persona.

        REQUIREMENTS:
        - Minimum 1000 words
        - High-impact details only - no filler, no repetition, no fluff
        - Follow the ASP-1 structure exactly
        - Write in active, kinetic language
        - Create rich backstory, personality, relationships, and goals
        - Make it feel like the character is in the middle of action RIGHT NOW

        ASP-1 TEMPLATE:
        \(asp1Template)

        CHARACTER DESCRIPTION:
        \(description)

        Generate the complete character persona now:
        """
    }

    private func buildResearchBasedPrompt(characterName: String, research: String, citations: [String]) -> String {
        let sourcesSection = citations.isEmpty ? "" : """

        RESEARCH SOURCES:
        \(citations.enumerated().map { "[\($0.offset + 1)] \($0.element)" }.joined(separator: "\n"))
        """

        return """
        You are creating a comprehensive AI character persona for \(characterName).

        You have been provided with EXHAUSTIVE RESEARCH from multiple sources. Your job is to transform this research into an incredibly rich, detailed, and authentic character profile following the ASP-1 template structure.

        CRITICAL REQUIREMENTS:
        - MINIMUM 2000 words (aim for 2500+)
        - Use EVERY relevant detail from the research
        - Include specific dates, numbers, names, and facts
        - Write vivid, active prose that brings the character to life
        - Make the "Current Situation" feel immediate and urgent
        - Include at least 5 key relationships with specific dynamics
        - Include at least 5 transformative story moments
        - The "Communication & Speech" section should include actual quotes and speech patterns
        - Include physical details, mannerisms, and behavioral quirks
        - Make the character feel like they're in the middle of action RIGHT NOW

        QUALITY STANDARDS:
        - No placeholder text - every section must be fully realized
        - No generic descriptions - be specific and concrete
        - No repetition - each section should add new information
        - Write like you're creating a character bible for a major production
        - The result should feel as rich as "Here's to the crazy ones" manifesto - every word intentional

        ASP-1 TEMPLATE STRUCTURE TO FOLLOW:
        \(asp1Template)

        COMPREHENSIVE RESEARCH ON \(characterName.uppercased()):
        \(research)
        \(sourcesSection)

        Generate the complete, production-ready character persona now. Make it extraordinary:
        """
    }

    private func extractCharacterName(from content: String) -> String? {
        // Look for "## Your Persona: [Name]" pattern
        let pattern = "##\\s*Your Persona:\\s*(.+)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return nil
        }

        let nsString = content as NSString
        let matches = regex.matches(in: content, range: NSRange(location: 0, length: nsString.length))

        guard let match = matches.first,
              match.numberOfRanges > 1 else {
            return nil
        }

        let nameRange = match.range(at: 1)
        let name = nsString.substring(with: nameRange)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return name.isEmpty ? nil : name
    }
}

// MARK: - Errors

enum CharacterCreationError: LocalizedError {
    case invalidWikipediaURL
    case wikipediaContentNotFound
    case generationFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidWikipediaURL:
            return "Invalid Wikipedia URL. Please enter a valid Wikipedia article URL."
        case .wikipediaContentNotFound:
            return "Could not find content for this Wikipedia article."
        case .generationFailed(let message):
            return "Character generation failed: \(message)"
        }
    }
}
