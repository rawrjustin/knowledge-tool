import Foundation

/// Source types for brain augmentation
enum AugmentationSourceType: String, CaseIterable, Codable {
    case youtubeVideo = "youtube"
    case webLink = "link"
    case text = "text"

    var displayName: String {
        switch self {
        case .youtubeVideo: return "YouTube Video"
        case .webLink: return "Web Link"
        case .text: return "Text Content"
        }
    }

    var icon: String {
        switch self {
        case .youtubeVideo: return "play.rectangle.fill"
        case .webLink: return "link"
        case .text: return "doc.text.fill"
        }
    }
}

/// A suggested augmentation to the persona
struct PersonaAugmentation: Identifiable, Codable {
    let id: UUID
    let section: String          // Which persona section this relates to (e.g., "Personality", "Background", "Speech Patterns")
    let currentContent: String?  // Existing content in that section (if any)
    let suggestedAddition: String // The new content to add
    let rationale: String        // Why this should be added
    let confidence: Double       // 0.0-1.0 how confident the model is this is relevant
    let sourceExcerpt: String    // The part of the source this came from
    var isSelected: Bool         // User's selection

    init(id: UUID = UUID(), section: String, currentContent: String?, suggestedAddition: String, rationale: String, confidence: Double, sourceExcerpt: String, isSelected: Bool = true) {
        self.id = id
        self.section = section
        self.currentContent = currentContent
        self.suggestedAddition = suggestedAddition
        self.rationale = rationale
        self.confidence = confidence
        self.sourceExcerpt = sourceExcerpt
        self.isSelected = isSelected
    }
}

/// A RAG knowledge entry generated from augmentation analysis
struct AugmentationKnowledgeEntry: Codable {
    let id: String
    let section: String
    let content: String
    let keywords: [String]
}

/// Result of augmentation analysis
struct AugmentationAnalysisResult {
    let sourceType: AugmentationSourceType
    let sourceTitle: String
    let sourceSummary: String
    let augmentations: [PersonaAugmentation]
    let ragEntries: [AugmentationKnowledgeEntry]  // Items better suited for RAG
    let processedAt: Date
}

