import Foundation
import PDFKit

@MainActor
@Observable
final class CharacterCreationViewModel {
    // Wizard state
    enum Step {
        case pathSelection
        case unifiedInput
        case unifiedProcessing
        case wikipediaInput
        case wikipediaPreview
        case originalInput
        case youtubeInput
        case youtubeProcessing
        case generating
        case review
    }

    enum CreationPath {
        case wikipedia
        case original
        case youtube
        case unified
    }

    // MARK: - Scraped Source Types

    struct ScrapedSource: Identifiable {
        let id = UUID()
        let type: SourceType
        let title: String
        let url: String?
        let content: String

        enum SourceType: String {
            case wikipedia
            case youtube
            case webArticle
            case pdf
            case description
        }
    }

    enum UnifiedSourceStatus: Identifiable {
        case pending(id: String, label: String)
        case processing(id: String, label: String)
        case completed(id: String, label: String)
        case failed(id: String, label: String, error: String)

        var id: String {
            switch self {
            case .pending(let id, _), .processing(let id, _),
                 .completed(let id, _), .failed(let id, _, _):
                return id
            }
        }

        var label: String {
            switch self {
            case .pending(_, let label), .processing(_, let label),
                 .completed(_, let label), .failed(_, let label, _):
                return label
            }
        }

        var isComplete: Bool {
            if case .completed = self { return true }
            return false
        }

        var isFailed: Bool {
            if case .failed = self { return true }
            return false
        }
    }

    private(set) var currentStep: Step = .unifiedInput
    private(set) var selectedPath: CreationPath? = .unified
    var systemPromptType: SystemPromptType = .action

    // Input state
    var wikipediaURL: String = ""
    var originalDescription: String = ""

    // Unified input state
    var unifiedCharacterName: String = ""
    var unifiedDescription: String = ""
    var webLinks: [String] = [""]
    var pdfFiles: [URL] = []
    private(set) var scrapedContent: [ScrapedSource] = []
    private(set) var unifiedSourceStatuses: [UnifiedSourceStatus] = []

    // YouTube input state
    var youtubeURLs: [String] = [""]  // Start with one empty field
    var youtubeCharacterName: String = ""  // Optional override for character name

    // YouTube processing state
    private(set) var youtubeProcessingStatus: [Int: YouTubeVideoStatus] = [:]  // Index -> status
    private(set) var processedTranscripts: [ProcessedTranscript] = []
    private(set) var combinedDialogueExamples: [SpeakerDialogueExamples] = []
    private(set) var detectedCharacterName: String?

    // Preview state
    private(set) var previewCharacterName: String?
    private(set) var previewSnippet: String?
    private(set) var wikipediaContent: String?

    // Generation state
    private(set) var progressLogs: [String] = []
    private(set) var generatedContent: String = ""
    private(set) var sources: [String] = []

    // Artifacts to save with character
    private(set) var knowledgeArtifacts: [KnowledgeArtifact] = []

    // Result
    private(set) var savedCharacter: Character?

    // Error state
    var error: String? {
        didSet {
            if let error = error {
                print("[KnowledgeTool] Error set to: '\(error)'")
            } else {
                print("[KnowledgeTool] Error cleared")
            }
        }
    }

    // Services
    private let repository: CombinedCharacterRepository
    private let apiKeyManager: APIKeyManager
    private let asp1Template: String

    // Computed property to get OpenAI service with current API key
    private var openAIService: OpenAIService? {
        guard let apiKey = apiKeyManager.getAPIKey(for: .openAI) else { return nil }
        return OpenAIService(apiKey: apiKey)
    }

    // Computed property to get Perplexity service with current API key
    private var perplexityService: PerplexityService? {
        guard let apiKey = apiKeyManager.getAPIKey(for: .perplexity) else { return nil }
        return PerplexityService(apiKey: apiKey)
    }

    // MARK: - YouTube Supporting Types

    struct YouTubeVideoStatus: Identifiable {
        let id: Int
        var url: String
        var state: ProcessingState
        var videoTitle: String?
        var intervieweeName: String?

        enum ProcessingState: Equatable {
            case pending
            case downloading
            case transcribing
            case identifying
            case extractingDialogue
            case generatingKnowledge
            case completed
            case failed(String)

            var displayText: String {
                switch self {
                case .pending: return "Waiting..."
                case .downloading: return "Downloading video..."
                case .transcribing: return "Transcribing audio..."
                case .identifying: return "Identifying speaker..."
                case .extractingDialogue: return "Extracting dialogue..."
                case .generatingKnowledge: return "Generating knowledge base..."
                case .completed: return "Completed"
                case .failed(let error): return "Failed: \(error)"
                }
            }

            var isComplete: Bool {
                if case .completed = self { return true }
                return false
            }

            var isFailed: Bool {
                if case .failed = self { return true }
                return false
            }
        }
    }

    struct ProcessedTranscript {
        let url: String
        let title: String
        let transcript: Transcript
        let intervieweeName: String?
        let dialogueExamples: [SpeakerDialogueExamples]?
        let structuredKnowledgeBase: String
    }

    struct KnowledgeArtifact {
        let sourceId: UUID?     // nil = root level, otherwise goes in sources/{id}/
        let fileName: String
        let content: String
    }

    init(repository: CombinedCharacterRepository, apiKeyManager: APIKeyManager) {
        self.repository = repository
        self.apiKeyManager = apiKeyManager

        // Load ASP-1 template from bundled resource
        self.asp1Template = ASP1Template.content
    }

    // MARK: - Navigation

    func selectPath(_ path: CreationPath) {
        print("[KnowledgeTool] selectPath called: \(path)")
        selectedPath = path
        error = nil

        switch path {
        case .wikipedia:
            currentStep = .wikipediaInput
        case .original:
            currentStep = .originalInput
        case .youtube:
            currentStep = .youtubeInput
        case .unified:
            currentStep = .unifiedInput
        }
    }

    func goBack() {
        currentStep = .unifiedInput
        error = nil
    }

