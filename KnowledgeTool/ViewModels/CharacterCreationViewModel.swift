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
    private let asp1Template: String

    init(localRepository: LocalCharacterRepository, apiKeyManager: APIKeyManager) {
        self.localRepository = localRepository

        // Get OpenAI service
        if let apiKey = apiKeyManager.getAPIKey(for: .openAI) {
            self.openAIService = OpenAIService(apiKey: apiKey)
        } else {
            self.openAIService = nil
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

        error = nil
        currentStep = .generating
        progressLogs = []

        do {
            // Use cached content if available, otherwise fetch
            let content: String
            if let cached = wikipediaContent {
                content = cached
                addLog("Using cached Wikipedia content...")
            } else {
                addLog("Fetching Wikipedia content...")
                content = try await fetchWikipediaContent(url: wikipediaURL)
            }

            addLog("Retrieved \(content.count) characters from Wikipedia")
            addLog("Generating character using ASP-1 template...")

            // Generate character using OpenAI
            let prompt = buildWikipediaPrompt(wikipediaContent: content)
            generatedContent = try await openAIService.chat(messages: [
                ["role": "system", "content": "You are a character generation assistant that creates detailed character personas following the ASP-1 template."],
                ["role": "user", "content": prompt]
            ], model: "gpt-4o-mini")

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

        do {
            addLog("Expanding character description...")
            addLog("Generating character using ASP-1 template...")

            // Generate character using OpenAI
            let prompt = buildOriginalPrompt(description: originalDescription)
            generatedContent = try await openAIService.chat(messages: [
                ["role": "system", "content": "You are a creative character generation assistant that creates detailed character personas following the ASP-1 template."],
                ["role": "user", "content": prompt]
            ], model: "gpt-4o-mini")

            addLog("Character generated successfully!")
            addLog("Word count: \(generatedContent.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count)")

            currentStep = .review

        } catch {
            self.error = "Failed to generate character: \(error.localizedDescription)"
            currentStep = .originalInput
        }
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
