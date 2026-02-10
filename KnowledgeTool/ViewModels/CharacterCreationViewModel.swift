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
        case youtubeInput
        case youtubeProcessing
        case generating
        case review
    }

    enum CreationPath {
        case wikipedia
        case original
        case youtube
    }

    private(set) var currentStep: Step = .pathSelection
    private(set) var selectedPath: CreationPath?

    // Input state
    var wikipediaURL: String = ""
    var originalDescription: String = ""

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
            addLog("Generating rich character profile using ASP-1 template...")

            let prompt: String
            if !researchContent.isEmpty {
                prompt = buildResearchBasedPrompt(
                    characterName: characterName,
                    research: researchContent,
                    citations: researchCitations
                )
            } else {
                // Fallback: use Wikipedia content directly
                prompt = buildResearchBasedPrompt(
                    characterName: characterName,
                    research: "Wikipedia content:\n\n\(wikiContent)",
                    citations: [wikipediaURL]
                )
            }

            generatedContent = try await openAIService.chat(messages: [
                ["role": "system", "content": "You are an expert character designer that creates incredibly detailed, rich character personas. Your characters feel alive, with deep backstories, nuanced personalities, and authentic voices. Follow the ASP-1 template structure exactly."],
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
                    addLog("Generating rich character profile using ASP-1 template...")

                    let prompt = buildResearchBasedPrompt(
                        characterName: characterName,
                        research: researchResult.content,
                        citations: researchResult.citations
                    )

                    generatedContent = try await openAIService.chat(messages: [
                        ["role": "system", "content": "You are an expert character designer that creates incredibly detailed, rich character personas. Your characters feel alive, with deep backstories, nuanced personalities, and authentic voices. Follow the ASP-1 template structure exactly."],
                        ["role": "user", "content": prompt]
                    ], model: "gpt-5")
                } catch {
                    // Research failed - fall back to creative generation
                    addLog("⚠️ Web research failed: \(error.localizedDescription)")
                    addLog("Falling back to creative generation...")

                    let prompt = buildOriginalPrompt(description: originalDescription)
                    generatedContent = try await openAIService.chat(messages: [
                        ["role": "system", "content": "You are a creative character generation assistant that creates detailed character personas following the ASP-1 template. Make the character feel real with rich backstory and authentic voice."],
                        ["role": "user", "content": prompt]
                    ], model: "gpt-5")
                }

            } else {
                // Creative generation path for fictional characters
                addLog("Creating original fictional character...")
                addLog("Generating character using ASP-1 template...")

                let prompt = buildOriginalPrompt(description: originalDescription)
                generatedContent = try await openAIService.chat(messages: [
                    ["role": "system", "content": "You are a creative character generation assistant that creates detailed character personas following the ASP-1 template. Make the character feel real with rich backstory and authentic voice."],
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

            addLog("Generating rich character profile using ASP-1 template...")

            let prompt = buildTranscriptBasedPrompt(
                characterName: characterName,
                transcriptContent: transcriptContent,
                dialogueExamples: dialogueSection,
                additionalResearch: additionalResearch
            )

            generatedContent = try await openAIService.chat(messages: [
                ["role": "system", "content": "You are an expert character designer that creates incredibly detailed, rich character personas from primary source material. You have access to real transcripts of the person speaking, which gives you authentic insight into their voice, personality, and communication style. Follow the ASP-1 template structure exactly."],
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
        [Full paragraphs describing the character's origin, background, and core identity]

        ### Current Situation
        [What is happening right now in their world - what they're in the middle of, what's at stake]

        ### Live Objective
        [What they're actively trying to accomplish within this scene or timeline]

        ### Core Personality & Psychological Profile
        [Full paragraphs summarizing key traits, personality type, fears, motivations, worldview, and recurring conflicts]

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
        - Make the character feel like they're in the middle of action RIGHT NOW

        QUALITY STANDARDS:
        - No placeholder text like "[Description]" - every section must be fully realized with real content
        - No generic descriptions - be specific and concrete
        - No repetition - each section should add new information
        - The speech patterns section should use DIRECT EXAMPLES from their transcripts
        - Write like you're creating a character bible for a major production

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

    // MARK: - Save

    func saveCharacter(content: String) async {
        do {
            // Extract character name from content
            let characterName = extractCharacterName(from: content) ?? "New Character"

            // Create character
            var character = try await repository.createCharacter(
                name: characterName,
                markdownContent: content
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
        [Full paragraphs describing the character's origin, background, and core identity]

        ### Current Situation
        [What is happening right now in their world - what they're in the middle of, what's at stake]

        ### Live Objective
        [What they're actively trying to accomplish within this scene or timeline]

        ### Core Personality & Psychological Profile
        [Full paragraphs summarizing key traits, personality type, fears, motivations, worldview, and recurring conflicts]

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
        - Minimum 1500 words
        - High-impact details only - no filler, no repetition, no fluff
        - Write in active, kinetic language
        - Replace all placeholder sections with real content
        - Make it feel like the character is in the middle of action RIGHT NOW
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
        [Full paragraphs describing the character's origin, background, and core identity]

        ### Current Situation
        [What is happening right now in their world - what they're in the middle of, what's at stake]

        ### Live Objective
        [What they're actively trying to accomplish within this scene or timeline]

        ### Core Personality & Psychological Profile
        [Full paragraphs summarizing key traits, personality type, fears, motivations, worldview, and recurring conflicts]

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
        - Minimum 1500 words
        - High-impact details only - no filler, no repetition, no fluff
        - Write in active, kinetic language
        - Create rich backstory, personality, relationships, and goals
        - Make it feel like the character is in the middle of action RIGHT NOW
        - No placeholder text like "[Description]" - every section must be fully realized

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
        [Full paragraphs describing the character's origin, background, and core identity]

        ### Current Situation
        [What is happening right now in their world - what they're in the middle of, what's at stake]

        ### Live Objective
        [What they're actively trying to accomplish within this scene or timeline]

        ### Core Personality & Psychological Profile
        [Full paragraphs summarizing key traits, personality type, fears, motivations, worldview, and recurring conflicts]

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
        - Make the "Current Situation" feel immediate and urgent
        - Include at least 5 key relationships with specific dynamics
        - Include at least 5 transformative story moments
        - The "Communication & Speech" section should include actual quotes and speech patterns
        - Include physical details, mannerisms, and behavioral quirks
        - Make the character feel like they're in the middle of action RIGHT NOW

        QUALITY STANDARDS:
        - No placeholder text like "[Description]" - every section must be fully realized with real content
        - No generic descriptions - be specific and concrete
        - No repetition - each section should add new information
        - Write like you're creating a character bible for a major production
        - The result should feel as rich as "Here's to the crazy ones" manifesto - every word intentional

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