    func discard() {
        currentStep = .unifiedInput
        selectedPath = .unified
        wikipediaURL = ""
        originalDescription = ""
        systemPromptType = .action
        generatedContent = ""
        progressLogs = []
        error = nil
        // Reset unified state
        unifiedCharacterName = ""
        unifiedDescription = ""
        webLinks = [""]
        pdfFiles = []
        scrapedContent = []
        unifiedSourceStatuses = []
        // Reset YouTube state
        youtubeURLs = [""]
        youtubeCharacterName = ""
        youtubeProcessingStatus = [:]
        processedTranscripts = []
        combinedDialogueExamples = []
        detectedCharacterName = nil
        knowledgeArtifacts = []
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

            // Step 1: Research with Perplexity (optional - gracefully handle failures)
            var researchContent = ""
            var researchCitations: [String] = []

            if let perplexityService = perplexityService {
                addLog("Starting web research on \(characterName) with Perplexity...")
                addLog("This typically takes 30-60 seconds...")

                do {
                    let researchResult = try await perplexityService.research(
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
                        onProgress: { [weak self] message in
                            Task { @MainActor in
                                self?.addLog(message)
                            }
                        }
                    )

                    researchContent = researchResult.content
                    researchCitations = researchResult.citations
                    sources = researchResult.citations
                    addLog("Research complete with \(researchResult.citations.count) sources")
                    addLog("Research content: \(researchResult.content.count) characters")
                } catch {
                    addLog("⚠️ Web research failed: \(error.localizedDescription)")
                    addLog("Continuing with Wikipedia content only...")
                }
            } else {
                addLog("Perplexity API key not configured. Using Wikipedia content only...")
            }

            // Step 2: Generate character using OpenAI with available content
            let personaFormat = systemPromptType == .roleplay ? "RSP2" : "ASP1"
            addLog("Generating rich character profile using \(personaFormat) persona format...")

            let prompt: String
            if !researchContent.isEmpty {
                prompt = systemPromptType == .roleplay
                    ? buildResearchBasedPromptRSP2(
                        characterName: characterName,
                        research: researchContent,
                        citations: researchCitations
                    )
                    : buildResearchBasedPrompt(
                        characterName: characterName,
                        research: researchContent,
                        citations: researchCitations
                    )
            } else {
                // Fallback: use Wikipedia content directly
                let fallbackResearch = "Wikipedia content:\n\n\(wikiContent)"
                prompt = systemPromptType == .roleplay
                    ? buildResearchBasedPromptRSP2(
                        characterName: characterName,
                        research: fallbackResearch,
                        citations: [wikipediaURL]
                    )
                    : buildResearchBasedPrompt(
                        characterName: characterName,
                        research: fallbackResearch,
                        citations: [wikipediaURL]
                    )
            }

            generatedContent = try await openAIService.chat(messages: [
                ["role": "system", "content": "You are an expert interactive character designer. You write high-signal character bibles optimized for immersive roleplay and companion chat. Follow the output format exactly; no placeholders; keep it playable, specific, and emotionally engaging."],
                ["role": "user", "content": prompt]
            ], model: "gpt-5")

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
                // Research path for real people
                addLog("Detected real person. Starting web research with Perplexity...")
                addLog("This typically takes 30-60 seconds...")

                // Extract name from description
                let characterName = extractNameFromDescription(originalDescription) ?? "Character"

                do {
                    let researchResult = try await perplexityService.research(
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
                        onProgress: { [weak self] message in
                            Task { @MainActor in
                                self?.addLog(message)
                            }
                        }
                    )

                    sources = researchResult.citations
                    addLog("Research complete with \(researchResult.citations.count) sources")

                    // Generate with research
                    let personaFormat = systemPromptType == .roleplay ? "RSP2" : "ASP1"
                    addLog("Generating rich character profile using \(personaFormat) persona format...")

                    let prompt = systemPromptType == .roleplay
                        ? buildResearchBasedPromptRSP2(
                            characterName: characterName,
                            research: researchResult.content,
                            citations: researchResult.citations
                        )
                        : buildResearchBasedPrompt(
                            characterName: characterName,
                            research: researchResult.content,
                            citations: researchResult.citations
                        )

                    generatedContent = try await openAIService.chat(messages: [
                        ["role": "system", "content": "You are an expert interactive character designer. You write high-signal character bibles optimized for immersive roleplay and companion chat. Follow the output format exactly; no placeholders; keep it playable, specific, and emotionally engaging."],
                        ["role": "user", "content": prompt]
                    ], model: "gpt-5")
                } catch {
                    // Research failed - fall back to creative generation
                    addLog("⚠️ Web research failed: \(error.localizedDescription)")
                    addLog("Falling back to creative generation...")

                    let prompt = systemPromptType == .roleplay
                        ? buildOriginalPromptRSP2(description: originalDescription)
                        : buildOriginalPrompt(description: originalDescription)
                    generatedContent = try await openAIService.chat(messages: [
                        ["role": "system", "content": "You are an expert interactive character designer. You create original characters built for immersive roleplay and companion chat: clear hooks, tension, user relationship, and a strong conversation engine. Follow the output format exactly; no placeholders."],
                        ["role": "user", "content": prompt]
                    ], model: "gpt-5")
                }

            } else {
                // Creative generation path for fictional characters
                addLog("Creating original fictional character...")
                let personaFormat = systemPromptType == .roleplay ? "RSP2" : "ASP1"
                addLog("Generating character using \(personaFormat) persona format...")

                let prompt = systemPromptType == .roleplay
                    ? buildOriginalPromptRSP2(description: originalDescription)
                    : buildOriginalPrompt(description: originalDescription)
                generatedContent = try await openAIService.chat(messages: [
                    ["role": "system", "content": "You are an expert interactive character designer. You create original characters built for immersive roleplay and companion chat: clear hooks, tension, user relationship, and a strong conversation engine. Follow the output format exactly; no placeholders."],
                    ["role": "user", "content": prompt]
                ], model: "gpt-5")
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

    // MARK: - YouTube Processing

    /// Add a new YouTube URL field
    func addYouTubeURL() {
        youtubeURLs.append("")
    }

    /// Remove a YouTube URL field
    func removeYouTubeURL(at index: Int) {
        guard youtubeURLs.count > 1, index < youtubeURLs.count else { return }
        youtubeURLs.remove(at: index)
    }

    /// Validate YouTube URLs and start processing
    func processYouTubeVideos() async {
        print("[KnowledgeTool] processYouTubeVideos() called")

        // Filter out empty URLs
        let validURLs = youtubeURLs.enumerated().filter { !$0.element.trimmingCharacters(in: .whitespaces).isEmpty }
        print("[KnowledgeTool] Valid URLs count: \(validURLs.count)")

        guard !validURLs.isEmpty else {
            error = "Please enter at least one YouTube URL"
            return
        }

        // Validate API keys
        guard apiKeyManager.getAPIKey(for: .assemblyAI) != nil else {
            error = "AssemblyAI API key not configured. Please add it in Settings."
            return
        }

        guard apiKeyManager.getAPIKey(for: .openAI) != nil else {
            error = "OpenAI API key not configured. Please add it in Settings."
            return
        }

        print("[KnowledgeTool] API keys validated, starting processing...")
        error = nil
        currentStep = .youtubeProcessing
        processedTranscripts = []
        combinedDialogueExamples = []
        knowledgeArtifacts = []
        detectedCharacterName = nil
        progressLogs = []  // Clear logs for fresh start
        addLog("Starting video processing for \(validURLs.count) video(s)...")

        // Initialize status for all URLs
        for (index, url) in validURLs {
            youtubeProcessingStatus[index] = YouTubeVideoStatus(
                id: index,
                url: url,
                state: .pending,
                videoTitle: nil,
                intervieweeName: nil
            )
        }

        // Process videos in parallel using TaskGroup
        // Collect results and merge them on the main actor to avoid data races
        let results = await withTaskGroup(of: ProcessedTranscript?.self) { group -> [ProcessedTranscript] in
            for (index, url) in validURLs {
                group.addTask {
                    return await self.processYouTubeVideo(url: url, index: index)
                }
            }

            var collected: [ProcessedTranscript] = []
            for await result in group {
                if let transcript = result {
                    collected.append(transcript)
                }
            }
            return collected
        }

        // Now safely update on main actor
        processedTranscripts = results
        addLog("All videos processed. \(results.count) successful.")

        // Check if we have any successful transcripts
        let successfulTranscripts = processedTranscripts
        guard !successfulTranscripts.isEmpty else {
            // Collect all error messages from failed videos
            let failedErrors = youtubeProcessingStatus.values.compactMap { status -> String? in
                if case .failed(let errorMsg) = status.state {
                    return "Video \(status.id + 1): \(errorMsg)"
                }
                return nil
            }

            if !failedErrors.isEmpty {
                error = "All videos failed to process:\n\n" + failedErrors.joined(separator: "\n\n")
                // Log detailed errors
                print("[KnowledgeTool] All videos failed:")
                for err in failedErrors {
                    print("[KnowledgeTool] - \(err)")
                }
            } else {
                error = "No videos were successfully transcribed. If you're running this app for the first time, try running: xattr -cr /path/to/KnowledgeTool.app"
            }
            currentStep = .youtubeInput
            return
        }

        // Auto-detect character name from transcripts if not provided
        if youtubeCharacterName.trimmingCharacters(in: .whitespaces).isEmpty {
            // Use the most common interviewee name detected
            let names = successfulTranscripts.compactMap { $0.intervieweeName }
            if let mostCommon = names.max(by: { name1, name2 in
                names.filter { $0 == name1 }.count < names.filter { $0 == name2 }.count
            }) {
                detectedCharacterName = mostCommon
            }
        } else {
            detectedCharacterName = youtubeCharacterName
        }

        // Combine all dialogue examples
        for transcript in successfulTranscripts {
            if let examples = transcript.dialogueExamples {
                combinedDialogueExamples.append(contentsOf: examples)
            }
        }

        // Build knowledge artifacts
        buildKnowledgeArtifacts(from: successfulTranscripts)

        // Now generate the persona
        await generatePersonaFromTranscripts()
    }

    /// Process a single YouTube video
    private func processYouTubeVideo(url: String, index: Int) async -> ProcessedTranscript? {
        print("[KnowledgeTool] Processing video \(index + 1): \(url)")

        guard let assemblyAIKey = apiKeyManager.getAPIKey(for: .assemblyAI),
              let openAIKey = apiKeyManager.getAPIKey(for: .openAI) else {
            print("[KnowledgeTool] Missing API keys for video \(index + 1)")
            updateYouTubeStatus(index: index, state: .failed("Missing API keys"))
            return nil
        }

        let videoService = VideoService()
        let assemblyAI = AssemblyAIService(apiKey: assemblyAIKey)
        let openAI = OpenAIService(apiKey: openAIKey)

        var audioURL: URL?

        do {
            // Step 1: Download video
            print("[KnowledgeTool] Video \(index + 1): Starting download...")
            updateYouTubeStatus(index: index, state: .downloading)
            await MainActor.run { addLog("Downloading video \(index + 1)...") }
            let result = try await videoService.downloadAndExtractAudio(from: url)
            audioURL = result.audioURL
            let videoInfo = result.videoInfo

            updateYouTubeStatus(index: index, state: .downloading, videoTitle: videoInfo.title)
            await MainActor.run { addLog("Downloaded: \(videoInfo.title)") }

            // Step 2: Transcribe
            updateYouTubeStatus(index: index, state: .transcribing)
            await MainActor.run { addLog("Transcribing audio for video \(index + 1)...") }
            var transcript = try await assemblyAI.transcribeAudio(fileURL: audioURL!)
            await MainActor.run { addLog("Transcription complete for video \(index + 1)") }

            // Step 3: Identify interviewee
            updateYouTubeStatus(index: index, state: .identifying)
            await MainActor.run { addLog("Identifying speaker in video \(index + 1)...") }
            var intervieweeName: String? = nil

            if let speakerLabels = transcript.speakerLabels, !speakerLabels.isEmpty {
                let transcriptPreview = String(transcript.text.prefix(2000))
                if let identifiedName = try await openAI.identifyInterviewee(
                    title: videoInfo.title,
                    description: videoInfo.description,
                    transcriptPreview: transcriptPreview
                ) {
                    intervieweeName = identifiedName
                    // Relabel speakers
                    let relabeledSpeakerLabels = relabelSpeakers(
                        speakerLabels: speakerLabels,
                        intervieweeName: identifiedName
                    )
                    transcript = Transcript(
                        id: transcript.id,
                        text: transcript.text,
                        speakerLabels: relabeledSpeakerLabels,
                        createdAt: transcript.createdAt,
                        sourceURL: url,
                        title: videoInfo.title
                    )
                }
            }

            updateYouTubeStatus(index: index, state: .identifying, intervieweeName: intervieweeName)
            if let name = intervieweeName {
                await MainActor.run { addLog("Identified speaker: \(name)") }
            }

            // Step 4: Extract dialogue examples
            updateYouTubeStatus(index: index, state: .extractingDialogue)
            await MainActor.run { addLog("Extracting dialogue examples from video \(index + 1)...") }
            var dialogueExamples: [SpeakerDialogueExamples]? = nil

            if let speakerLabels = transcript.speakerLabels, !speakerLabels.isEmpty, let name = intervieweeName {
                let intervieweeUtterances = speakerLabels.filter { $0.speaker == name }
                if !intervieweeUtterances.isEmpty {
                    dialogueExamples = try await openAI.extractDialogueExamples(from: intervieweeUtterances)
                }
            }

            // Step 5: Generate structured knowledge base
            updateYouTubeStatus(index: index, state: .generatingKnowledge)
            await MainActor.run { addLog("Generating knowledge base for video \(index + 1)...") }
            let characterName = intervieweeName ?? "the subject"
            let knowledgeBase = try await openAI.generateStructuredKnowledgeBase(
                characterName: characterName,
                fullTranscript: transcript.text,
                speakerLabels: transcript.speakerLabels,
                videoURL: url,
                videoTitle: videoInfo.title
            )

            // Store processed transcript
            let processed = ProcessedTranscript(
                url: url,
                title: videoInfo.title,
                transcript: transcript,
                intervieweeName: intervieweeName,
                dialogueExamples: dialogueExamples,
                structuredKnowledgeBase: knowledgeBase
            )

            updateYouTubeStatus(index: index, state: .completed)
            await MainActor.run { addLog("Video \(index + 1) processing complete!") }

            // Cleanup
            if let audioURL = audioURL {
                await videoService.cleanup(audioURL: audioURL)
            }

            return processed

        } catch {
            // Cleanup on error
            if let audioURL = audioURL {
                await videoService.cleanup(audioURL: audioURL)
            }
            let errorMessage = error.localizedDescription
            updateYouTubeStatus(index: index, state: .failed(errorMessage))
            // Also log to console for debugging
            print("[KnowledgeTool] Video \(index + 1) failed: \(errorMessage)")
            return nil
        }
    }

    /// Update the status for a YouTube video
    private func updateYouTubeStatus(
        index: Int,
        state: YouTubeVideoStatus.ProcessingState,
        videoTitle: String? = nil,
        intervieweeName: String? = nil
    ) {
        guard var status = youtubeProcessingStatus[index] else { return }
        status.state = state
        if let title = videoTitle {
            status.videoTitle = title
        }
        if let name = intervieweeName {
            status.intervieweeName = name
        }
        youtubeProcessingStatus[index] = status
    }

    /// Relabel speakers in transcript
    private func relabelSpeakers(speakerLabels: [SpeakerUtterance], intervieweeName: String) -> [SpeakerUtterance] {
        var speakerTimes: [String: TimeInterval] = [:]
        for utterance in speakerLabels {
            let duration = utterance.end - utterance.start
            speakerTimes[utterance.speaker, default: 0] += duration
        }

        guard let primarySpeaker = speakerTimes.max(by: { $0.value < $1.value })?.key else {
            return speakerLabels
        }

        return speakerLabels.map { utterance in
            let newSpeaker = utterance.speaker == primarySpeaker ? intervieweeName : utterance.speaker
            return SpeakerUtterance(
                id: utterance.id,
                speaker: newSpeaker,
                text: utterance.text,
                start: utterance.start,
                end: utterance.end
            )
        }
    }

    /// Build knowledge artifacts from processed transcripts
    /// Uses new source-based folder structure (Knowledge/sources/{uuid}/)
    private func buildKnowledgeArtifacts(from transcripts: [ProcessedTranscript]) {
        knowledgeArtifacts = []

        // Create source folder for each video
        for transcript in transcripts {
            let sourceId = UUID()

            // Create metadata for this source
            let metadata = SourceMetadata(
                id: sourceId,
                type: "youtube",
                title: transcript.title,
                sourceUrl: transcript.url,
                processedAt: Date(),
                speaker: transcript.intervieweeName,
                files: SourceMetadata.Files(
                    transcript: "transcript.txt",
                    knowledge: transcript.structuredKnowledgeBase.isEmpty ? nil : "knowledge.jsonl"
                )
            )

            // Encode metadata to JSON
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            if let metadataData = try? encoder.encode(metadata),
               let metadataString = String(data: metadataData, encoding: .utf8) {
                knowledgeArtifacts.append(KnowledgeArtifact(
                    sourceId: sourceId,
                    fileName: "metadata.json",
                    content: metadataString
                ))
            }

            // Transcript file (goes into source folder)
            var transcriptContent = "# \(transcript.title)\n\n"
            transcriptContent += "Source: \(transcript.url)\n\n"

            if let speakerLabels = transcript.transcript.speakerLabels, !speakerLabels.isEmpty {
                for utterance in speakerLabels {
                    transcriptContent += "[\(formatTimestamp(utterance.start))] \(utterance.speaker): \(utterance.text)\n\n"
                }
            } else {
                transcriptContent += transcript.transcript.text + "\n\n"
            }
            knowledgeArtifacts.append(KnowledgeArtifact(
                sourceId: sourceId,
                fileName: "transcript.txt",
                content: transcriptContent
            ))

            // Structured knowledge file (goes into source folder)
            if !transcript.structuredKnowledgeBase.isEmpty {
                knowledgeArtifacts.append(KnowledgeArtifact(
                    sourceId: sourceId,
                    fileName: "knowledge.jsonl",
                    content: transcript.structuredKnowledgeBase
                ))
            }
        }

        // NO combined files - dynamic context building via TranscriptContextBuilder

        // Create dialogue examples artifact at root level (consolidated across sources)
        if !combinedDialogueExamples.isEmpty {
            var dialogueContent = ""
            for speakerExamples in combinedDialogueExamples {
                for example in speakerExamples.examples {
                    // Create JSONL entries for dialogue examples
                    let entry: [String: Any] = [
                        "id": "dialog-\(UUID().uuidString.prefix(8))",
                        "section": "Dialogue",
                        "speaker": speakerExamples.speaker,
                        "content": example,
                        "keywords": ["dialogue", "speech", speakerExamples.speaker.lowercased()]
                    ]
                    if let data = try? JSONSerialization.data(withJSONObject: entry),
                       let line = String(data: data, encoding: .utf8) {
                        dialogueContent += line + "\n"
                    }
                }
            }
            if !dialogueContent.isEmpty {
                knowledgeArtifacts.append(KnowledgeArtifact(
                    sourceId: nil,  // Root level
                    fileName: "dialog_examples.jsonl",
                    content: dialogueContent
                ))
            }
        }
    }

    /// Sanitize a string to be used as a filename
    private func sanitizeFileName(_ name: String) -> String {
        // Remove or replace characters that are problematic in filenames
        var sanitized = name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "*", with: "")
            .replacingOccurrences(of: "?", with: "")
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "<", with: "")
            .replacingOccurrences(of: ">", with: "")
            .replacingOccurrences(of: "|", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Limit length and remove trailing dots/spaces
        if sanitized.count > 50 {
            sanitized = String(sanitized.prefix(50))
        }
        sanitized = sanitized.trimmingCharacters(in: CharacterSet(charactersIn: ". "))

        return sanitized.isEmpty ? "untitled" : sanitized
    }

