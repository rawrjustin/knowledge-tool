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

        do {
            // Step 1: Download video and extract audio
            processingState = .processing("Downloading video...")

            let (audioURL, info) = try await videoService.downloadAndExtractAudio(from: urlInput)
            videoInfo = info

            // Step 2: Transcribe audio
            processingState = .processing("Transcribing audio...")

            let assemblyAI = AssemblyAIService(apiKey: assemblyAIKey)
            var transcriptResult = try await assemblyAI.transcribeAudio(fileURL: audioURL)

            // Add video info to transcript
            transcriptResult = Transcript(
                id: transcriptResult.id,
                text: transcriptResult.text,
                speakerLabels: transcriptResult.speakerLabels,
                createdAt: transcriptResult.createdAt,
                sourceURL: urlInput,
                title: info.title
            )
            transcript = transcriptResult

            // Step 3: Summarize transcript
            processingState = .processing("Generating summary...")

            let openAI = OpenAIService(apiKey: openAIKey)
            let summaryText = try await openAI.summarize(text: transcriptResult.text, contentType: .video)

            summary = Summary(
                text: summaryText,
                sourceType: .video,
                sourceURL: urlInput,
                title: info.title
            )

            // Cleanup audio file
            await videoService.cleanup(audioURL: audioURL)

            processingState = .completed

        } catch let error as KnowledgeToolError {
            errorMessage = error.localizedDescription
            processingState = .failed(error.localizedDescription)
        } catch {
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

        do {
            // Step 1: Extract audio from video file
            processingState = .processing("Extracting audio from video...")

            let audioURL = try await videoService.extractAudio(from: fileURL)
            let title = fileURL.deletingPathExtension().lastPathComponent

            // Step 2: Transcribe audio
            processingState = .processing("Transcribing audio...")

            let assemblyAI = AssemblyAIService(apiKey: assemblyAIKey)
            var transcriptResult = try await assemblyAI.transcribeAudio(fileURL: audioURL)

            // Add file info to transcript
            transcriptResult = Transcript(
                id: transcriptResult.id,
                text: transcriptResult.text,
                speakerLabels: transcriptResult.speakerLabels,
                createdAt: transcriptResult.createdAt,
                sourceURL: fileURL.path,
                title: title
            )
            transcript = transcriptResult

            // Step 3: Summarize transcript
            processingState = .processing("Generating summary...")

            let openAI = OpenAIService(apiKey: openAIKey)
            let summaryText = try await openAI.summarize(text: transcriptResult.text, contentType: .video)

            summary = Summary(
                text: summaryText,
                sourceType: .video,
                sourceURL: fileURL.path,
                title: title
            )

            // Cleanup audio file
            await videoService.cleanup(audioURL: audioURL)

            processingState = .completed

        } catch let error as KnowledgeToolError {
            errorMessage = error.localizedDescription
            processingState = .failed(error.localizedDescription)
        } catch {
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

        return output
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
    }
}
