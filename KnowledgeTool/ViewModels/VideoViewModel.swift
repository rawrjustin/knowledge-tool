import Foundation
import SwiftUI

@Observable
final class VideoViewModel {
    var urlInput: String = ""
    var processingState: ProcessingState = .idle
    var transcript: Transcript?
    var summary: Summary?
    var videoInfo: VideoInfo?
    var errorMessage: String?
    var intervieweeName: String?

    private let apiKeyManager: APIKeyManager
    private var videoService = VideoService()

    init(apiKeyManager: APIKeyManager) {
        self.apiKeyManager = apiKeyManager
    }

    // MARK: - Process Video from URL
    @MainActor
    func processVideoFromURL() async {
        guard !urlInput.trimmingCharacters(in: .whitespaces).isEmpty else {
            errorMessage = "Please enter a valid URL"
            return
        }

        // Validate API keys
        guard let assemblyAIKey = apiKeyManager.getAPIKey(for: .assemblyAI) else {
            errorMessage = "AssemblyAI API key not found. Please add it in Settings."
            processingState = .failed("Missing API key")
            return
        }

        guard let openAIKey = apiKeyManager.getAPIKey(for: .openAI) else {
            errorMessage = "OpenAI API key not found. Please add it in Settings."
            processingState = .failed("Missing API key")
            return
        }

        // Reset state
        transcript = nil
        summary = nil
        videoInfo = nil
        errorMessage = nil

        // Track audio URL for cleanup
        var audioURL: URL?

        do {
            // Step 1: Download video and extract audio
            processingState = .processing("Downloading video...")

            let result = try await videoService.downloadAndExtractAudio(from: urlInput)
            audioURL = result.audioURL
            let info = result.videoInfo
            videoInfo = info

            // Step 2: Transcribe audio
            processingState = .processing("Transcribing audio...")

            let assemblyAI = AssemblyAIService(apiKey: assemblyAIKey)
            var transcriptResult = try await assemblyAI.transcribeAudio(fileURL: audioURL!)

            // Step 2.5: Identify and relabel interviewee
            if let speakerLabels = transcriptResult.speakerLabels, !speakerLabels.isEmpty {
                processingState = .processing("Identifying interviewee...")

                // Get transcript preview (first 2000 characters)
                let transcriptPreview = String(transcriptResult.text.prefix(2000))

                let openAI = OpenAIService(apiKey: openAIKey)
                do {
                    if let identifiedName = try await openAI.identifyInterviewee(
                        title: info.title,
                        description: info.description,
                        transcriptPreview: transcriptPreview
                    ) {
                        // Store the interviewee name
                        intervieweeName = identifiedName

                        // Relabel speakers: find the speaker who talks the most (likely the interviewee)
                        let relabeledSpeakerLabels = relabelSpeakers(
                            speakerLabels: speakerLabels,
                            intervieweeName: identifiedName
                        )
                        transcriptResult = Transcript(
                            id: transcriptResult.id,
                            text: transcriptResult.text,
                            speakerLabels: relabeledSpeakerLabels,
                            createdAt: transcriptResult.createdAt,
                            sourceURL: urlInput,
                            title: info.title
                        )
                    }
                } catch {
                    // Log error but continue processing - identification is optional
                    print("Warning: Failed to identify interviewee: \(error.localizedDescription)")
                    // Continue without relabeling speakers
                }
            }

            // Add video info to transcript
            if transcriptResult.speakerLabels == nil {
                transcriptResult = Transcript(
                    id: transcriptResult.id,
                    text: transcriptResult.text,
                    speakerLabels: transcriptResult.speakerLabels,
                    createdAt: transcriptResult.createdAt,
                    sourceURL: urlInput,
                    title: info.title
                )
            }
            transcript = transcriptResult

            // Step 3: Summarize transcript with structured knowledge base format
            processingState = .processing("Generating structured knowledge base...")

            let openAI = OpenAIService(apiKey: openAIKey)
            let characterName = intervieweeName ?? "the subject"
            let summaryText = try await openAI.generateStructuredKnowledgeBase(
                characterName: characterName,
                fullTranscript: transcriptResult.text,
                speakerLabels: transcriptResult.speakerLabels,
                videoURL: urlInput,
                videoTitle: info.title
            )

            // Step 4: Extract dialogue examples (only from interviewee if identified)
            var dialogueExamples: [SpeakerDialogueExamples]? = nil
            if let speakerLabels = transcriptResult.speakerLabels, !speakerLabels.isEmpty, let intervieweeName = intervieweeName {
                processingState = .processing("Extracting dialogue examples...")
                // Filter to only include the interviewee's utterances
                let intervieweeUtterances = speakerLabels.filter { $0.speaker == intervieweeName }
                if !intervieweeUtterances.isEmpty {
                    dialogueExamples = try await openAI.extractDialogueExamples(from: intervieweeUtterances)
                }
            }

            summary = Summary(
                text: summaryText,
                sourceType: .video,
                sourceURL: urlInput,
                title: info.title,
                speakerDialogueExamples: dialogueExamples
            )

            // Cleanup audio file
            if let audioURL = audioURL {
                await videoService.cleanup(audioURL: audioURL)
            }

            processingState = .completed

        } catch let error as KnowledgeToolError {
            // Cleanup on error
            if let audioURL = audioURL {
                await videoService.cleanup(audioURL: audioURL)
            }
            errorMessage = error.localizedDescription
            processingState = .failed(error.localizedDescription)
        } catch {
            // Cleanup on error
            if let audioURL = audioURL {
                await videoService.cleanup(audioURL: audioURL)
            }
            errorMessage = error.localizedDescription
            processingState = .failed(error.localizedDescription)
        }
    }

