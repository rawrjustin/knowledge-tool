import Foundation

/// Service for generating dialog examples for AI characters
/// Orchestrates research, transcript extraction, and synthetic generation
actor DialogExampleService {
    private let openAIApiKey: String
    private let perplexityApiKey: String?
    private let model = "gpt-5"

    init(openAIApiKey: String, perplexityApiKey: String? = nil) {
        self.openAIApiKey = openAIApiKey
        self.perplexityApiKey = perplexityApiKey
    }

    // MARK: - Main Orchestration

    /// Generate dialog examples using the full pipeline:
    /// 1. Research real quotes (for real people)
    /// 2. Extract from transcripts (if available)
    /// 3. Generate synthetic to fill gaps
    func generateDialogExamples(
        characterName: String,
        personaContent: String,
        knowledgeFiles: [KnowledgeFile],
        config: DialogGenerationConfig,
        onProgress: @escaping @Sendable (String) -> Void
    ) async throws -> [DialogExample] {
        var allExamples: [DialogExample] = []
        let selectedCategories = DialogCategories.categories(for: config.selectedCategoryIds)

        // Step 1: Research real quotes if enabled and we have Perplexity key
        if config.researchQuotes, let _ = perplexityApiKey {
            onProgress("Researching real quotes for \(characterName)...")
            do {
                let researched = try await researchRealQuotes(
                    characterName: characterName,
                    personaContent: personaContent,
                    categories: selectedCategories,
                    onProgress: onProgress
                )
                allExamples.append(contentsOf: researched)
                onProgress("Found \(researched.count) real quotes")
            } catch {
                onProgress("Research skipped: \(error.localizedDescription)")
            }
        }

        // Step 2: Extract from transcripts if enabled
        if config.useTranscripts {
            let transcriptFiles = knowledgeFiles.filter { file in
                file.fileName.contains("transcript") || file.fileName.hasSuffix("_transcript.txt")
            }

            if !transcriptFiles.isEmpty {
                onProgress("Extracting examples from \(transcriptFiles.count) transcripts...")
                do {
                    let extracted = try await extractFromTranscripts(
                        characterName: characterName,
                        transcripts: transcriptFiles,
                        categories: selectedCategories,
                        onProgress: onProgress
                    )
                    allExamples.append(contentsOf: extracted)
                    onProgress("Extracted \(extracted.count) examples from transcripts")
                } catch {
                    onProgress("Transcript extraction skipped: \(error.localizedDescription)")
                }
            }
        }

        // Step 3: Generate synthetic to fill gaps
        onProgress("Generating synthetic examples...")
        let synthetic = try await generateSynthetic(
            characterName: characterName,
            personaContent: personaContent,
            existingExamples: allExamples,
            categories: selectedCategories,
            config: config,
            onProgress: onProgress
        )
        allExamples.append(contentsOf: synthetic)

        onProgress("Generated \(allExamples.count) total dialog examples")
        return allExamples
    }

    // MARK: - Research Real Quotes

    /// Research real quotes using Perplexity API
    func researchRealQuotes(
        characterName: String,
        personaContent: String,
        categories: [DialogCategory],
        onProgress: @escaping @Sendable (String) -> Void
    ) async throws -> [DialogExample] {
        guard let apiKey = perplexityApiKey else {
            throw DialogExampleError.missingAPIKey("Perplexity")
        }

        let categoryDescriptions = categories.map { "\($0.name): \($0.description)" }.joined(separator: "\n")

        let query = """
        Find actual quotes from \(characterName) that demonstrate how they speak in different situations.
        Look for quotes from interviews, social media, public appearances, and documented conversations.

        Categories I need quotes for:
        \(categoryDescriptions)

        For each quote found, indicate which category it best fits.
        Only include verified, real quotes with their source if possible.
        Format each quote clearly with the category it belongs to.
        """

        var request = URLRequest(url: URL(string: "https://api.perplexity.ai/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120

        let body: [String: Any] = [
            "model": "sonar-pro",
            "messages": [
                ["role": "system", "content": "You are a research assistant finding real quotes from public figures. Only include verified quotes."],
                ["role": "user", "content": query]
            ],
            "temperature": 0.3,
            "max_completion_tokens": 4000
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw DialogExampleError.apiError("Perplexity error: \(errorBody)")
        }

        // Parse response and extract quotes
        let perplexityResponse = try JSONDecoder().decode(PerplexityQuoteResponse.self, from: data)
        let content = perplexityResponse.choices.first?.message.content ?? ""

        return parseResearchedQuotes(content: content, categories: categories)
    }

    /// Parse Perplexity research response into dialog examples
    private func parseResearchedQuotes(content: String, categories: [DialogCategory]) -> [DialogExample] {
        var examples: [DialogExample] = []

        // Use OpenAI to structure the raw research into proper examples
        // For now, do simple parsing - look for quoted text and category mentions
        let lines = content.components(separatedBy: .newlines)
        var currentCategory: DialogCategory?

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Check if line mentions a category
            for category in categories {
                if trimmed.lowercased().contains(category.name.lowercased()) ||
                   trimmed.lowercased().contains(category.id.lowercased()) {
                    currentCategory = category
                    break
                }
            }

            // Look for quoted text
            if let range = trimmed.range(of: "\"[^\"]+\"", options: .regularExpression) {
                let quote = String(trimmed[range]).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                if !quote.isEmpty, let category = currentCategory ?? categories.first {
                    let example = DialogExample(
                        categoryId: category.id,
                        scenario: "Real quote",
                        dialog: quote,
                        source: .researched,
                        keywords: extractKeywords(from: quote)
                    )
                    examples.append(example)
                }
            }
        }

        return examples
    }

    // MARK: - Extract from Speaker Utterances

    /// Extract authentic dialogue from speaker utterances with animation markers
    /// - Parameters:
    ///   - speakerUtterances: Array of diarized speaker utterances
    ///   - speakerName: Name of the primary speaker to filter (auto-filters to this speaker only)
    ///   - sourceId: The source ID for traceability
    ///   - categories: Dialog categories to classify into
    ///   - includeAnimationMarkers: Whether to detect and include animation markers
    ///   - onProgress: Progress callback
    /// - Returns: Array of dialog examples with source attribution and animation markers
    func extractFromTranscriptUtterances(
        speakerUtterances: [SpeakerUtterance],
        speakerName: String,
        sourceId: UUID,
        categories: [DialogCategory],
        includeAnimationMarkers: Bool = true,
        onProgress: @escaping @Sendable (String) -> Void
    ) async throws -> [DialogExample] {
        // Filter to primary speaker only
        let speakerUtteranceTexts = speakerUtterances.filter { utterance in
            utterance.speaker.lowercased().contains(speakerName.lowercased()) ||
            speakerName.lowercased().contains(utterance.speaker.lowercased())
        }

        guard !speakerUtteranceTexts.isEmpty else {
            onProgress("No utterances found for speaker: \(speakerName)")
            return []
        }

        onProgress("Found \(speakerUtteranceTexts.count) utterances from \(speakerName)")

        // Combine utterances into chunks for processing
        let combinedText = speakerUtteranceTexts.map { utterance in
            "[\(formatTimestamp(utterance.start))] \(utterance.text)"
        }.joined(separator: "\n\n")

        let categoryList = categories.map { "- \($0.id): \($0.name) - \($0.description)" }.joined(separator: "\n")

        let animationSection = includeAnimationMarkers ? """

        ANIMATION MARKERS:
        Also detect opportunities for animation/expression markers. For each quote, if there are natural places for:
        - laugh, smile, pause, emphasis, gesture, nod, shrug, sigh, think, surprise, wink
        Include them in the animationMarkers array with position (character index) and marker type.

        EMOTION DETECTION:
        Classify the emotional tone of each quote from: happy, sad, angry, surprised, confident, nervous, playful, serious, excited, calm, frustrated, curious, nostalgic, determined, vulnerable
        Also rate intensity from 0.0 to 1.0.
        """ : ""

        let prompt = """
        You are extracting authentic dialog examples from a transcript where \(speakerName) is speaking.

        Extract the most characteristic, memorable quotes that capture \(speakerName)'s voice and personality.

        Categories to classify into:
        \(categoryList)
        \(animationSection)

        For each quote found, output as JSON:
        {
          "categoryId": "<category_id>",
          "dialog": "<the exact quote, cleaned up but preserving voice>",
          "keywords": ["keyword1", "keyword2"],
          "timestamp": <timestamp_in_seconds>,
          "emotion": "<emotion_tag or null>",
          "intensity": <0.0-1.0 or null>,
          "animationMarkers": [
            {"position": <char_index>, "marker": "<marker_type>", "duration": <seconds_or_null>}
          ]
        }

        Rules:
        - Only extract authentic quotes from \(speakerName)
        - Keep quotes short (1-3 sentences)
        - Preserve the character's exact voice, speech patterns, and mannerisms
        - Include 3-5 relevant keywords for RAG retrieval
        - Extract timestamp from the [HH:MM:SS] prefix

        Output a JSON object with "examples" array. If no suitable quotes found, output {"examples": []}.
        """

        // Truncate if too long
        let maxLength = 15000
        let truncatedContent = combinedText.count > maxLength
            ? String(combinedText.prefix(maxLength)) + "\n...[truncated]"
            : combinedText

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(openAIApiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": prompt],
                ["role": "user", "content": truncatedContent]
            ],
            "max_completion_tokens": 6000,
            "response_format": ["type": "json_object"]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        onProgress("Analyzing transcript for dialog examples...")
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw DialogExampleError.apiError("OpenAI error: \(errorBody)")
        }

        let chatResponse = try JSONDecoder().decode(OpenAIChatResponse.self, from: data)
        let jsonContent = chatResponse.choices.first?.message.content ?? "{}"

        return parseUtteranceExamples(jsonContent: jsonContent, sourceId: sourceId)
    }

    /// Parse examples extracted from utterances
    private func parseUtteranceExamples(jsonContent: String, sourceId: UUID) -> [DialogExample] {
        guard let data = jsonContent.data(using: .utf8) else { return [] }

        struct UtteranceExamplesWrapper: Decodable {
            let examples: [UtteranceExample]

            struct UtteranceExample: Decodable {
                let categoryId: String
                let dialog: String
                let keywords: [String]?
                let timestamp: Double?
                let emotion: String?
                let intensity: Double?
                let animationMarkers: [AnimationMarkerDTO]?

                struct AnimationMarkerDTO: Decodable {
                    let position: Int
                    let marker: String
                    let duration: Double?
                }
            }
        }

        guard let wrapper = try? JSONDecoder().decode(UtteranceExamplesWrapper.self, from: data) else {
            return []
        }

        return wrapper.examples.map { example in
            let markers = (example.animationMarkers ?? []).compactMap { dto -> AnimationMarker? in
                guard let markerType = AnimationMarkerType(rawValue: dto.marker.lowercased()) else {
                    return nil
                }
                return AnimationMarker(
                    position: dto.position,
                    marker: markerType,
                    duration: dto.duration
                )
            }

            let emotion = example.emotion.flatMap { EmotionTag(rawValue: $0.lowercased()) }

            return DialogExample(
                categoryId: example.categoryId,
                dialog: example.dialog,
                source: .transcript,
                keywords: example.keywords ?? [],
                sourceId: sourceId,
                sourceTimestamp: example.timestamp,
                animationMarkers: markers,
                emotion: emotion,
                intensity: example.intensity
            )
        }
    }

    private func formatTimestamp(_ seconds: TimeInterval) -> String {
        let totalSeconds = Int(seconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }

    // MARK: - Extract from Transcripts

    /// Extract dialog examples from video transcripts
    func extractFromTranscripts(
        characterName: String,
        transcripts: [KnowledgeFile],
        categories: [DialogCategory],
        onProgress: @escaping @Sendable (String) -> Void
    ) async throws -> [DialogExample] {
        var allExamples: [DialogExample] = []

        for transcript in transcripts {
            onProgress("Processing transcript: \(transcript.displayName)")

            let examples = try await extractFromSingleTranscript(
                characterName: characterName,
                content: transcript.content,
                categories: categories
            )
            allExamples.append(contentsOf: examples)
        }

        return allExamples
    }

    /// Extract from a single transcript using OpenAI
    private func extractFromSingleTranscript(
        characterName: String,
        content: String,
        categories: [DialogCategory]
    ) async throws -> [DialogExample] {
        let categoryList = categories.map { "- \($0.id): \($0.name) - \($0.description)" }.joined(separator: "\n")

        let prompt = """
        You are extracting dialog examples from a transcript featuring \(characterName).

        Find quotes that demonstrate how \(characterName) speaks in these situations:
        \(categoryList)

        For each quote found, output as JSON:
        {
          "categoryId": "<category_id>",
          "dialog": "<the exact quote>",
          "keywords": ["keyword1", "keyword2"]
        }

        Rules:
        - Only extract quotes actually spoken by \(characterName)
        - Keep quotes short (1-3 sentences)
        - Preserve the character's voice exactly
        - Include 3-5 relevant keywords

        Output a JSON array of quotes. If no suitable quotes found, output empty array [].
        """

        // Truncate content if too long
        let maxContentLength = 12000
        let truncatedContent = content.count > maxContentLength
            ? String(content.prefix(maxContentLength)) + "..."
            : content

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(openAIApiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": prompt],
                ["role": "user", "content": truncatedContent]
            ],
            "max_completion_tokens": 4000,
            "response_format": ["type": "json_object"]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw DialogExampleError.apiError("OpenAI error: \(errorBody)")
        }

        let chatResponse = try JSONDecoder().decode(OpenAIChatResponse.self, from: data)
        let jsonContent = chatResponse.choices.first?.message.content ?? "[]"

        return parseExtractedExamples(jsonContent: jsonContent, source: .transcript)
    }

    // MARK: - Generate Synthetic

    /// Generate synthetic dialog examples to fill gaps
    func generateSynthetic(
        characterName: String,
        personaContent: String,
        existingExamples: [DialogExample],
        categories: [DialogCategory],
        config: DialogGenerationConfig,
        onProgress: @escaping @Sendable (String) -> Void
    ) async throws -> [DialogExample] {
        var allSynthetic: [DialogExample] = []

        // Calculate how many examples we need per category
        let existingByCategory = Dictionary(grouping: existingExamples) { $0.categoryId }

        for category in categories {
            let existing = existingByCategory[category.id]?.count ?? 0
            let needed = max(0, category.suggestedCount - existing)

            if needed > 0 {
                onProgress("Generating \(needed) examples for \(category.name)...")

                let examples = try await generateForCategory(
                    characterName: characterName,
                    personaContent: personaContent,
                    category: category,
                    existingExamples: existingByCategory[category.id] ?? [],
                    count: needed,
                    config: config
                )
                allSynthetic.append(contentsOf: examples)
            }
        }

        return allSynthetic
    }

    /// Generate examples for a specific category
    private func generateForCategory(
        characterName: String,
        personaContent: String,
        category: DialogCategory,
        existingExamples: [DialogExample],
        count: Int,
        config: DialogGenerationConfig
    ) async throws -> [DialogExample] {
        let existingDialogs = existingExamples.map { "- \"\($0.dialog)\"" }.joined(separator: "\n")

        var contextSection = ""
        if !existingDialogs.isEmpty {
            contextSection = """

            EXISTING VOICE SAMPLES (use these to match the character's speech patterns):
            \(existingDialogs)
            """
        }

        var styleSection = ""
        if !config.toneGuidance.isEmpty || !config.styleNotes.isEmpty {
            styleSection = """

            ADDITIONAL STYLE GUIDANCE:
            \(config.toneGuidance.isEmpty ? "" : "Tone: \(config.toneGuidance)")
            \(config.styleNotes.isEmpty ? "" : "Style: \(config.styleNotes)")
            """
        }

        let prompt = """
        You are generating dialog examples for an AI character named \(characterName).

        CHARACTER PERSONA:
        \(personaContent.prefix(6000))
        \(contextSection)
        \(styleSection)

        CATEGORY: \(category.name)
        DESCRIPTION: \(category.description)
        GUIDANCE: \(category.contextPrompt)

        Generate \(count) dialog examples for this category. Each should:
        1. Sound authentically like \(characterName) - match their vocabulary, sentence structure, and personality
        2. Be 1-3 sentences (short and punchy)
        3. Be standalone dialog (not requiring context to understand)
        4. Capture the character's unique voice and mannerisms

        Output as JSON array:
        {
          "examples": [
            {
              "dialog": "The dialog line here.",
              "keywords": ["keyword1", "keyword2", "keyword3"]
            }
          ]
        }
        """

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(openAIApiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": "You are an expert at capturing character voices and generating authentic dialog."],
                ["role": "user", "content": prompt]
            ],
            "max_completion_tokens": 2000,
            "temperature": 0.8,
            "response_format": ["type": "json_object"]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw DialogExampleError.apiError("OpenAI error: \(errorBody)")
        }

        let chatResponse = try JSONDecoder().decode(OpenAIChatResponse.self, from: data)
        let jsonContent = chatResponse.choices.first?.message.content ?? "{}"

        return parseSyntheticExamples(jsonContent: jsonContent, categoryId: category.id)
    }

    // MARK: - Regenerate Single Example

    /// Regenerate a single dialog example
    func regenerateExample(
        example: DialogExample,
        characterName: String,
        personaContent: String
    ) async throws -> DialogExample {
        guard let category = DialogCategories.category(for: example.categoryId) else {
            throw DialogExampleError.invalidCategory(example.categoryId)
        }

        let prompt = """
        You are generating a dialog example for an AI character named \(characterName).

        CHARACTER PERSONA:
        \(personaContent.prefix(4000))

        CATEGORY: \(category.name)
        DESCRIPTION: \(category.description)

        Generate ONE new dialog example that:
        1. Sounds authentically like \(characterName)
        2. Is 1-3 sentences
        3. Is standalone (doesn't require context)
        4. Different from: "\(example.dialog)"

        Output as JSON:
        {
          "dialog": "The new dialog line.",
          "keywords": ["keyword1", "keyword2"]
        }
        """

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(openAIApiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "user", "content": prompt]
            ],
            "max_completion_tokens": 500,
            "temperature": 0.9,
            "response_format": ["type": "json_object"]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw DialogExampleError.apiError("Failed to regenerate example")
        }

        let chatResponse = try JSONDecoder().decode(OpenAIChatResponse.self, from: data)
        let jsonContent = chatResponse.choices.first?.message.content ?? "{}"

        guard let jsonData = jsonContent.data(using: .utf8),
              let parsed = try? JSONDecoder().decode(SingleExampleResponse.self, from: jsonData) else {
            throw DialogExampleError.parseError("Failed to parse regenerated example")
        }

        return DialogExample(
            categoryId: example.categoryId,
            scenario: example.scenario,
            dialog: parsed.dialog,
            source: .generated,
            keywords: parsed.keywords ?? extractKeywords(from: parsed.dialog)
        )
    }

    // MARK: - JSONL Conversion

    /// Convert dialog examples to JSONL format for storage
    func examplesToJSONL(_ examples: [DialogExample]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = []
        encoder.dateEncodingStrategy = .iso8601

        return examples.compactMap { example -> String? in
            guard let data = try? encoder.encode(example),
                  let json = String(data: data, encoding: .utf8) else {
                return nil
            }
            return json
        }.joined(separator: "\n")
    }

    /// Parse JSONL content into dialog examples
    func parseJSONL(_ content: String) -> [DialogExample] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return content.components(separatedBy: .newlines).compactMap { line -> DialogExample? in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty,
                  let data = trimmed.data(using: .utf8) else {
                return nil
            }
            return try? decoder.decode(DialogExample.self, from: data)
        }
    }

    // MARK: - Private Helpers

    private func parseExtractedExamples(jsonContent: String, source: DialogSource) -> [DialogExample] {
        // Clean markdown code blocks if present
        var cleaned = jsonContent
        if cleaned.hasPrefix("```") {
            let lines = cleaned.components(separatedBy: "\n")
            cleaned = lines.dropFirst().dropLast().joined(separator: "\n")
        }

        guard let data = cleaned.data(using: .utf8) else { return [] }

        // Try parsing as array first
        if let array = try? JSONDecoder().decode([ExtractedExample].self, from: data) {
            return array.map { extracted in
                DialogExample(
                    categoryId: extracted.categoryId,
                    dialog: extracted.dialog,
                    source: source,
                    keywords: extracted.keywords ?? []
                )
            }
        }

        // Try parsing as object with examples array
        if let wrapper = try? JSONDecoder().decode(ExtractedExamplesWrapper.self, from: data) {
            return wrapper.examples.map { extracted in
                DialogExample(
                    categoryId: extracted.categoryId,
                    dialog: extracted.dialog,
                    source: source,
                    keywords: extracted.keywords ?? []
                )
            }
        }

        return []
    }

    private func parseSyntheticExamples(jsonContent: String, categoryId: String) -> [DialogExample] {
        guard let data = jsonContent.data(using: .utf8),
              let wrapper = try? JSONDecoder().decode(SyntheticExamplesWrapper.self, from: data) else {
            return []
        }

        return wrapper.examples.map { synthetic in
            DialogExample(
                categoryId: categoryId,
                dialog: synthetic.dialog,
                source: .generated,
                keywords: synthetic.keywords ?? extractKeywords(from: synthetic.dialog)
            )
        }
    }

    private func extractKeywords(from text: String) -> [String] {
        // Simple keyword extraction - split on spaces and filter
        let words = text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 3 }

        // Return unique words, max 5
        return Array(Set(words).prefix(5))
    }

    // MARK: - Response Models

    private struct PerplexityQuoteResponse: Codable {
        let choices: [Choice]
        struct Choice: Codable {
            let message: Message
        }
        struct Message: Codable {
            let content: String
        }
    }

    private struct OpenAIChatResponse: Codable {
        let choices: [Choice]
        struct Choice: Codable {
            let message: Message
        }
        struct Message: Codable {
            let content: String
        }
    }

    private struct ExtractedExample: Codable {
        let categoryId: String
        let dialog: String
        let keywords: [String]?
    }

    private struct ExtractedExamplesWrapper: Codable {
        let examples: [ExtractedExample]
    }

    private struct SyntheticExample: Codable {
        let dialog: String
        let keywords: [String]?
    }

    private struct SyntheticExamplesWrapper: Codable {
        let examples: [SyntheticExample]
    }

    private struct SingleExampleResponse: Codable {
        let dialog: String
        let keywords: [String]?
    }
}

// MARK: - Errors

enum DialogExampleError: LocalizedError {
    case missingAPIKey(String)
    case apiError(String)
    case parseError(String)
    case invalidCategory(String)
    case noExamplesGenerated

    var errorDescription: String? {
        switch self {
        case .missingAPIKey(let service):
            return "Missing API key for \(service)"
        case .apiError(let message):
            return message
        case .parseError(let message):
            return "Parse error: \(message)"
        case .invalidCategory(let id):
            return "Invalid category: \(id)"
        case .noExamplesGenerated:
            return "No dialog examples were generated"
        }
    }
}
