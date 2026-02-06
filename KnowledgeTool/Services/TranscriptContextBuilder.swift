import Foundation

// MARK: - Transcript Context Builder

/// Service for building transcript context for brain creation with token limit awareness
actor TranscriptContextBuilder {
    // Approximate tokens per character (conservative estimate)
    private let tokensPerCharacter: Double = 0.25

    // Default max tokens for context
    private let defaultMaxTokens: Int = 120000

    // MARK: - Build Context

    /// Build context from multiple transcripts, respecting token limits
    /// - Parameters:
    ///   - sources: Array of knowledge sources with transcripts
    ///   - maxTokens: Maximum tokens allowed in context
    /// - Returns: Combined context string and metadata
    func buildContext(
        from sources: [KnowledgeSource],
        maxTokens: Int? = nil
    ) -> TranscriptContext {
        let limit = maxTokens ?? defaultMaxTokens
        let maxChars = Int(Double(limit) / tokensPerCharacter)

        var combinedText = ""
        var includedSources: [UUID] = []
        var truncatedSources: [UUID] = []

        for source in sources {
            guard source.includeInBrainCreation else { continue }

            // Get transcript content
            let transcript: String
            if let raw = source.rawTranscript, !raw.isEmpty {
                transcript = raw
            } else if let content = source.rawContent, !content.isEmpty {
                transcript = content
            } else {
                // Build from entries
                transcript = source.entries.map { $0.content }.joined(separator: "\n\n")
            }

            guard !transcript.isEmpty else { continue }

            // Format with source header
            let header = "\n\n--- SOURCE: \(source.title) ---\n\n"
            let remainingChars = maxChars - combinedText.count - header.count

            if remainingChars <= 0 {
                break
            }

            if transcript.count <= remainingChars {
                combinedText += header + transcript
                includedSources.append(source.id)
            } else {
                // Truncate this transcript
                let truncated = String(transcript.prefix(remainingChars - 50)) + "\n\n[TRUNCATED...]"
                combinedText += header + truncated
                includedSources.append(source.id)
                truncatedSources.append(source.id)
            }
        }

        return TranscriptContext(
            content: combinedText,
            includedSourceIds: includedSources,
            truncatedSourceIds: truncatedSources,
            approximateTokens: Int(Double(combinedText.count) * tokensPerCharacter)
        )
    }

    /// Build context from brain sources (for multi-source input)
    /// - Parameters:
    ///   - sources: Array of brain sources
    ///   - maxTokens: Maximum tokens allowed
    /// - Returns: Combined context string and metadata
    func buildContext(
        from sources: [BrainSource],
        maxTokens: Int? = nil
    ) -> TranscriptContext {
        let limit = maxTokens ?? defaultMaxTokens
        let maxChars = Int(Double(limit) / tokensPerCharacter)

        var combinedText = ""
        var includedSources: [UUID] = []
        var truncatedSources: [UUID] = []

        for source in sources where source.processingStatus != .failed {
            let content = source.content

            guard !content.isEmpty else { continue }

            // Format with source header
            let header = "\n\n--- SOURCE: \(source.label) (\(source.sourceType.displayName)) ---\n\n"
            let remainingChars = maxChars - combinedText.count - header.count

            if remainingChars <= 0 {
                break
            }

            if content.count <= remainingChars {
                combinedText += header + content
                includedSources.append(source.id)
            } else {
                // Truncate this content
                let truncated = String(content.prefix(remainingChars - 50)) + "\n\n[TRUNCATED...]"
                combinedText += header + truncated
                includedSources.append(source.id)
                truncatedSources.append(source.id)
            }
        }

        return TranscriptContext(
            content: combinedText,
            includedSourceIds: includedSources,
            truncatedSourceIds: truncatedSources,
            approximateTokens: Int(Double(combinedText.count) * tokensPerCharacter)
        )
    }

    // MARK: - Chunk Transcript

    /// Chunk a long transcript into smaller segments for processing
    /// - Parameters:
    ///   - transcript: The full transcript
    ///   - chunkSize: Target size for each chunk in characters
    ///   - overlap: Overlap between chunks in characters
    /// - Returns: Array of transcript chunks
    nonisolated func chunkTranscript(
        _ transcript: String,
        chunkSize: Int = 8000,
        overlap: Int = 500
    ) -> [TranscriptChunk] {
        guard transcript.count > chunkSize else {
            return [TranscriptChunk(
                index: 0,
                content: transcript,
                startPosition: 0,
                endPosition: transcript.count
            )]
        }

        var chunks: [TranscriptChunk] = []
        var startIndex = 0
        var chunkIndex = 0

        while startIndex < transcript.count {
            let endIndex = min(startIndex + chunkSize, transcript.count)
            let startStringIndex = transcript.index(transcript.startIndex, offsetBy: startIndex)
            let endStringIndex = transcript.index(transcript.startIndex, offsetBy: endIndex)

            // Try to find a sentence boundary near the end
            let chunkContent: String
            if endIndex < transcript.count {
                let searchRange = transcript[startStringIndex..<endStringIndex]
                if let lastPeriod = searchRange.lastIndex(of: ".") {
                    let adjustedEnd = transcript.index(after: lastPeriod)
                    chunkContent = String(transcript[startStringIndex..<adjustedEnd])
                } else {
                    chunkContent = String(transcript[startStringIndex..<endStringIndex])
                }
            } else {
                chunkContent = String(transcript[startStringIndex..<endStringIndex])
            }

            chunks.append(TranscriptChunk(
                index: chunkIndex,
                content: chunkContent,
                startPosition: startIndex,
                endPosition: startIndex + chunkContent.count
            ))

            // Move to next chunk with overlap
            startIndex = startIndex + chunkContent.count - overlap
            chunkIndex += 1
        }

        return chunks
    }

    // MARK: - Format with Speaker Labels

    /// Format a transcript with speaker labels
    /// - Parameters:
    ///   - utterances: Array of speaker utterances
    ///   - primarySpeaker: Optional filter to include only one speaker
    /// - Returns: Formatted transcript string
    nonisolated func formatWithSpeakerLabels(
        _ utterances: [SpeakerUtterance],
        primarySpeaker: String? = nil
    ) -> String {
        let filtered = primarySpeaker != nil
            ? utterances.filter { $0.speaker == primarySpeaker }
            : utterances

        return filtered.map { utterance in
            let timestamp = formatTimestamp(utterance.start)
            return "[\(timestamp)] \(utterance.speaker): \(utterance.text)"
        }.joined(separator: "\n\n")
    }

    private nonisolated func formatTimestamp(_ seconds: TimeInterval) -> String {
        let totalSeconds = Int(seconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }
}

// MARK: - Supporting Types

/// Result of building transcript context
struct TranscriptContext {
    let content: String
    let includedSourceIds: [UUID]
    let truncatedSourceIds: [UUID]
    let approximateTokens: Int

    var isEmpty: Bool { content.isEmpty }
    var wasTruncated: Bool { !truncatedSourceIds.isEmpty }
}

/// A chunk of a larger transcript
struct TranscriptChunk {
    let index: Int
    let content: String
    let startPosition: Int
    let endPosition: Int
}