    // MARK: - Process Video from File
    @MainActor
    func processVideoFromFile(_ fileURL: URL) async {
        // Validate API keys
        guard let assemblyAIKey = apiKeyManager.getAPIKey(for: .assemblyAI) else {
            errorMessage = "AssemblyAI API key not found. Please add it in Settings."
            processingState = .failed("Missing API key")
            return
        }

        guard let openAIKey = apiKeyManager.getAPIKey(for: .openAI) else {
            errorMessage = "OpenAI API key not found. Please add it in Settings."
            processingState = .failed("Missing API key")
            return
        }

        // Reset state
        transcript = nil
        summary = nil
        videoInfo = nil
        errorMessage = nil

        // Track audio URL for cleanup
        var audioURL: URL?

        do {
            // Step 1: Extract audio from video file
            processingState = .processing("Extracting audio from video...")

            audioURL = try await videoService.extractAudio(from: fileURL)
            let title = fileURL.deletingPathExtension().lastPathComponent

            // Step 2: Transcribe audio
            processingState = .processing("Transcribing audio...")

            let assemblyAI = AssemblyAIService(apiKey: assemblyAIKey)
            var transcriptResult = try await assemblyAI.transcribeAudio(fileURL: audioURL!)
            
            // Step 2.5: Identify and relabel interviewee
            if let speakerLabels = transcriptResult.speakerLabels, !speakerLabels.isEmpty {
                processingState = .processing("Identifying interviewee...")

                // Get transcript preview (first 2000 characters)
                let transcriptPreview = String(transcriptResult.text.prefix(2000))

                let openAI = OpenAIService(apiKey: openAIKey)
                do {
                    // For local files, we don't have a description, so we pass nil
                    if let identifiedName = try await openAI.identifyInterviewee(
                        title: title,
                        description: nil,
                        transcriptPreview: transcriptPreview
                    ) {
                        // Store the interviewee name
                        intervieweeName = identifiedName

                        // Relabel speakers: find the speaker who talks the most (likely the interviewee)
                        let relabeledSpeakerLabels = relabelSpeakers(
                            speakerLabels: speakerLabels,
                            intervieweeName: identifiedName
                        )
                        transcriptResult = Transcript(
                            id: transcriptResult.id,
                            text: transcriptResult.text,
                            speakerLabels: relabeledSpeakerLabels,
                            createdAt: transcriptResult.createdAt,
                            sourceURL: fileURL.path,
                            title: title
                        )
                    }
                } catch {
                    // Log error but continue processing - identification is optional
                    print("Warning: Failed to identify interviewee: \(error.localizedDescription)")
                    // Continue without relabeling speakers
                }
            }

            // Add file info to transcript
            if transcriptResult.speakerLabels == nil {
                transcriptResult = Transcript(
                    id: transcriptResult.id,
                    text: transcriptResult.text,
                    speakerLabels: transcriptResult.speakerLabels,
                    createdAt: transcriptResult.createdAt,
                    sourceURL: fileURL.path,
                    title: title
                )
            }
            transcript = transcriptResult

            // Step 3: Summarize transcript with structured knowledge base format
            processingState = .processing("Generating structured knowledge base...")

            let openAI = OpenAIService(apiKey: openAIKey)
            let characterName = intervieweeName ?? "the subject"
            let summaryText = try await openAI.generateStructuredKnowledgeBase(
                characterName: characterName,
                fullTranscript: transcriptResult.text,
                speakerLabels: transcriptResult.speakerLabels,
                videoURL: fileURL.absoluteString,
                videoTitle: title
            )

            // Step 4: Extract dialogue examples (only from interviewee if identified)
            var dialogueExamples: [SpeakerDialogueExamples]? = nil
            if let speakerLabels = transcriptResult.speakerLabels, !speakerLabels.isEmpty, let intervieweeName = intervieweeName {
                processingState = .processing("Extracting dialogue examples...")
                // Filter to only include the interviewee's utterances
                let intervieweeUtterances = speakerLabels.filter { $0.speaker == intervieweeName }
                if !intervieweeUtterances.isEmpty {
                    dialogueExamples = try await openAI.extractDialogueExamples(from: intervieweeUtterances)
                }
            }

            summary = Summary(
                text: summaryText,
                sourceType: .video,
                sourceURL: fileURL.path,
                title: title,
                speakerDialogueExamples: dialogueExamples
            )

            // Cleanup audio file
            if let audioURL = audioURL {
                await videoService.cleanup(audioURL: audioURL)
            }

            processingState = .completed

        } catch let error as KnowledgeToolError {
            // Cleanup on error
            if let audioURL = audioURL {
                await videoService.cleanup(audioURL: audioURL)
            }
            errorMessage = error.localizedDescription
            processingState = .failed(error.localizedDescription)
        } catch {
            // Cleanup on error
            if let audioURL = audioURL {
                await videoService.cleanup(audioURL: audioURL)
            }
            errorMessage = error.localizedDescription
            processingState = .failed(error.localizedDescription)
        }
    }