/// Service for analyzing content and generating persona augmentations
actor AugmentationService {
    private let openAIApiKey: String
    private let assemblyAIApiKey: String?
    private let model = "gpt-5"
    private let session: URLSession

    init(openAIApiKey: String, assemblyAIApiKey: String? = nil) {
        self.openAIApiKey = openAIApiKey
        self.assemblyAIApiKey = assemblyAIApiKey

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 300
        config.timeoutIntervalForResource = 600
        self.session = URLSession(configuration: config)
    }

    // MARK: - Public API

    /// Analyze content and generate persona augmentation suggestions
    func analyzeForAugmentation(
        character: Character,
        sourceType: AugmentationSourceType,
        content: String,
        sourceTitle: String,
        onProgress: @escaping @Sendable (String) -> Void
    ) async throws -> AugmentationAnalysisResult {
        onProgress("Analyzing content for \(character.name)...")

        // Extract current persona sections
        let personaSections = extractPersonaSections(from: character.markdownContent)

        onProgress("Identifying relevant information...")

        // Generate augmentation suggestions
        let analysisPrompt = buildAnalysisPrompt(
            characterName: character.name,
            personaSections: personaSections,
            sourceType: sourceType
        )

        let response = try await callOpenAI(
            systemPrompt: analysisPrompt,
            userContent: """
            SOURCE TITLE: \(sourceTitle)

            SOURCE CONTENT:
            \(content)
            """
        )

        onProgress("Processing suggestions...")

        // Parse the response
        let result = try parseAnalysisResponse(
            response: response,
            sourceType: sourceType,
            sourceTitle: sourceTitle
        )

        onProgress("Found \(result.augmentations.count) persona updates and \(result.ragEntries.count) knowledge entries")

        return result
    }

    /// Process a YouTube video for augmentation
    func processYouTubeVideo(
        character: Character,
        videoURL: String,
        onProgress: @escaping @Sendable (String) -> Void
    ) async throws -> AugmentationAnalysisResult {
        guard let assemblyAIKey = assemblyAIApiKey else {
            throw AugmentationError.missingAPIKey("AssemblyAI API key required for video processing")
        }

        onProgress("Downloading video...")
        let videoService = VideoService()
        let (audioURL, videoInfo) = try await videoService.downloadAndExtractAudio(from: videoURL)

        defer {
            Task {
                await videoService.cleanup(audioURL: audioURL)
            }
        }

        onProgress("Transcribing audio...")
        let assemblyAI = AssemblyAIService(apiKey: assemblyAIKey)
        let transcript = try await assemblyAI.transcribeAudio(fileURL: audioURL)

        // Format transcript with speaker labels if available
        var formattedTranscript = ""
        if let speakerLabels = transcript.speakerLabels, !speakerLabels.isEmpty {
            for utterance in speakerLabels {
                formattedTranscript += "\(utterance.speaker): \(utterance.text)\n\n"
            }
        } else {
            formattedTranscript = transcript.text
        }

        return try await analyzeForAugmentation(
            character: character,
            sourceType: .youtubeVideo,
            content: formattedTranscript,
            sourceTitle: videoInfo.title,
            onProgress: onProgress
        )
    }

    /// Process a web link for augmentation
    func processWebLink(
        character: Character,
        url: String,
        onProgress: @escaping @Sendable (String) -> Void
    ) async throws -> AugmentationAnalysisResult {
        onProgress("Fetching web content...")

        // Use a simple web fetch (could be enhanced with Jina or similar)
        guard let requestURL = URL(string: url) else {
            throw AugmentationError.invalidURL
        }

        var request = URLRequest(url: requestURL)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw AugmentationError.fetchFailed("Failed to fetch web content")
        }

        guard let htmlContent = String(data: data, encoding: .utf8) else {
            throw AugmentationError.fetchFailed("Failed to decode web content")
        }

        // Extract text from HTML (basic extraction)
        let textContent = extractTextFromHTML(htmlContent)
        let title = extractTitleFromHTML(htmlContent) ?? url

        return try await analyzeForAugmentation(
            character: character,
            sourceType: .webLink,
            content: textContent,
            sourceTitle: title,
            onProgress: onProgress
        )
    }

    /// Apply selected augmentations to the persona markdown
    /// This is a pure function that doesn't require actor isolation
    nonisolated func applyAugmentations(
        to markdownContent: String,
        augmentations: [PersonaAugmentation]
    ) -> String {
        var updatedContent = markdownContent

        // Group augmentations by section
        let selectedAugmentations = augmentations.filter { $0.isSelected }
        let bySection = Dictionary(grouping: selectedAugmentations) { $0.section }

        for (section, sectionAugmentations) in bySection {
            // Find the section in the markdown
            let sectionPattern = "##\\s*\(NSRegularExpression.escapedPattern(for: section))[\\s\\S]*?(?=\\n##|\\z)"

            if let regex = try? NSRegularExpression(pattern: sectionPattern, options: [.caseInsensitive]),
               let match = regex.firstMatch(in: updatedContent, range: NSRange(updatedContent.startIndex..., in: updatedContent)) {

                // Section exists - append to it
                let range = Range(match.range, in: updatedContent)!
                let existingSection = String(updatedContent[range])

                // Build additions
                let additions = sectionAugmentations.map { $0.suggestedAddition }.joined(separator: "\n\n")

                // Append to section (before the next ## or end)
                let updatedSection = existingSection.trimmingCharacters(in: .whitespacesAndNewlines) + "\n\n" + additions
                updatedContent = updatedContent.replacingCharacters(in: range, with: updatedSection + "\n\n")
            } else {
                // Section doesn't exist - create it
                let newSection = "\n\n## \(section)\n\n" + sectionAugmentations.map { $0.suggestedAddition }.joined(separator: "\n\n")
                updatedContent += newSection
            }
        }

        return updatedContent
    }

    // MARK: - Private Methods

    private func extractPersonaSections(from markdown: String) -> [String: String] {
        var sections: [String: String] = [:]

        let pattern = "##\\s*([^\\n]+)\\n([\\s\\S]*?)(?=\\n##|\\z)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return sections
        }

        let nsString = markdown as NSString
        let matches = regex.matches(in: markdown, range: NSRange(location: 0, length: nsString.length))

        for match in matches {
            if match.numberOfRanges >= 3 {
                let titleRange = match.range(at: 1)
                let contentRange = match.range(at: 2)

                let title = nsString.substring(with: titleRange).trimmingCharacters(in: .whitespaces)
                let content = nsString.substring(with: contentRange).trimmingCharacters(in: .whitespacesAndNewlines)

                sections[title] = content
            }
        }

        return sections
    }

    private func buildAnalysisPrompt(characterName: String, personaSections: [String: String], sourceType: AugmentationSourceType) -> String {
        let sectionsDescription = personaSections.map { "- \($0.key): \($0.value.prefix(200))..." }.joined(separator: "\n")

        return """
        You are an expert at analyzing content to extract information relevant to building AI character personas.

        **Character:** \(characterName)

        **Current Persona Sections:**
        \(sectionsDescription.isEmpty ? "No existing sections" : sectionsDescription)

        **Source Type:** \(sourceType.displayName)

        ---

        ## Your Task

        Analyze the provided source content and identify information that should DIRECTLY augment the character's persona definition. You must distinguish between:

        ### 1. PERSONA AUGMENTATIONS (for direct persona updates)
        Information that defines WHO the character IS - their identity, personality, beliefs, relationships, speech patterns, mannerisms, etc. This goes into the persona markdown.

        Examples of persona-worthy content:
        - Personality traits revealed ("I'm actually really shy in person")
        - Core beliefs and values ("I believe hard work beats talent")
        - Relationship dynamics ("My mom is my biggest supporter")
        - Speech patterns and catchphrases
        - Emotional tendencies ("I cry when I'm proud, not sad")
        - Self-perception and identity
        - Behavioral patterns and habits
        - Fears, insecurities, motivations

        ### 2. KNOWLEDGE ENTRIES (for RAG storage)
        Factual information, events, opinions on topics, or details that are ABOUT the character but don't define who they are. This goes into the knowledge base for retrieval.

        Examples of knowledge-worthy content:
        - Specific events or stories ("In 2019, I performed at Madison Square Garden")
        - Opinions on external topics ("I think social media can be toxic")
        - Facts about their career, achievements, projects
        - Detailed descriptions of past experiences
        - Technical information about their work
        - Current events or news about them

        ---

        ## Output Format

        Return a JSON object with this exact structure:

        ```json
        {
          "source_summary": "Brief 1-2 sentence summary of the source content",
          "persona_augmentations": [
            {
              "section": "Section name (e.g., 'Personality & Traits', 'Speech Patterns', 'Relationships')",
              "suggested_addition": "The text to add to the persona (written in third person about \(characterName))",
              "rationale": "Why this belongs in the persona definition",
              "confidence": 0.85,
              "source_excerpt": "The relevant quote or excerpt from the source"
            }
          ],
          "knowledge_entries": [
            {
              "id": "snake_case_id",
              "section": "Topic or category",
              "content": "The knowledge entry written in third person about \(characterName)",
              "keywords": ["keyword1", "keyword2"]
            }
          ]
        }
        ```

        ## Critical Guidelines

        1. **Be selective** - Only include information that adds NEW value. Don't duplicate what's already in the persona.
        2. **Write in third person** - "\(characterName) is..." not "I am..."
        3. **Maintain authenticity** - Only include information actually supported by the source.
        4. **High confidence threshold** - Only suggest persona augmentations you're confident about (>0.7).
        5. **Appropriate categorization** - Factual/event-based content goes to knowledge, identity/personality content goes to persona.
        6. **Section matching** - Try to match existing section names when possible, or suggest appropriate new sections.

        Common persona sections include:
        - Identity & Origins
        - Personality & Traits
        - Values & Beliefs
        - Speech Patterns & Communication
        - Relationships & Social Dynamics
        - Emotional Landscape
        - Fears & Insecurities
        - Motivations & Goals
        - Mannerisms & Habits
        - Self-Perception

        Now analyze the source content and provide your structured response:
        """
    }

    private func callOpenAI(systemPrompt: String, userContent: String) async throws -> String {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(openAIApiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userContent]
            ],
            "max_tokens": 8000,
            "response_format": ["type": "json_object"]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AugmentationError.networkError
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AugmentationError.apiError("OpenAI error: \(errorBody)")
        }

        struct ChatResponse: Decodable {
            let choices: [Choice]
            struct Choice: Decodable {
                let message: Message
            }
            struct Message: Decodable {
                let content: String
            }
        }

        let chatResponse = try JSONDecoder().decode(ChatResponse.self, from: data)
        return chatResponse.choices.first?.message.content ?? ""
    }

    private func parseAnalysisResponse(
        response: String,
        sourceType: AugmentationSourceType,
        sourceTitle: String
    ) throws -> AugmentationAnalysisResult {
        guard let jsonData = response.data(using: .utf8) else {
            throw AugmentationError.parseError("Failed to encode response as data")
        }

        struct AnalysisResponse: Decodable {
            let source_summary: String
            let persona_augmentations: [PersonaAugmentationDTO]
            let knowledge_entries: [KnowledgeEntryDTO]

            struct PersonaAugmentationDTO: Decodable {
                let section: String
                let suggested_addition: String
                let rationale: String
                let confidence: Double
                let source_excerpt: String
            }

            struct KnowledgeEntryDTO: Decodable {
                let id: String
                let section: String
                let content: String
                let keywords: [String]
            }
        }

        let parsed = try JSONDecoder().decode(AnalysisResponse.self, from: jsonData)

        let augmentations = parsed.persona_augmentations.map { dto in
            PersonaAugmentation(
                section: dto.section,
                currentContent: nil,
                suggestedAddition: dto.suggested_addition,
                rationale: dto.rationale,
                confidence: dto.confidence,
                sourceExcerpt: dto.source_excerpt,
                isSelected: dto.confidence >= 0.7  // Auto-select high confidence items
            )
        }

        let ragEntries = parsed.knowledge_entries.map { dto in
            AugmentationKnowledgeEntry(
                id: dto.id,
                section: dto.section,
                content: dto.content,
                keywords: dto.keywords
            )
        }

        return AugmentationAnalysisResult(
            sourceType: sourceType,
            sourceTitle: sourceTitle,
            sourceSummary: parsed.source_summary,
            augmentations: augmentations,
            ragEntries: ragEntries,
            processedAt: Date()
        )
    }

    private func extractTextFromHTML(_ html: String) -> String {
        // Remove script and style tags
        var text = html
        text = text.replacingOccurrences(of: "<script[^>]*>[\\s\\S]*?</script>", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "<style[^>]*>[\\s\\S]*?</style>", with: "", options: .regularExpression)

        // Remove HTML tags
        text = text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)

        // Decode HTML entities
        text = text.replacingOccurrences(of: "&nbsp;", with: " ")
        text = text.replacingOccurrences(of: "&amp;", with: "&")
        text = text.replacingOccurrences(of: "&lt;", with: "<")
        text = text.replacingOccurrences(of: "&gt;", with: ">")
        text = text.replacingOccurrences(of: "&quot;", with: "\"")

        // Normalize whitespace
        text = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func extractTitleFromHTML(_ html: String) -> String? {
        let pattern = "<title[^>]*>([^<]+)</title>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              match.numberOfRanges > 1 else {
            return nil
        }

        let range = Range(match.range(at: 1), in: html)!
        return String(html[range]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Errors

enum AugmentationError: LocalizedError {
    case missingAPIKey(String)
    case invalidURL
    case fetchFailed(String)
    case networkError
    case apiError(String)
    case parseError(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey(let key):
            return "Missing API key: \(key)"
        case .invalidURL:
            return "Invalid URL provided"
        case .fetchFailed(let reason):
            return "Failed to fetch content: \(reason)"
        case .networkError:
            return "Network error occurred"
        case .apiError(let message):
            return message
        case .parseError(let reason):
            return "Failed to parse response: \(reason)"
        }
    }
}