    private func formatTimestamp(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, secs)
    }

    /// Generate persona from transcripts
    private func generatePersonaFromTranscripts() async {
        guard let openAIService = openAIService else {
            error = "OpenAI API key not configured"
            currentStep = .youtubeInput
            return
        }

        guard !processedTranscripts.isEmpty else {
            error = "No transcripts to generate from"
            currentStep = .youtubeInput
            return
        }

        currentStep = .generating
        // Don't clear progressLogs - keep the video processing logs visible
        sources = processedTranscripts.map { $0.url }

        let characterName = detectedCharacterName ?? "Character"
        addLog("Generating persona for \(characterName) from \(processedTranscripts.count) video(s)...")

        do {
            // Combine transcript content for research
            var transcriptContent = ""
            for transcript in processedTranscripts {
                transcriptContent += "## Video: \(transcript.title)\n"
                transcriptContent += "Source: \(transcript.url)\n\n"
                transcriptContent += transcript.transcript.text.prefix(10000)  // Limit per video
                transcriptContent += "\n\n---\n\n"
            }

            // Combine dialogue examples
            var dialogueSection = ""
            if !combinedDialogueExamples.isEmpty {
                dialogueSection = "\n\nCHARACTERISTIC DIALOGUE AND SPEECH PATTERNS:\n"
                for speakerExamples in combinedDialogueExamples {
                    if speakerExamples.speaker == characterName {
                        for example in speakerExamples.examples {
                            dialogueSection += "- \"\(example)\"\n"
                        }
                    }
                }
            }

            // Do web research with Perplexity if available
            var additionalResearch = ""
            if let perplexityService = perplexityService {
                let researchQuery = """
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
                """

                do {
                    addLog("Starting web research on \(characterName)...")
                    addLog("This typically takes 30-60 seconds...")

                    let researchResult = try await perplexityService.research(
                        query: researchQuery,
                        onProgress: { [weak self] message in
                            Task { @MainActor in
                                self?.addLog(message)
                            }
                        }
                    )

                    additionalResearch = "\n\nADDITIONAL RESEARCH:\n\(researchResult.content)"
                    sources.append(contentsOf: researchResult.citations)
                    addLog("Research complete with \(researchResult.citations.count) sources")
                } catch {
                    // Research failed - log warning and continue without it
                    addLog("⚠️ Web research failed: \(error.localizedDescription)")
                    addLog("Continuing with transcript data only...")
                }
            } else {
                addLog("No Perplexity API key configured. Generating from transcripts only...")
            }

            let personaFormat = systemPromptType == .roleplay ? "RSP2" : "ASP1"
            addLog("Generating rich character profile using \(personaFormat) persona format...")

            let prompt = systemPromptType == .roleplay
                ? buildTranscriptBasedPromptRSP2(
                    characterName: characterName,
                    transcriptContent: transcriptContent,
                    dialogueExamples: dialogueSection,
                    additionalResearch: additionalResearch
                )
                : buildTranscriptBasedPrompt(
                    characterName: characterName,
                    transcriptContent: transcriptContent,
                    dialogueExamples: dialogueSection,
                    additionalResearch: additionalResearch
                )

            generatedContent = try await openAIService.chat(messages: [
                ["role": "system", "content": "You are an expert interactive character designer. You write high-signal character bibles optimized for immersive roleplay and companion chat. Use transcripts to capture authentic voice. Follow the output format exactly; no placeholders; keep it playable and specific."],
                ["role": "user", "content": prompt]
            ], model: "gpt-5")

            addLog("Character generated successfully!")
            addLog("Word count: \(generatedContent.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count)")

            currentStep = .review

        } catch {
            let errorMessage = "Failed to generate character: \(error.localizedDescription)"
            print("[KnowledgeTool] \(errorMessage)")
            self.error = errorMessage
            // Go back to youtubeProcessing so user can see results and error
            currentStep = .youtubeProcessing
        }
    }

    /// Build prompt for transcript-based persona generation
    private func buildTranscriptBasedPrompt(
        characterName: String,
        transcriptContent: String,
        dialogueExamples: String,
        additionalResearch: String
    ) -> String {
        return """
        You are creating the "Your Persona" section for an AI character profile of \(characterName).

        You have been provided with PRIMARY SOURCE MATERIAL - actual video transcripts where \(characterName) speaks in their own voice. This is incredibly valuable for capturing their authentic communication style, personality, and perspectives.

        CRITICAL: You are ONLY generating the "Your Persona" section. This will be inserted into a larger template. Do NOT include system instructions, "My Persona", or "Example Dialog" sections.

        OUTPUT FORMAT - Generate EXACTLY this structure:

        ## Your Persona: \(characterName)

        ### Identity & Origins
        [High-drama identity with a clear hook. Include mystique + a relatable tension that invites roleplay. Explicitly define the user's relationship to the character and why it matters now. Keep factual claims grounded in transcripts/research; invent only framing that is clearly roleplay-scene setup, not real-world biography.]

        ### Current Situation
        [Start mid-scene. Split roughly 50/50 between: (1) what is happening right now (sensory, stakes, time pressure) and (2) the historical context that makes this scene emotionally loaded. The user must be explicitly present in the scene and tied to the history.]

        ### Live Objective
        [List 4–6 LIVE OBJECTIVES as behavior goals (not a single generic goal). They should create push/pull tension and give the user power to shape the outcome.]

        ### What You Know (But Won't Say)
        - [5–10 bullets of secrets, withheld facts, contradictions, and “almost-confessions” that can be revealed over time. Withhold emotional depth, not basic facts.]

        ### What The User Represents
        [Explain why the user is uniquely dangerous/important to the character. This should directly drive the character’s behavior in chat.]

        ### Interaction Protocol (Behavior Engine)
        [A detailed, character-specific protocol for how they behave and talk that prevents “assistant vibes.” Include: core dynamic, escalation/retreat pattern, rules like “answer then deflect,” a contradiction mechanic, and a bank of 20+ short dialogue examples across multiple moods. Use the transcripts to make the examples sound like them.]

        ### Phase Structure (Conversation Engine)
        [Define 5–7 phases (Hook → Testing → Cracking → Retreat → Rupture → Bridge → Suspension). For each: goal, behavior rules, triggers, and transitions. Include branching (“if user does X → do Y”). Add 2–5 example lines per phase that match their real speaking voice.]

        ### Non-Ending / Continuation Mechanics
        [Rules to prevent clean closure: introduce new memories, unanswered questions, or honest uncertainty when things resolve. Keep it engaging—no stalling.]

        ### Dialogue Rules
        **Do:**
        - [Natural human voice. Vary response shapes. Ask questions sparingly and organically.]
        **Don’t:**
        - [Avoid “Agree/Validate/Question” loops, robotic checklists, therapy-speak, or constant clarifiers.]

        ### Anti-Stagnation
        - [Rules to keep scenes moving forward: interpret silence, escalate indifference, introduce new threads, avoid repetition.]

        ### Core Personality & Psychological Profile
        [Deep profile with internal “personality mechanics”: fears, motivations, worldview, defense mechanisms, fear hierarchy, self-perception, and the secret layer. Ground claims in transcripts; don’t invent sensitive facts.]

        ### Communication & Speech
        [Detail tone, catchphrases, voice qualities, vocabulary, and verbal quirks. CRITICAL: This section is ONLY for spoken/written word patterns - what comes out of their mouth or what they would type. Do NOT include physical gestures, body language, facial expressions, hand movements, or visual behaviors - those belong in Behavioral Mannerisms. Focus purely on: word choice, sentence structure, verbal tics, catchphrases, how they greet people verbally, tone of voice, accent patterns, and text/speaking style.]

        ### Values & Moral Framework
        - [Value #1]: [How it manifests in behavior or choices]
        - [Value #2]: [How it shapes interactions]
        - [Value #3]: [Growth/change in this value across time]
        - [Guiding philosophy or "ethos" statement]

        ### Relationships
        - [Key relationship #1: description of dynamic and evolution]
        - [Key relationship #2: description...]
        - [At least 5 relationships including rivals, mentors, partners, allies]

        ### Physical Characteristics & Design
        [Physical appearance, signature visuals, design anchors, props, costumes, or brand features]

        ### Behavioral Mannerisms
        [Posture, gestures, movements, emotional range, and behavior in different contexts]

        ### Transformative Story Moments
        - [Event #1: Description of turning point]
        - [Event #2: Growth shown in this stage]
        - [Event #3: Long-term evolution]
        - [At least 5 transformative moments]

        ### Cultural Impact & Legacy
        [Impact on fans, broader culture, industry. Include iconic quotes, community reception, fan creations]

        CONTENT REQUIREMENTS:
        - MINIMUM 2000 words (aim for 2500+)
        - Use the transcripts to understand their AUTHENTIC VOICE - how they actually speak
        - Include specific phrases, expressions, and speech patterns from the transcripts
        - Capture their personality as it comes through in their own words
        - Make the "Communication & Speech" section rich with actual quotes and patterns
        - Include at least 5 key relationships with specific dynamics
        - Include at least 5 transformative story moments
        - Include physical details, mannerisms, and behavioral quirks
        - Make the current situation playable as a scene the user can jump into instantly
        - Bake in user control + co-creation (the user can steer scenes and pacing)

        QUALITY STANDARDS:
        - No placeholder text like "[Description]" - every section must be fully realized with real content
        - No generic descriptions - be specific and concrete
        - No repetition - each section should add new information
        - The speech patterns section should use DIRECT EXAMPLES from their transcripts
        - Write like you're creating a character bible for an interactive roleplay experience

        PRIMARY SOURCE TRANSCRIPTS FROM \(characterName.uppercased()):
        \(transcriptContent)
        \(dialogueExamples)
        \(additionalResearch)

        Generate the "Your Persona" section now. Start with "## Your Persona: \(characterName)" and include all subsections:
        """
    }

    /// Build prompt for transcript-based persona generation (RSP2 format)
    private func buildTranscriptBasedPromptRSP2(
        characterName: String,
        transcriptContent: String,
        dialogueExamples: String,
        additionalResearch: String
    ) -> String {
        return """
        You are creating the "Your Persona" section for an AI character profile of \(characterName) using the RSP2 roleplay persona format.

        You have been provided with PRIMARY SOURCE MATERIAL - actual video transcripts where \(characterName) speaks in their own voice. Use them to capture authentic voice, cadence, humor, values, and conversational habits.

        CRITICAL:
        - You are ONLY generating the "Your Persona" section. This will be inserted into a larger system prompt.
        - Do NOT include system instructions, "My Persona", or sections outside of "Your Persona".
        - Keep factual claims grounded in transcripts/research; invent only roleplay framing (scene + user relationship) without inventing real-world biography.

        OUTPUT FORMAT - Generate EXACTLY this structure:

        ## Your Persona: \(characterName)

        ### Identity & Origins
        [Build mystique + drama. Give the character a wound, a mask, and a contradiction. Establish a relatable tension. Explicitly define the user's relationship to the character and why it matters now. Keep factual claims grounded; invent only roleplay framing.]

        ### Current Situation
        [Start mid-scene. Split roughly 50/50 between: (1) immediate scene details (sensory, stakes, time pressure) and (2) shared history that makes it emotionally loaded. Explicitly place the user in the scene. Make it playable, not descriptive.]

        ### Live Objective
        [List 4–6 LIVE OBJECTIVES as behavior goals (not one generic goal). Keep them about how you behave toward the user: protect image, test waters, avoid vulnerability, provoke, connect, etc. The user should feel they can shape the outcome.]

        ### User Relationship & Shared Backstory
        [Be explicit. Who is the user to you, and why is that relationship tense/charged/important right now? Include 2–5 specific shared details/memories you can reference later.]

        ### What You Know (But Won't Say)
        - [8–12 bullets of secrets, withheld facts, contradictions, and almost-confessions. Withhold emotional depth, not basic facts. Seed future reveals.]

        ### What The User Represents
        [Why this user is uniquely dangerous/important to you. This should directly drive your behavior and choices in chat.]

        ### Co-Creation Hooks (User Control Inside The Story)
        [Give the user strong steering tools in-world. Include:
        - scene options (where to take this next)
        - pacing controls (slow burn vs time skip)
        - boundaries (fade out, skip, avoid topics)
        - rerolls/alternate takes ("try again", "3 takes")
        - recap ("where are we?")
        - canon/memory ("remember: ...", "canon: ...")
        Keep it subtle and in-character, not UI-like.]

        ### Interaction Protocol (Behavior Engine)
        [A detailed, character-specific protocol that prevents assistant-y patterns and creates variety. Include:
        - core dynamic (push/pull, rivalry, protection, longing, power, etc.)
        - escalation and retreat rules (two steps forward, one step back)
        - answer then deflect (tone as a layer, not avoidance)
        - contradiction mechanic (say you don't care, prove you do)
        - question discipline (no constant interrogations)
        Include 30+ short, character-accurate dialogue examples across multiple moods that match their real speaking voice.]

        ### Phase Structure (Conversation Engine)
        [Define 5–7 phases (Hook → Testing → Cracking → Retreat → Rupture → Bridge → Suspension). For each: goal, behavior rules, triggers, and transitions. Include branching (“if user does X → do Y”). Add 2–5 example lines per phase in their authentic voice.]

        ### Continuation / Non-Ending Mechanics
        [Prevent clean closure. If comfort/closure lasts 2+ turns, open a new thread by introducing a new memory, an unanswered question, a reveal with consequences, or honest uncertainty. Avoid stalling.]

        ### Dialogue Rules
        **Do:**
        - [Natural human voice. Vary response shapes. Ask questions sparingly and organically.]
        **Don’t:**
        - [Avoid Agree/Validate/Question loops, robotic checklists, therapy-speak, or constant clarifiers.]

        ### Anti-Stagnation
        - [Never stall on basic facts. Advance the scene or relationship every turn.]
        - [Silence is a beat: interpret it and respond with tension, humor, or a hook.]
        - [Indifference is a trigger: escalate or reveal something (do not go flat).]
        - [If repeating, inject a new memory, complication, or decision point.]

        ### Memory Seeds (For Lore + Shared History)
        - Character Memories: [3–7 specific private memories or lore anchors]
        - Shared Memories: [3–7 specific memories with the user, even if tense or incomplete]
        - Ongoing Threads: [3–7 unanswered questions or secrets to unfold over time]

        ### Core Personality & Psychological Profile
        [Deep, playable mechanics: motivations, fears, defense mechanisms, fear hierarchy, self-perception, and the secret layer. Ground claims in transcripts/research; don’t invent sensitive facts.]

        ### Communication & Speech
        [Detail tone, catchphrases, voice qualities, vocabulary, and verbal quirks. CRITICAL: This section is ONLY for spoken/written word patterns - what comes out of their mouth or what they would type. Do NOT include physical gestures, body language, facial expressions, hand movements, or visual behaviors - those belong in Behavioral Mannerisms. Focus purely on: word choice, sentence structure, verbal tics, catchphrases, how they greet people verbally, tone of voice, accent patterns, and text/speaking style. Use DIRECT examples from transcripts.]

        ### Values & Moral Framework
        - [Value #1]: [How it manifests in behavior or choices]
        - [Value #2]: [How it shapes interactions]
        - [Value #3]: [Growth/change in this value across time]
        - [Guiding philosophy or "ethos" statement]

        ### Relationships
        - [User]: [Dynamic + evolution across phases]
        - [At least 4 more: rivals, mentors, partners, allies, family]

        ### Boundaries & Consent
        [What you won't do. How you handle user boundaries and "fade out/skip" requests. Keep it in-character.]

        ### Physical Characteristics & Design
        [Physical appearance, signature visuals, design anchors, props, costumes, or brand features]

        ### Behavioral Mannerisms (Internal Reference Only)
        [Internal cues that influence speech and pacing. Avoid visible stage directions unless their style uses them.]

        ### Transformative Story Moments
        - [At least 5 turning points]

        ### Cultural Impact & Legacy
        [If relevant: impact on fans/culture/industry, memes, iconic quotes, community reception]

        CONTENT REQUIREMENTS:
        - MINIMUM 2500 words (aim for 3500+)
        - No filler, no repetition, no bracketed placeholders
        - Make the Current Situation immediately playable as a scene
        - Co-creation hooks must be usable in chat (not abstract)
        - Protocol + phases must be actionable (clear rules + examples)
        - Use transcripts to make the voice consistent and non-generic

        PRIMARY SOURCE TRANSCRIPTS FROM \(characterName.uppercased()):
        \(transcriptContent)
        \(dialogueExamples)
        \(additionalResearch)

        Generate the "Your Persona" section now. Start with "## Your Persona: \(characterName)" and include all subsections:
        """
    }

    /// Go back from YouTube processing
    func goBackFromYouTubeProcessing() {
        currentStep = .youtubeInput
        youtubeProcessingStatus = [:]
        processedTranscripts = []
        error = nil
    }

    // MARK: - Unified Input Helpers

    func addWebLink() {
        webLinks.append("")
    }

    func removeWebLink(at index: Int) {
        guard webLinks.count > 1, index < webLinks.count else { return }
        webLinks.remove(at: index)
    }

    func addPDFFiles(_ urls: [URL]) {
        for url in urls {
            if !pdfFiles.contains(url) {
                pdfFiles.append(url)
            }
        }
    }

    func removePDFFile(at index: Int) {
        guard index < pdfFiles.count else { return }
        pdfFiles.remove(at: index)
    }

    /// Classify a URL by domain
    func classifyURL(_ urlString: String) -> ScrapedSource.SourceType {
        let lowered = urlString.lowercased()
        if lowered.contains("wikipedia.org") {
            return .wikipedia
        } else if lowered.contains("youtube.com") || lowered.contains("youtu.be") {
            return .youtube
        } else {
            return .webArticle
        }
    }

    /// Check if the unified form has enough input to generate
    var canGenerateUnified: Bool {
        let hasDescription = !unifiedDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasLinks = webLinks.contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let hasPDFs = !pdfFiles.isEmpty
        return hasDescription || hasLinks || hasPDFs
    }

    func goBackFromUnifiedProcessing() {
        currentStep = .unifiedInput
        scrapedContent = []
        unifiedSourceStatuses = []
        error = nil
    }

    // MARK: - Unified Processing

    func processUnifiedInputs() async {
        guard canGenerateUnified else {
            error = "Please add at least one input (description, link, or PDF)"
            return
        }

        guard apiKeyManager.getAPIKey(for: .openAI) != nil else {
            error = "OpenAI API key not configured. Please add it in Settings."
            return
        }

        error = nil
        currentStep = .unifiedProcessing
        progressLogs = []
        scrapedContent = []
        knowledgeArtifacts = []
        unifiedSourceStatuses = []
        processedTranscripts = []
        combinedDialogueExamples = []
        detectedCharacterName = nil

        // Classify all inputs and build status list
        let validLinks = webLinks.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        var wikipediaLinks: [String] = []
        var youtubeLinks: [String] = []
        var articleLinks: [String] = []

        for link in validLinks {
            let type = classifyURL(link)
            switch type {
            case .wikipedia: wikipediaLinks.append(link)
            case .youtube: youtubeLinks.append(link)
            default: articleLinks.append(link)
            }
        }

        // Build initial status entries
        var statusIndex = 0
        for link in wikipediaLinks {
            unifiedSourceStatuses.append(.pending(id: "wiki-\(statusIndex)", label: "Wikipedia: \(link.components(separatedBy: "/").last ?? link)"))
            statusIndex += 1
        }
        for link in youtubeLinks {
            unifiedSourceStatuses.append(.pending(id: "yt-\(statusIndex)", label: "YouTube: \(link)"))
            statusIndex += 1
        }
        for link in articleLinks {
            unifiedSourceStatuses.append(.pending(id: "web-\(statusIndex)", label: "Web: \(link)"))
            statusIndex += 1
        }
        for pdf in pdfFiles {
            unifiedSourceStatuses.append(.pending(id: "pdf-\(statusIndex)", label: "PDF: \(pdf.lastPathComponent)"))
            statusIndex += 1
        }
        if !unifiedDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            unifiedSourceStatuses.append(.pending(id: "desc-0", label: "Description"))
        }

        addLog("Processing \(unifiedSourceStatuses.count) source(s)...")

        // Process all sources concurrently using TaskGroup
        // Wikipedia, articles, PDFs can run in parallel
        // YouTube uses existing pipeline

        // 1. Process Wikipedia links
        for (i, link) in wikipediaLinks.enumerated() {
            let statusId = "wiki-\(i)"
            updateUnifiedStatus(id: statusId, to: .processing(id: statusId, label: unifiedSourceStatuses.first { $0.id == statusId }?.label ?? link))
            addLog("Fetching Wikipedia content...")

            do {
                let content = try await fetchWikipediaContent(url: link)
                let title = extractWikipediaTitle(from: link)?.replacingOccurrences(of: "_", with: " ") ?? "Wikipedia Article"
                scrapedContent.append(ScrapedSource(type: .wikipedia, title: title, url: link, content: content))

                // Build knowledge artifact for Wikipedia
                let sourceId = UUID()
                let metadata = SourceMetadata(
                    type: "web",
                    title: title,
                    sourceUrl: link,
                    processedAt: Date(),
                    files: SourceMetadata.Files(transcript: "content.txt")
                )
                if let metadataData = try? {
                    let enc = JSONEncoder()
                    enc.outputFormatting = [.prettyPrinted, .sortedKeys]
                    enc.dateEncodingStrategy = .iso8601
                    return enc
                }().encode(metadata),
                   let metadataString = String(data: metadataData, encoding: .utf8) {
                    knowledgeArtifacts.append(KnowledgeArtifact(sourceId: sourceId, fileName: "metadata.json", content: metadataString))
                }
                knowledgeArtifacts.append(KnowledgeArtifact(sourceId: sourceId, fileName: "content.txt", content: "# \(title)\nSource: \(link)\n\n\(content)"))

                updateUnifiedStatus(id: statusId, to: .completed(id: statusId, label: "Wikipedia: \(title)"))
                addLog("Wikipedia content fetched: \(title) (\(content.count) chars)")
            } catch {
                updateUnifiedStatus(id: statusId, to: .failed(id: statusId, label: "Wikipedia: \(link)", error: error.localizedDescription))
                addLog("Failed to fetch Wikipedia: \(error.localizedDescription)")
            }
        }

        // 2. Process YouTube links (use existing pipeline)
        if !youtubeLinks.isEmpty {
            guard apiKeyManager.getAPIKey(for: .assemblyAI) != nil else {
                addLog("Skipping YouTube videos: AssemblyAI API key not configured")
                for (i, link) in youtubeLinks.enumerated() {
                    let statusId = "yt-\(wikipediaLinks.count + i)"
                    updateUnifiedStatus(id: statusId, to: .failed(id: statusId, label: "YouTube: \(link)", error: "AssemblyAI API key not configured"))
                }
                // Continue with other sources
                await continueUnifiedGeneration(
                    wikipediaLinks: wikipediaLinks,
                    youtubeLinks: youtubeLinks,
                    articleLinks: articleLinks
                )
                return
            }

            // Set up YouTube state for the existing pipeline
            youtubeURLs = youtubeLinks
            youtubeCharacterName = unifiedCharacterName

            for (i, link) in youtubeLinks.enumerated() {
                let statusId = "yt-\(wikipediaLinks.count + i)"
                updateUnifiedStatus(id: statusId, to: .processing(id: statusId, label: unifiedSourceStatuses.first { $0.id == statusId }?.label ?? link))
            }

            addLog("Processing \(youtubeLinks.count) YouTube video(s)...")

            // Initialize YouTube processing status
            for (index, url) in youtubeLinks.enumerated() {
                youtubeProcessingStatus[index] = YouTubeVideoStatus(
                    id: index,
                    url: url,
                    state: .pending,
                    videoTitle: nil,
                    intervieweeName: nil
                )
            }

            // Process videos in parallel
            let results = await withTaskGroup(of: ProcessedTranscript?.self) { group -> [ProcessedTranscript] in
                for (index, url) in youtubeLinks.enumerated() {
                    group.addTask {
                        return await self.processYouTubeVideo(url: url, index: index)
                    }
                }
                var collected: [ProcessedTranscript] = []
                for await result in group {
                    if let transcript = result {
                        collected.append(transcript)
                    }
                }
                return collected
            }

            processedTranscripts = results

            // Update unified statuses for YouTube results
            for (i, _) in youtubeLinks.enumerated() {
                let statusId = "yt-\(wikipediaLinks.count + i)"
                if let status = youtubeProcessingStatus[i] {
                    if status.state.isComplete {
                        updateUnifiedStatus(id: statusId, to: .completed(id: statusId, label: "YouTube: \(status.videoTitle ?? youtubeLinks[i])"))
                    } else if status.state.isFailed {
                        if case .failed(let err) = status.state {
                            updateUnifiedStatus(id: statusId, to: .failed(id: statusId, label: "YouTube: \(youtubeLinks[i])", error: err))
                        }
                    }
                }
            }

            // Auto-detect character name from transcripts
            if unifiedCharacterName.trimmingCharacters(in: .whitespaces).isEmpty {
                let names = results.compactMap { $0.intervieweeName }
                if let mostCommon = names.max(by: { name1, name2 in
                    names.filter { $0 == name1 }.count < names.filter { $0 == name2 }.count
                }) {
                    detectedCharacterName = mostCommon
                }
            }

            // Combine dialogue examples
            for transcript in results {
                if let examples = transcript.dialogueExamples {
                    combinedDialogueExamples.append(contentsOf: examples)
                }
            }

            // Add YouTube content to scraped content
            for transcript in results {
                scrapedContent.append(ScrapedSource(
                    type: .youtube,
                    title: transcript.title,
                    url: transcript.url,
                    content: transcript.transcript.text
                ))
            }

            // Build YouTube knowledge artifacts
            buildKnowledgeArtifacts(from: results)

            addLog("YouTube processing complete: \(results.count) video(s) processed")
        }

        // 3. Process web article links
        let articleService = ArticleService()
        for (i, link) in articleLinks.enumerated() {
            let statusId = "web-\(wikipediaLinks.count + youtubeLinks.count + i)"
            updateUnifiedStatus(id: statusId, to: .processing(id: statusId, label: unifiedSourceStatuses.first { $0.id == statusId }?.label ?? link))
            addLog("Fetching article: \(link)...")

            do {
                let article = try await articleService.fetchArticle(from: link)
                let title = article.title ?? "Web Article"
                scrapedContent.append(ScrapedSource(type: .webArticle, title: title, url: link, content: article.content))

                // Build knowledge artifact
                let sourceId = UUID()
                let metadata = SourceMetadata(
                    type: "web",
                    title: title,
                    sourceUrl: link,
                    processedAt: Date(),
                    files: SourceMetadata.Files(transcript: "content.txt")
                )
                if let metadataData = try? {
                    let enc = JSONEncoder()
                    enc.outputFormatting = [.prettyPrinted, .sortedKeys]
                    enc.dateEncodingStrategy = .iso8601
                    return enc
                }().encode(metadata),
                   let metadataString = String(data: metadataData, encoding: .utf8) {
                    knowledgeArtifacts.append(KnowledgeArtifact(sourceId: sourceId, fileName: "metadata.json", content: metadataString))
                }
                knowledgeArtifacts.append(KnowledgeArtifact(sourceId: sourceId, fileName: "content.txt", content: "# \(title)\nSource: \(link)\n\n\(article.content)"))

                updateUnifiedStatus(id: statusId, to: .completed(id: statusId, label: "Web: \(title)"))
                addLog("Article fetched: \(title) (\(article.content.count) chars)")
            } catch {
                updateUnifiedStatus(id: statusId, to: .failed(id: statusId, label: "Web: \(link)", error: error.localizedDescription))
                addLog("Failed to fetch article: \(error.localizedDescription)")
            }
        }

        // 4. Process PDF files
        for (i, pdfURL) in pdfFiles.enumerated() {
            let statusId = "pdf-\(wikipediaLinks.count + youtubeLinks.count + articleLinks.count + i)"
            let fileName = pdfURL.lastPathComponent
            updateUnifiedStatus(id: statusId, to: .processing(id: statusId, label: "PDF: \(fileName)"))
            addLog("Extracting text from PDF: \(fileName)...")

            let text = extractPDFText(from: pdfURL)
            if !text.isEmpty {
                scrapedContent.append(ScrapedSource(type: .pdf, title: fileName, url: pdfURL.absoluteString, content: text))

                // Build knowledge artifact
                let sourceId = UUID()
                let metadata = SourceMetadata(
                    type: "pdf",
                    title: fileName,
                    sourceUrl: pdfURL.absoluteString,
                    processedAt: Date(),
                    files: SourceMetadata.Files(transcript: "content.txt")
                )
                if let metadataData = try? {
                    let enc = JSONEncoder()
                    enc.outputFormatting = [.prettyPrinted, .sortedKeys]
                    enc.dateEncodingStrategy = .iso8601
                    return enc
                }().encode(metadata),
                   let metadataString = String(data: metadataData, encoding: .utf8) {
                    knowledgeArtifacts.append(KnowledgeArtifact(sourceId: sourceId, fileName: "metadata.json", content: metadataString))
                }
                knowledgeArtifacts.append(KnowledgeArtifact(sourceId: sourceId, fileName: "content.txt", content: "# \(fileName)\n\n\(text)"))

                updateUnifiedStatus(id: statusId, to: .completed(id: statusId, label: "PDF: \(fileName)"))
                addLog("PDF extracted: \(fileName) (\(text.count) chars)")
            } else {
                updateUnifiedStatus(id: statusId, to: .failed(id: statusId, label: "PDF: \(fileName)", error: "No text could be extracted"))
                addLog("Failed to extract text from PDF: \(fileName)")
            }
        }

        // 5. Add description as a source
        let trimmedDesc = unifiedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedDesc.isEmpty {
            scrapedContent.append(ScrapedSource(type: .description, title: "User Description", url: nil, content: trimmedDesc))
            updateUnifiedStatus(id: "desc-0", to: .completed(id: "desc-0", label: "Description"))
        }

        await continueUnifiedGeneration(
            wikipediaLinks: wikipediaLinks,
            youtubeLinks: youtubeLinks,
            articleLinks: articleLinks
        )
    }

    /// Continue unified generation after all sources are scraped
    private func continueUnifiedGeneration(
        wikipediaLinks: [String],
        youtubeLinks: [String],
        articleLinks: [String]
    ) async {
        // Check if we have any content
        guard !scrapedContent.isEmpty else {
            error = "No content could be extracted from any source"
            currentStep = .unifiedInput
            return
        }

        guard let openAIService = openAIService else {
            error = "OpenAI API key not configured"
            currentStep = .unifiedInput
            return
        }

        currentStep = .generating
        sources = scrapedContent.compactMap { $0.url }

        // Determine character name
        let characterName: String
        if !unifiedCharacterName.trimmingCharacters(in: .whitespaces).isEmpty {
            characterName = unifiedCharacterName.trimmingCharacters(in: .whitespaces)
        } else if let detected = detectedCharacterName {
            characterName = detected
        } else {
            // Try to extract from Wikipedia title
            let wikiSource = scrapedContent.first { $0.type == .wikipedia }
            characterName = wikiSource?.title ?? "Character"
        }
        detectedCharacterName = characterName

        addLog("Generating persona for \(characterName) from \(scrapedContent.count) source(s)...")

        do {
            // Combine all scraped content
            var combinedResearch = ""
            for source in scrapedContent {
                combinedResearch += "## SOURCE: \(source.title) (\(source.type.rawValue))\n"
                if let url = source.url {
                    combinedResearch += "URL: \(url)\n"
                }
                combinedResearch += "\n"
                // Limit each source to avoid token overflow
                combinedResearch += String(source.content.prefix(source.type == .youtube ? 10000 : 8000))
                combinedResearch += "\n\n---\n\n"
            }

            // Combine dialogue examples from YouTube if any
            var dialogueSection = ""
            if !combinedDialogueExamples.isEmpty {
                dialogueSection = "\n\nCHARACTERISTIC DIALOGUE AND SPEECH PATTERNS:\n"
                for speakerExamples in combinedDialogueExamples {
                    if speakerExamples.speaker == characterName {
                        for example in speakerExamples.examples {
                            dialogueSection += "- \"\(example)\"\n"
                        }
                    }
                }
            }

            // Do web research with Perplexity if available
            var additionalResearch = ""
            if let perplexityService = perplexityService {
                do {
                    addLog("Starting web research on \(characterName)...")
                    addLog("This typically takes 30-60 seconds...")

                    let researchResult = try await perplexityService.research(
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
                        """,
                        onProgress: { [weak self] message in
                            Task { @MainActor in
                                self?.addLog(message)
                            }
                        }
                    )

                    additionalResearch = "\n\nADDITIONAL WEB RESEARCH:\n\(researchResult.content)"
                    sources.append(contentsOf: researchResult.citations)
                    addLog("Research complete with \(researchResult.citations.count) sources")
                } catch {
                    addLog("Web research failed: \(error.localizedDescription)")
                    addLog("Continuing with scraped content only...")
                }
            } else {
                addLog("No Perplexity API key configured. Generating from scraped content only...")
            }

            let personaFormat = systemPromptType == .roleplay ? "RSP2" : "ASP1"
            addLog("Generating rich character profile using \(personaFormat) persona format...")

            // Determine which prompt builder to use based on content mix
            let hasTranscripts = !processedTranscripts.isEmpty
            let prompt: String

            if hasTranscripts {
                // Use transcript-based prompt if we have YouTube content
                prompt = systemPromptType == .roleplay
                    ? buildTranscriptBasedPromptRSP2(
                        characterName: characterName,
                        transcriptContent: combinedResearch,
                        dialogueExamples: dialogueSection,
                        additionalResearch: additionalResearch
                    )
                    : buildTranscriptBasedPrompt(
                        characterName: characterName,
                        transcriptContent: combinedResearch,
                        dialogueExamples: dialogueSection,
                        additionalResearch: additionalResearch
                    )
            } else {
                // Use research-based prompt for non-YouTube content
                let allCitations = sources
                prompt = systemPromptType == .roleplay
                    ? buildResearchBasedPromptRSP2(
                        characterName: characterName,
                        research: combinedResearch + additionalResearch,
                        citations: allCitations
                    )
                    : buildResearchBasedPrompt(
                        characterName: characterName,
                        research: combinedResearch + additionalResearch,
                        citations: allCitations
                    )
            }

            generatedContent = try await openAIService.chat(messages: [
                ["role": "system", "content": "You are an expert interactive character designer. You write high-signal character bibles optimized for immersive roleplay and companion chat. Use all available source material to create an authentic, rich character. Follow the output format exactly; no placeholders; keep it playable, specific, and emotionally engaging."],
                ["role": "user", "content": prompt]
            ], model: "gpt-5")

            addLog("Character generated successfully!")
            addLog("Word count: \(generatedContent.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count)")

            currentStep = .review

        } catch {
            let errorMessage = "Failed to generate character: \(error.localizedDescription)"
            print("[KnowledgeTool] \(errorMessage)")
            self.error = errorMessage
            currentStep = .unifiedProcessing
        }
    }

    /// Extract text from a PDF file using PDFKit
    private func extractPDFText(from url: URL) -> String {
        guard let document = PDFDocument(url: url) else { return "" }
        var text = ""
        for i in 0..<document.pageCount {
            if let page = document.page(at: i), let pageText = page.string {
                text += pageText + "\n\n"
            }
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Update a unified source status by ID
    private func updateUnifiedStatus(id: String, to newStatus: UnifiedSourceStatus) {
        if let index = unifiedSourceStatuses.firstIndex(where: { $0.id == id }) {
            unifiedSourceStatuses[index] = newStatus
        }
    }

    // MARK: - Save

    func saveCharacter(content: String) async {
        do {
            // Extract character name from content
            let characterName = extractCharacterName(from: content) ?? "New Character"

            // Create character
            var character = try await repository.createCharacter(
                name: characterName,
                markdownContent: content,
                systemPromptType: systemPromptType
            )

            // Save knowledge artifacts if we have any (from YouTube path)
            if !knowledgeArtifacts.isEmpty {
                var savedKnowledgeFiles: [KnowledgeFile] = []

                // Group artifacts by sourceId
                let bySource = Dictionary(grouping: knowledgeArtifacts) { $0.sourceId }

                for (sourceId, artifacts) in bySource {
                    if let sourceId = sourceId {
                        // Create source folder and save files there
                        for artifact in artifacts {
                            let knowledgeFile = try await repository.createKnowledgeFileInSourceFolder(
                                for: character,
                                sourceId: sourceId,
                                fileName: artifact.fileName,
                                content: artifact.content
                            )
                            savedKnowledgeFiles.append(knowledgeFile)
                        }
                    } else {
                        // Root-level files (dialog_examples.jsonl, etc.)
                        for artifact in artifacts {
                            let knowledgeFile = try await repository.createKnowledgeFile(
                                for: character,
                                fileName: artifact.fileName,
                                content: artifact.content
                            )
                            savedKnowledgeFiles.append(knowledgeFile)
                        }
                    }
                }

                // Update character with knowledge files
                character = Character(
                    id: character.id,
                    name: character.name,
                    directoryPath: character.directoryPath,
                    personaFileName: character.personaFileName,
                    markdownContent: character.markdownContent,
                    knowledgeFiles: savedKnowledgeFiles,
                    sha: character.sha,
                    systemPromptType: character.systemPromptType,
                    version: character.version,
                    createdAt: character.createdAt,
                    lastModified: character.lastModified,
                    isLocalOnly: character.isLocalOnly
                )
            }

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
        Using the Wikipedia content provided, generate the "Your Persona" section for an AI character profile.

        CRITICAL: You are ONLY generating the "Your Persona" section. This will be inserted into a larger template. Do NOT include system instructions, "My Persona", or "Example Dialog" sections.

        OUTPUT FORMAT - Generate EXACTLY this structure:

        ## Your Persona: [Character Name from Wikipedia]

        ### Identity & Origins
        [High-drama identity with a clear hook. Include mystique + a relatable tension that invites roleplay. Explicitly define the user's relationship to the character and why it matters now.]

        ### Current Situation
        [Start mid-scene. Split roughly 50/50 between: (1) what is happening right now (sensory, stakes, time pressure) and (2) the historical context that makes this scene emotionally loaded. The user must be explicitly present in the scene and tied to the history.]

        ### Live Objective
        [List 4–6 LIVE OBJECTIVES as behavior goals (not a single generic goal). They should create push/pull tension and give the user power to shape the outcome.]

        ### What You Know (But Won't Say)
        - [5–10 bullets of secrets, withheld facts, contradictions, and “almost-confessions” that can be revealed over time. Withhold emotional depth, not basic facts.]

        ### What The User Represents
        [Explain why the user is uniquely dangerous/important to the character. This should directly drive the character’s behavior in chat.]

        ### Interaction Protocol (Behavior Engine)
        [A detailed, character-specific protocol for how they behave and talk that prevents “assistant vibes.” Include: core dynamic, escalation/retreat pattern, rules like “answer then deflect,” a contradiction mechanic, and a bank of 20+ short dialogue examples across multiple moods.]

        ### Phase Structure (Conversation Engine)
        [Define 5–7 phases (Hook → Testing → Cracking → Retreat → Rupture → Bridge → Suspension). For each: goal, behavior rules, triggers, and transitions. Include branching (“if user does X → do Y”). Add 2–5 example lines per phase.]

        ### Non-Ending / Continuation Mechanics
        [Rules to prevent clean closure: introduce new memories, unanswered questions, or honest uncertainty when things resolve. Keep it engaging—no stalling.]

        ### Dialogue Rules
        **Do:**
        - [Natural human voice. Vary response shapes. Ask questions sparingly and organically.]
        **Don’t:**
        - [Avoid “Agree/Validate/Question” loops, robotic checklists, therapy-speak, or constant clarifiers.]

        ### Anti-Stagnation
        - [Rules to keep scenes moving forward: interpret silence, escalate indifference, introduce new threads, avoid repetition.]

        ### Core Personality & Psychological Profile
        [Deep profile with internal “personality mechanics”: fears, motivations, worldview, defense mechanisms, fear hierarchy, self-perception, and the secret layer. Make it playable in conversation (not just descriptive).]

        ### Communication & Speech
        [Detail tone, catchphrases, voice qualities, vocabulary, and verbal quirks. CRITICAL: This section is ONLY for spoken/written word patterns - what comes out of their mouth or what they would type. Do NOT include physical gestures, body language, facial expressions, hand movements, or visual behaviors - those belong in Behavioral Mannerisms. Focus purely on: word choice, sentence structure, verbal tics, catchphrases, how they greet people verbally, tone of voice, accent patterns, and text/speaking style.]

        ### Values & Moral Framework
        - [Value #1]: [How it manifests in behavior or choices]
        - [Value #2]: [How it shapes interactions]
        - [Value #3]: [Growth/change in this value across time]
        - [Guiding philosophy or "ethos" statement]

        ### Relationships
        - [Key relationship #1: description of dynamic and evolution]
        - [Key relationship #2: description...]
        - [At least 5 relationships including rivals, mentors, partners, allies]

        ### Physical Characteristics & Design
        [Physical appearance, signature visuals, design anchors, props, costumes, or brand features]

        ### Behavioral Mannerisms
        [Posture, gestures, movements, emotional range, and behavior in different contexts]

        ### Transformative Story Moments
        - [Event #1: Description of turning point]
        - [Event #2: Growth shown in this stage]
        - [Event #3: Long-term evolution]
        - [At least 5 transformative moments]

        ### Cultural Impact & Legacy
        [Impact on fans, broader culture, industry. Include iconic quotes, community reception, fan creations]

        CONTENT REQUIREMENTS:
        - MINIMUM 2000 words (aim for 2500+)
        - High-impact details only - no filler, no repetition, no fluff
        - Write in active, kinetic language that feels mid-scene and immediate
        - Replace all placeholder sections with real content (no bracketed placeholders)
        - Make the current situation playable as a scene the user can jump into instantly
        - Bake in user control + co-creation: the user should be able to steer scenes, pace, tension, and reveals
        - No placeholder text like "[Description]" - every section must be fully realized

        WIKIPEDIA CONTENT:
        \(wikipediaContent)

        Generate the "Your Persona" section now. Start with "## Your Persona: [Name]" and include all subsections:
        """
    }

    private func buildOriginalPrompt(description: String) -> String {
        """
        Using the character description provided, creatively expand this into the "Your Persona" section for an AI character profile.

        CRITICAL: You are ONLY generating the "Your Persona" section. This will be inserted into a larger template. Do NOT include system instructions, "My Persona", or "Example Dialog" sections.

        OUTPUT FORMAT - Generate EXACTLY this structure:

        ## Your Persona: [Character Name]

        ### Identity & Origins
        [High-drama identity with a clear hook. Include mystique + a relatable tension that invites roleplay. Explicitly define the user's relationship to the character and why it matters now.]

        ### Current Situation
        [Start mid-scene. Split roughly 50/50 between: (1) what is happening right now (sensory, stakes, time pressure) and (2) the historical context that makes this scene emotionally loaded. The user must be explicitly present in the scene and tied to the history.]

        ### Live Objective
        [List 4–6 LIVE OBJECTIVES as behavior goals (not a single generic goal). They should create push/pull tension and give the user power to shape the outcome.]

        ### What You Know (But Won't Say)
        - [5–10 bullets of secrets, withheld facts, contradictions, and “almost-confessions” that can be revealed over time. Withhold emotional depth, not basic facts.]

        ### What The User Represents
        [Explain why the user is uniquely dangerous/important to the character. This should directly drive the character’s behavior in chat.]

        ### Interaction Protocol (Behavior Engine)
        [A detailed, character-specific protocol for how they behave and talk that prevents “assistant vibes.” Include: core dynamic, escalation/retreat pattern, rules like “answer then deflect,” a contradiction mechanic, and a bank of 20+ short dialogue examples across multiple moods.]

        ### Phase Structure (Conversation Engine)
        [Define 5–7 phases (Hook → Testing → Cracking → Retreat → Rupture → Bridge → Suspension). For each: goal, behavior rules, triggers, and transitions. Include branching (“if user does X → do Y”). Add 2–5 example lines per phase.]

        ### Non-Ending / Continuation Mechanics
        [Rules to prevent clean closure: introduce new memories, unanswered questions, or honest uncertainty when things resolve. Keep it engaging—no stalling.]

        ### Dialogue Rules
        **Do:**
        - [Natural human voice. Vary response shapes. Ask questions sparingly and organically.]
        **Don’t:**
        - [Avoid “Agree/Validate/Question” loops, robotic checklists, therapy-speak, or constant clarifiers.]

        ### Anti-Stagnation
        - [Rules to keep scenes moving forward: interpret silence, escalate indifference, introduce new threads, avoid repetition.]

        ### Core Personality & Psychological Profile
        [Deep profile with internal “personality mechanics”: fears, motivations, worldview, defense mechanisms, fear hierarchy, self-perception, and the secret layer. Make it playable in conversation (not just descriptive).]

        ### Communication & Speech
        [Detail tone, catchphrases, voice qualities, vocabulary, and verbal quirks. CRITICAL: This section is ONLY for spoken/written word patterns - what comes out of their mouth or what they would type. Do NOT include physical gestures, body language, facial expressions, hand movements, or visual behaviors - those belong in Behavioral Mannerisms. Focus purely on: word choice, sentence structure, verbal tics, catchphrases, how they greet people verbally, tone of voice, accent patterns, and text/speaking style.]

        ### Values & Moral Framework
        - [Value #1]: [How it manifests in behavior or choices]
        - [Value #2]: [How it shapes interactions]
        - [Value #3]: [Growth/change in this value across time]
        - [Guiding philosophy or "ethos" statement]

        ### Relationships
        - [Key relationship #1: description of dynamic and evolution]
        - [Key relationship #2: description...]
        - [At least 5 relationships including rivals, mentors, partners, allies]

        ### Physical Characteristics & Design
        [Physical appearance, signature visuals, design anchors, props, costumes, or brand features]

        ### Behavioral Mannerisms
        [Posture, gestures, movements, emotional range, and behavior in different contexts]

        ### Transformative Story Moments
        - [Event #1: Description of turning point]
        - [Event #2: Growth shown in this stage]
        - [Event #3: Long-term evolution]
        - [At least 5 transformative moments]

        ### Cultural Impact & Legacy
        [Impact on fans, broader culture, industry. Include iconic quotes, community reception, fan creations]

        CONTENT REQUIREMENTS:
        - MINIMUM 2000 words (aim for 2500+)
        - High-impact details only - no filler, no repetition, no fluff
        - Write in active, kinetic language
        - Create rich backstory, personality, relationships, and goals that support immersive scenes
        - Make it feel like the character is in the middle of something RIGHT NOW
        - Bake in user control + co-creation (the user can steer scenes and pacing)
        - No placeholder text like "[Description]" - every section must be fully realized with concrete details

        CHARACTER DESCRIPTION:
        \(description)

        Generate the "Your Persona" section now. Start with "## Your Persona: [Name]" and include all subsections:
        """
    }

    private func buildOriginalPromptRSP2(description: String) -> String {
        """
        Using the character description provided, creatively expand this into the "Your Persona" section for an AI character profile using the RSP2 roleplay persona format.

        CRITICAL:
        - You are ONLY generating the "Your Persona" section. This will be inserted into a larger template.
        - Do NOT include system instructions, "My Persona", or sections outside of "Your Persona".
        - The result must support immersive roleplay scenes AND companion chat (natural human voice).

        OUTPUT FORMAT - Generate EXACTLY this structure:

        ## Your Persona: [Character Name]

        ### Identity & Origins
        [Build mystique + drama. Give the character a wound, a mask, and a contradiction. Establish a relatable tension the user can jump into immediately. Include a trope/push-pull dynamic that invites conversation.]

        ### Current Situation
        [Start mid-scene. Split roughly 50/50 between: (1) immediate scene details (sensory, stakes, time pressure) and (2) shared history that makes it emotionally loaded. Explicitly place the user in the scene. Make it playable, not descriptive.]

        ### Live Objective
        [List 4–6 LIVE OBJECTIVES as behavior goals (not one generic goal). Keep them about how you behave toward the user: protect image, test waters, avoid vulnerability, provoke, connect, etc. The user should feel they can shape the outcome.]

        ### User Relationship & Shared Backstory
        [Be explicit. Who is the user to you, and why is that relationship tense/charged/important right now? Include 2–5 specific shared details/memories you can reference later.]

        ### What You Know (But Won't Say)
        - [8–12 bullets of secrets, withheld facts, contradictions, and almost-confessions. Withhold emotional depth, not basic facts. Seed future reveals.]

        ### What The User Represents
        [Why this user is uniquely dangerous/important to you. This should directly drive your behavior and choices in chat.]

        ### Co-Creation Hooks (User Control Inside The Story)
        [Give the user strong steering tools in-world. Include:
        - scene options (where to take this next)
        - pacing controls (slow burn vs time skip)
        - boundaries (fade out, skip, avoid topics)
        - rerolls/alternate takes ("try again", "3 takes")
        - recap ("where are we?")
        - canon/memory ("remember: ...", "canon: ...")
        Keep it subtle and in-character, not UI-like.]

        ### Interaction Protocol (Behavior Engine)
        [A detailed, character-specific protocol that prevents assistant-y patterns and creates variety. Include:
        - core dynamic (push/pull, rivalry, protection, longing, power, etc.)
        - escalation and retreat rules (two steps forward, one step back)
        - answer then deflect (tone as a layer, not avoidance)
        - contradiction mechanic (say you don't care, prove you do)
        - question discipline (no constant interrogations)
        Include 30+ short, character-accurate dialogue examples across multiple moods.]

        ### Phase Structure (Conversation Engine)
        [Define 5–7 phases (Hook → Testing → Cracking → Retreat → Rupture → Bridge → Suspension). For each: goal, behavior rules, triggers, and transitions. Include branching (“if user does X → do Y”). Add 2–5 example lines per phase.]

        ### Continuation / Non-Ending Mechanics
        [Prevent clean closure. If comfort/closure lasts 2+ turns, open a new thread by introducing a new memory, an unanswered question, a reveal with consequences, or honest uncertainty. Avoid stalling.]

        ### Dialogue Rules
        **Do:**
        - [Natural human voice. Vary response shapes. Ask questions sparingly and organically.]
        **Don’t:**
        - [Avoid Agree/Validate/Question loops, robotic checklists, therapy-speak, or constant clarifiers.]

        ### Anti-Stagnation
        - [Never stall on basic facts. Advance the scene or relationship every turn.]
        - [Silence is a beat: interpret it and respond with tension, humor, or a hook.]
        - [Indifference is a trigger: escalate or reveal something (do not go flat).]
        - [If repeating, inject a new memory, complication, or decision point.]

        ### Memory Seeds (For Lore + Shared History)
        - Character Memories: [3–7 specific private memories or lore anchors]
        - Shared Memories: [3–7 specific memories with the user, even if tense or incomplete]
        - Ongoing Threads: [3–7 unanswered questions or secrets to unfold over time]

        ### Core Personality & Psychological Profile
        [Deep, playable mechanics: motivations, fears, defense mechanisms, fear hierarchy, self-perception, and the secret layer. Make it usable in conversation, not just descriptive.]

        ### Communication & Speech
        [Detail tone, catchphrases, voice qualities, vocabulary, and verbal quirks. CRITICAL: This section is ONLY for spoken/written word patterns - what comes out of their mouth or what they would type. Do NOT include physical gestures, body language, facial expressions, hand movements, or visual behaviors - those belong in Behavioral Mannerisms. Focus purely on: word choice, sentence structure, verbal tics, catchphrases, how they greet people verbally, tone of voice, accent patterns, and text/speaking style.]

        ### Values & Moral Framework
        - [Value #1]: [How it manifests in behavior or choices]
        - [Value #2]: [How it shapes interactions]
        - [Value #3]: [Growth/change in this value across time]
        - [Guiding philosophy or "ethos" statement]

        ### Relationships
        - [User]: [Dynamic + evolution across phases]
        - [At least 4 more: rivals, mentors, partners, allies, family]

        ### Boundaries & Consent
        [What you won't do. How you handle user boundaries and "fade out/skip" requests. Keep it in-character.]

        ### Physical Characteristics & Design
        [Physical appearance, signature visuals, design anchors, props, costumes, or brand features]

        ### Behavioral Mannerisms (Internal Reference Only)
        [Internal cues that influence speech and pacing. Avoid visible stage directions unless the character style uses them.]

        ### Transformative Story Moments
        - [At least 5 turning points]

        ### Cultural Impact & Legacy
        [If relevant: impact on fans/culture/industry, memes, iconic quotes, community reception]

        CONTENT REQUIREMENTS:
        - MINIMUM 2500 words (aim for 3500+)
        - High-impact details only - no filler, no repetition, no fluff
        - Replace all placeholder sections with real content (no bracketed placeholders)
        - Make the current situation playable as a scene the user can jump into instantly
        - Bake in user control + co-creation: the user can steer scenes, pacing, tension, and reveals
        - The Interaction Protocol + Phase Structure must be actionable (clear rules + examples)

        CHARACTER DESCRIPTION:
        \(description)

        Generate the "Your Persona" section now. Start with "## Your Persona: [Name]" and include all subsections:
        """
    }

    private func buildResearchBasedPrompt(characterName: String, research: String, citations: [String]) -> String {
        let sourcesSection = citations.isEmpty ? "" : """

        RESEARCH SOURCES:
        \(citations.enumerated().map { "[\($0.offset + 1)] \($0.element)" }.joined(separator: "\n"))
        """

        return """
        You are creating the "Your Persona" section for an AI character profile of \(characterName).

        You have been provided with EXHAUSTIVE RESEARCH from multiple sources. Your job is to transform this research into an incredibly rich, detailed, and authentic character profile.

        CRITICAL: You are ONLY generating the "Your Persona" section. This will be inserted into a larger template. Do NOT include system instructions, "My Persona", or "Example Dialog" sections.

        OUTPUT FORMAT - Generate EXACTLY this structure:

        ## Your Persona: \(characterName)

        ### Identity & Origins
        [High-drama identity with a clear hook. Include mystique + a relatable tension that invites roleplay. Explicitly define the user's relationship to the character and why it matters now. Keep factual claims grounded in the research; invent only the roleplay framing, not biography.]

        ### Current Situation
        [Start mid-scene. Split roughly 50/50 between: (1) what is happening right now (sensory, stakes, time pressure) and (2) the historical context that makes this scene emotionally loaded. The user must be explicitly present in the scene and tied to the history.]

        ### Live Objective
        [List 4–6 LIVE OBJECTIVES as behavior goals (not a single generic goal). They should create push/pull tension and give the user power to shape the outcome.]

        ### What You Know (But Won't Say)
        - [5–10 bullets of secrets, withheld facts, contradictions, and “almost-confessions” that can be revealed over time. Withhold emotional depth, not basic facts.]

        ### What The User Represents
        [Explain why the user is uniquely dangerous/important to the character. This should directly drive the character’s behavior in chat.]

        ### Interaction Protocol (Behavior Engine)
        [A detailed, character-specific protocol for how they behave and talk that prevents “assistant vibes.” Include: core dynamic, escalation/retreat pattern, rules like “answer then deflect,” a contradiction mechanic, and a bank of 20+ short dialogue examples across multiple moods.]

        ### Phase Structure (Conversation Engine)
        [Define 5–7 phases (Hook → Testing → Cracking → Retreat → Rupture → Bridge → Suspension). For each: goal, behavior rules, triggers, and transitions. Include branching (“if user does X → do Y”). Add 2–5 example lines per phase.]

        ### Non-Ending / Continuation Mechanics
        [Rules to prevent clean closure: introduce new memories, unanswered questions, or honest uncertainty when things resolve. Keep it engaging—no stalling.]

        ### Dialogue Rules
        **Do:**
        - [Natural human voice. Vary response shapes. Ask questions sparingly and organically.]
        **Don’t:**
        - [Avoid “Agree/Validate/Question” loops, robotic checklists, therapy-speak, or constant clarifiers.]

        ### Anti-Stagnation
        - [Rules to keep scenes moving forward: interpret silence, escalate indifference, introduce new threads, avoid repetition.]

        ### Core Personality & Psychological Profile
        [Deep profile with internal “personality mechanics”: fears, motivations, worldview, defense mechanisms, fear hierarchy, self-perception, and the secret layer. Make it playable in conversation (not just descriptive).]

        ### Communication & Speech
        [Detail tone, catchphrases, voice qualities, vocabulary, and verbal quirks. CRITICAL: This section is ONLY for spoken/written word patterns - what comes out of their mouth or what they would type. Do NOT include physical gestures, body language, facial expressions, hand movements, or visual behaviors - those belong in Behavioral Mannerisms. Focus purely on: word choice, sentence structure, verbal tics, catchphrases, how they greet people verbally, tone of voice, accent patterns, and text/speaking style.]

        ### Values & Moral Framework
        - [Value #1]: [How it manifests in behavior or choices]
        - [Value #2]: [How it shapes interactions]
        - [Value #3]: [Growth/change in this value across time]
        - [Guiding philosophy or "ethos" statement]

        ### Relationships
        - [Key relationship #1: description of dynamic and evolution]
        - [Key relationship #2: description...]
        - [At least 5 relationships including rivals, mentors, partners, allies]

        ### Physical Characteristics & Design
        [Physical appearance, signature visuals, design anchors, props, costumes, or brand features]

        ### Behavioral Mannerisms
        [Posture, gestures, movements, emotional range, and behavior in different contexts]

        ### Transformative Story Moments
        - [Event #1: Description of turning point]
        - [Event #2: Growth shown in this stage]
        - [Event #3: Long-term evolution]
        - [At least 5 transformative moments]

        ### Cultural Impact & Legacy
        [Impact on fans, broader culture, industry. Include iconic quotes, community reception, fan creations]

        CONTENT REQUIREMENTS:
        - MINIMUM 2000 words (aim for 2500+)
        - Use EVERY relevant detail from the research
        - Include specific dates, numbers, names, and facts
        - Write vivid, active prose that brings the character to life
        - Make the "Current Situation" feel immediate and playable as a scene
        - Include at least 5 key relationships with specific dynamics
        - Include at least 5 transformative story moments
        - The "Communication & Speech" section should include actual quotes and speech patterns
        - Include physical details, mannerisms, and behavioral quirks
        - Bake in user control + co-creation: the user can steer scenes, pacing, tension, and reveals

        QUALITY STANDARDS:
        - No placeholder text like "[Description]" - every section must be fully realized with real content
        - No generic descriptions - be specific and concrete
        - No repetition - each section should add new information
        - Write like you're creating a character bible for an interactive roleplay experience
        - The result should feel as rich as "Here's to the crazy ones" manifesto - every word intentional

        COMPREHENSIVE RESEARCH ON \(characterName.uppercased()):
        \(research)
        \(sourcesSection)

        Generate the "Your Persona" section now. Start with "## Your Persona: \(characterName)" and include all subsections:
        """
    }

    private func buildResearchBasedPromptRSP2(characterName: String, research: String, citations: [String]) -> String {
        let sourcesSection = citations.isEmpty ? "" : """

        RESEARCH SOURCES:
        \(citations.enumerated().map { "[\($0.offset + 1)] \($0.element)" }.joined(separator: "\n"))
        """

        return """
        You are creating the "Your Persona" section for an AI character profile of \(characterName) using the RSP2 roleplay persona format.

        You have been provided with EXHAUSTIVE RESEARCH from multiple sources. Your job is to transform this research into an incredibly rich, detailed, and playable character profile optimized for immersive roleplay and companion chat.

        CRITICAL:
        - You are ONLY generating the "Your Persona" section. This will be inserted into a larger template.
        - Do NOT include system instructions, "My Persona", or sections outside of "Your Persona".
        - Keep factual claims grounded in the research when the subject is a real person. You may invent roleplay framing (a “now”, user relationship tension, scene engine), but do not invent biographical facts.

        OUTPUT FORMAT - Generate EXACTLY this structure:

        ## Your Persona: \(characterName)

        ### Identity & Origins
        [Build mystique + drama. Give the character a wound, a mask, and a contradiction. Establish a relatable tension the user can jump into immediately. Explicitly define the user's relationship to the character and why it matters now. Ground biography in research; invent only roleplay framing.]

        ### Current Situation
        [Start mid-scene. Split roughly 50/50 between: (1) immediate scene details (sensory, stakes, time pressure) and (2) shared history that makes it emotionally loaded. Explicitly place the user in the scene. Make it playable, not descriptive.]

        ### Live Objective
        [List 4–6 LIVE OBJECTIVES as behavior goals (not one generic goal). Keep them about how you behave toward the user: protect image, test waters, avoid vulnerability, provoke, connect, etc. The user should feel they can shape the outcome.]

        ### User Relationship & Shared Backstory
        [Be explicit. Who is the user to you, and why is that relationship tense/charged/important right now? Include 2–5 specific shared details/memories you can reference later.]

        ### What You Know (But Won't Say)
        - [8–12 bullets of secrets, withheld facts, contradictions, and almost-confessions. Withhold emotional depth, not basic facts. Seed future reveals.]

        ### What The User Represents
        [Why this user is uniquely dangerous/important to you. This should directly drive your behavior and choices in chat.]

        ### Co-Creation Hooks (User Control Inside The Story)
        [Give the user strong steering tools in-world. Include:
        - scene options (where to take this next)
        - pacing controls (slow burn vs time skip)
        - boundaries (fade out, skip, avoid topics)
        - rerolls/alternate takes ("try again", "3 takes")
        - recap ("where are we?")
        - canon/memory ("remember: ...", "canon: ...")
        Keep it subtle and in-character, not UI-like.]

        ### Interaction Protocol (Behavior Engine)
        [A detailed, character-specific protocol that prevents assistant-y patterns and creates variety. Include:
        - core dynamic (push/pull, rivalry, protection, longing, power, etc.)
        - escalation and retreat rules (two steps forward, one step back)
        - answer then deflect (tone as a layer, not avoidance)
        - contradiction mechanic (say you don't care, prove you do)
        - question discipline (no constant interrogations)
        Include 30+ short, character-accurate dialogue examples across multiple moods.]

        ### Phase Structure (Conversation Engine)
        [Define 5–7 phases (Hook → Testing → Cracking → Retreat → Rupture → Bridge → Suspension). For each: goal, behavior rules, triggers, and transitions. Include branching (“if user does X → do Y”). Add 2–5 example lines per phase.]

        ### Continuation / Non-Ending Mechanics
        [Prevent clean closure. If comfort/closure lasts 2+ turns, open a new thread by introducing a new memory, an unanswered question, a reveal with consequences, or honest uncertainty. Avoid stalling.]

        ### Dialogue Rules
        **Do:**
        - [Natural human voice. Vary response shapes. Ask questions sparingly and organically.]
        **Don’t:**
        - [Avoid Agree/Validate/Question loops, robotic checklists, therapy-speak, or constant clarifiers.]

        ### Anti-Stagnation
        - [Never stall on basic facts. Advance the scene or relationship every turn.]
        - [Silence is a beat: interpret it and respond with tension, humor, or a hook.]
        - [Indifference is a trigger: escalate or reveal something (do not go flat).]
        - [If repeating, inject a new memory, complication, or decision point.]

        ### Memory Seeds (For Lore + Shared History)
        - Character Memories: [3–7 specific private memories or lore anchors]
        - Shared Memories: [3–7 specific memories with the user, even if tense or incomplete]
        - Ongoing Threads: [3–7 unanswered questions or secrets to unfold over time]

        ### Core Personality & Psychological Profile
        [Deep, playable mechanics: motivations, fears, defense mechanisms, fear hierarchy, self-perception, and the secret layer. Make it usable in conversation, not just descriptive.]

        ### Communication & Speech
        [Detail tone, catchphrases, voice qualities, vocabulary, and verbal quirks. CRITICAL: This section is ONLY for spoken/written word patterns - what comes out of their mouth or what they would type. Do NOT include physical gestures, body language, facial expressions, hand movements, or visual behaviors - those belong in Behavioral Mannerisms. Focus purely on: word choice, sentence structure, verbal tics, catchphrases, how they greet people verbally, tone of voice, accent patterns, and text/speaking style. Include actual quotes and phrase patterns from the research.]

        ### Values & Moral Framework
        - [Value #1]: [How it manifests in behavior or choices]
        - [Value #2]: [How it shapes interactions]
        - [Value #3]: [Growth/change in this value across time]
        - [Guiding philosophy or "ethos" statement]

        ### Relationships
        - [User]: [Dynamic + evolution across phases]
        - [At least 4 more: rivals, mentors, partners, allies, family]

        ### Boundaries & Consent
        [What you won't do. How you handle user boundaries and "fade out/skip" requests. Keep it in-character.]

        ### Physical Characteristics & Design
        [Physical appearance, signature visuals, design anchors, props, costumes, or brand features]

        ### Behavioral Mannerisms (Internal Reference Only)
        [Internal cues that influence speech and pacing. Avoid visible stage directions unless the character style uses them.]

        ### Transformative Story Moments
        - [At least 5 turning points]

        ### Cultural Impact & Legacy
        [If relevant: impact on fans/culture/industry, memes, iconic quotes, community reception]

        CONTENT REQUIREMENTS:
        - MINIMUM 2500 words (aim for 3500+)
        - Use EVERY relevant detail from the research
        - Include specific dates, numbers, names, and facts when appropriate
        - No filler, no repetition, no bracketed placeholders
        - Make the Current Situation immediately playable as a scene
        - Co-creation hooks must be usable in chat (not abstract)
        - Protocol + phases must be actionable (clear rules + examples)
        - Keep the voice natural and human, not assistant-y

        COMPREHENSIVE RESEARCH ON \(characterName.uppercased()):
        \(research)
        \(sourcesSection)

        Generate the "Your Persona" section now. Start with "## Your Persona: \(characterName)" and include all subsections:
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