    // MARK: - Export Results
    func exportTranscript() -> String? {
        guard let transcript = transcript else { return nil }

        var output = ""

        if let title = transcript.title {
            output += "Title: \(title)\n"
        }

        if let sourceURL = transcript.sourceURL {
            output += "Source: \(sourceURL)\n"
        }

        output += "Date: \(transcript.createdAt.formatted())\n\n"

        if let speakerLabels = transcript.speakerLabels, !speakerLabels.isEmpty {
            output += "=== Transcript with Speaker Labels ===\n\n"
            for utterance in speakerLabels {
                output += "[\(utterance.formattedTimestamp)] \(utterance.speaker): \(utterance.text)\n\n"
            }
        } else {
            output += "=== Transcript ===\n\n"
            output += transcript.text
        }

        return output
    }

    func exportSummary() -> String? {
        guard let summary = summary else { return nil }

        var output = ""

        if let title = summary.title {
            output += "Title: \(title)\n"
        }

        if let sourceURL = summary.sourceURL {
            output += "Source: \(sourceURL)\n"
        }

        output += "Date: \(summary.createdAt.formatted())\n\n"
        output += "=== Summary ===\n\n"
        output += summary.text

        // Add dialogue examples if available
        if let dialogueExamples = summary.speakerDialogueExamples, !dialogueExamples.isEmpty {
            output += "\n\n=== Characteristic Dialogue Examples ===\n\n"
            for speakerExample in dialogueExamples {
                output += "\(speakerExample.speaker):\n"
                for (index, example) in speakerExample.examples.enumerated() {
                    output += "\(index + 1). \(example)\n"
                }
                output += "\n"
            }
        }

        return output
    }

    // MARK: - Relabel Speakers
    private func relabelSpeakers(speakerLabels: [SpeakerUtterance], intervieweeName: String) -> [SpeakerUtterance] {
        // Count total speaking time for each speaker
        var speakerTimes: [String: TimeInterval] = [:]
        for utterance in speakerLabels {
            let duration = utterance.end - utterance.start
            speakerTimes[utterance.speaker, default: 0] += duration
        }

        // Find the speaker with the most speaking time (likely the interviewee)
        guard let primarySpeaker = speakerTimes.max(by: { $0.value < $1.value })?.key else {
            return speakerLabels
        }

        // Relabel: primary speaker becomes the interviewee, others stay as Speaker B, C, etc.
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

    // MARK: - Reset
    @MainActor
    func reset() {
        urlInput = ""
        processingState = .idle
        transcript = nil
        summary = nil
        videoInfo = nil
        errorMessage = nil
        intervieweeName = nil
    }
}
