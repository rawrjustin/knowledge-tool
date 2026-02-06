import Foundation

// MARK: - Knowledge Source Type

/// Represents the origin type of a knowledge source
enum KnowledgeSourceType: String, Codable, CaseIterable {
    case youtubeVideo = "youtube"
    case webArticle = "web"
    case manualText = "text"
    case personaExtraction = "persona"
    case research = "research"

    var displayName: String {
        switch self {
        case .youtubeVideo: return "YouTube Video"
        case .webArticle: return "Web Article"
        case .manualText: return "Manual Notes"
        case .personaExtraction: return "Persona Extraction"
        case .research: return "Research"
        }
    }

    var icon: String {
        switch self {
        case .youtubeVideo: return "play.rectangle.fill"
        case .webArticle: return "link"
        case .manualText: return "note.text"
        case .personaExtraction: return "person.text.rectangle"
        case .research: return "magnifyingglass"
        }
    }

    var color: String {
        switch self {
        case .youtubeVideo: return "red"
        case .webArticle: return "blue"
        case .manualText: return "purple"
        case .personaExtraction: return "orange"
        case .research: return "green"
        }
    }
}

// MARK: - Knowledge Upload Status

enum KnowledgeUploadStatus: String, Codable {
    case pending = "pending"
    case uploading = "uploading"
    case uploaded = "uploaded"
    case failed = "failed"

    var icon: String {
        switch self {
        case .pending: return "clock"
        case .uploading: return "arrow.up.circle"
        case .uploaded: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.circle.fill"
        }
    }

    var color: String {
        switch self {
        case .pending: return "secondary"
        case .uploading: return "blue"
        case .uploaded: return "green"
        case .failed: return "red"
        }
    }
}

// MARK: - Knowledge Entry

/// A single knowledge entry (memory) within a source
struct KnowledgeEntry: Identifiable, Codable, Hashable {
    let id: String
    let section: String
    let content: String
    let keywords: [String]

    /// The persona section this knowledge relates to (if any)
    var relatedPersonaSection: String?

    /// Source traceability - links entry to its original source
    var sourceId: UUID?

    /// Start timestamp in seconds (for video sources)
    var timestamp: TimeInterval?

    /// End timestamp in seconds (for video sources)
    var endTimestamp: TimeInterval?

    /// Excerpt from the source that this entry was derived from
    var sourceExcerpt: String?

    /// Formatted timestamp range for display (e.g., "5:30 - 15:30")
    var formattedTimestamp: String? {
        guard let start = timestamp else { return nil }
        let startFormatted = formatTime(start)

        if let end = endTimestamp {
            let endFormatted = formatTime(end)
            return "\(startFormatted) - \(endFormatted)"
        }
        return startFormatted
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let totalSeconds = Int(seconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }

    /// Parse timestamp range from entry ID (e.g., "t5-15" -> (300, 900))
    static func parseTimestampFromId(_ id: String) -> (start: TimeInterval, end: TimeInterval)? {
        // Match pattern like "t5-15" or "t0-10"
        let pattern = "t(\\d+)-(\\d+)"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: id, range: NSRange(id.startIndex..., in: id)),
              match.numberOfRanges == 3 else {
            return nil
        }

        guard let startRange = Range(match.range(at: 1), in: id),
              let endRange = Range(match.range(at: 2), in: id),
              let startMinutes = Double(id[startRange]),
              let endMinutes = Double(id[endRange]) else {
            return nil
        }

        return (startMinutes * 60, endMinutes * 60)
    }
}

// MARK: - Knowledge Source

/// Status of summary generation
enum SummaryStatus: String, Codable {
    case notGenerated
    case generating
    case generated
    case failed
}

/// Represents a source of knowledge for a character with full provenance tracking
struct KnowledgeSource: Identifiable, Codable, Equatable {
    // Custom Equatable implementation needed since SourceSummary is complex
    static func == (lhs: KnowledgeSource, rhs: KnowledgeSource) -> Bool {
        lhs.id == rhs.id
    }
    let id: UUID
    let characterId: UUID
    let sourceType: KnowledgeSourceType
    let title: String
    let sourceURL: String?              // Original URL (YouTube, web link)
    let sourceDescription: String?       // Brief description of the source
    let createdAt: Date
    var modifiedAt: Date

    // Content
    var entries: [KnowledgeEntry]
    var rawContent: String?              // Original transcript/text if available

    // Transcript-specific data
    var rawTranscript: String?           // Raw transcript text for LLM context
    var speakerUtterances: [SpeakerUtterance]?  // Diarized speaker utterances
    var identifiedSpeaker: String?       // The identified primary speaker

    // Brain creation settings
    var includeInBrainCreation: Bool = true  // Whether to use this source for brain creation

    // File reference
    var knowledgeFileName: String        // The .jsonl file this maps to

    // RAG status
    var uploadStatus: KnowledgeUploadStatus
    var uploadedAt: Date?
    var vectorCount: Int?

    // Summary
    var summary: SourceSummary?
    var summaryStatus: SummaryStatus = .notGenerated

    // Computed properties
    var entryCount: Int { entries.count }

    var totalWordCount: Int {
        entries.reduce(0) { total, entry in
            total + entry.content.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count
        }
    }

    var relatedPersonaSections: [String] {
        Array(Set(entries.compactMap { $0.relatedPersonaSection })).sorted()
    }

    init(
        id: UUID = UUID(),
        characterId: UUID,
        sourceType: KnowledgeSourceType,
        title: String,
        sourceURL: String? = nil,
        sourceDescription: String? = nil,
        createdAt: Date = Date(),
        modifiedAt: Date = Date(),
        entries: [KnowledgeEntry] = [],
        rawContent: String? = nil,
        rawTranscript: String? = nil,
        speakerUtterances: [SpeakerUtterance]? = nil,
        identifiedSpeaker: String? = nil,
        includeInBrainCreation: Bool = true,
        knowledgeFileName: String,
        uploadStatus: KnowledgeUploadStatus = .pending,
        uploadedAt: Date? = nil,
        vectorCount: Int? = nil,
        summary: SourceSummary? = nil,
        summaryStatus: SummaryStatus = .notGenerated
    ) {
        self.id = id
        self.characterId = characterId
        self.sourceType = sourceType
        self.title = title
        self.sourceURL = sourceURL
        self.sourceDescription = sourceDescription
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.entries = entries
        self.rawContent = rawContent
        self.rawTranscript = rawTranscript
        self.speakerUtterances = speakerUtterances
        self.identifiedSpeaker = identifiedSpeaker
        self.includeInBrainCreation = includeInBrainCreation
        self.knowledgeFileName = knowledgeFileName
        self.uploadStatus = uploadStatus
        self.uploadedAt = uploadedAt
        self.vectorCount = vectorCount
        self.summary = summary
        self.summaryStatus = summaryStatus
    }
}

// MARK: - Knowledge Source Parsing

extension KnowledgeSource {
    /// Parse a KnowledgeFile into a KnowledgeSource with entries
    static func from(knowledgeFile: KnowledgeFile, characterId: UUID) -> KnowledgeSource {
        // Determine source type from filename
        let sourceType = detectSourceType(from: knowledgeFile.fileName)

        // Parse title from filename
        let title = parseTitle(from: knowledgeFile.fileName)

        // Parse entries based on file type
        let entries: [KnowledgeEntry]
        let isJSONL = knowledgeFile.fileName.lowercased().hasSuffix(".jsonl") ||
                      knowledgeFile.fileName.lowercased().hasSuffix(".json")

        if isJSONL {
            // Parse JSONL entries
            entries = parseEntries(from: knowledgeFile.content)
        } else {
            // For plain text files (.txt, .md, etc.), create entries from content sections
            entries = parseTextContent(from: knowledgeFile.content, fileName: knowledgeFile.fileName)
        }

        // Determine upload status (check if filename suggests it's been processed)
        let uploadStatus: KnowledgeUploadStatus = knowledgeFile.fileName.contains("_uploaded") ? .uploaded : .pending

        return KnowledgeSource(
            characterId: characterId,
            sourceType: sourceType,
            title: title,
            createdAt: knowledgeFile.createdAt,
            modifiedAt: knowledgeFile.modifiedAt,
            entries: entries,
            rawContent: knowledgeFile.content,
            knowledgeFileName: knowledgeFile.fileName,
            uploadStatus: uploadStatus
        )
    }

    /// Parse plain text content into knowledge entries
    /// Splits by sections (markdown headers) or treats entire content as one entry
    private static func parseTextContent(from content: String, fileName: String) -> [KnowledgeEntry] {
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }

        // Check for markdown sections (## headers)
        let sections = content.components(separatedBy: "\n## ")

        if sections.count > 1 {
            // Multiple sections - create an entry for each
            var entries: [KnowledgeEntry] = []
            for (index, section) in sections.enumerated() {
                let trimmedSection = section.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedSection.isEmpty else { continue }

                // First section might have # header or content before first ##
                let sectionTitle: String
                let sectionContent: String

                if index == 0 {
                    // Handle content before first ##
                    if let firstNewline = trimmedSection.firstIndex(of: "\n") {
                        let firstLine = String(trimmedSection[..<firstNewline]).trimmingCharacters(in: .whitespaces)
                        if firstLine.hasPrefix("#") {
                            sectionTitle = firstLine.replacingOccurrences(of: "#", with: "").trimmingCharacters(in: .whitespaces)
                            sectionContent = String(trimmedSection[trimmedSection.index(after: firstNewline)...])
                        } else {
                            sectionTitle = "Introduction"
                            sectionContent = trimmedSection
                        }
                    } else {
                        sectionTitle = "Introduction"
                        sectionContent = trimmedSection
                    }
                } else {
                    // Regular ## section
                    if let firstNewline = trimmedSection.firstIndex(of: "\n") {
                        sectionTitle = String(trimmedSection[..<firstNewline]).trimmingCharacters(in: .whitespaces)
                        sectionContent = String(trimmedSection[trimmedSection.index(after: firstNewline)...])
                    } else {
                        sectionTitle = trimmedSection
                        sectionContent = ""
                    }
                }

                guard !sectionContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }

                let words = sectionContent.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
                let keywords = extractKeywords(from: sectionContent)

                entries.append(KnowledgeEntry(
                    id: "text-\(index)",
                    section: sectionTitle,
                    content: sectionContent.trimmingCharacters(in: .whitespacesAndNewlines),
                    keywords: keywords
                ))
            }
            return entries
        } else {
            // Single block of text - create one entry representing the whole content
            let words = content.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
            let keywords = extractKeywords(from: content)

            return [KnowledgeEntry(
                id: "text-full",
                section: fileName.replacingOccurrences(of: ".txt", with: "").replacingOccurrences(of: "_", with: " "),
                content: content.trimmingCharacters(in: .whitespacesAndNewlines),
                keywords: keywords
            )]
        }
    }

    /// Extract simple keywords from text
    private static func extractKeywords(from text: String) -> [String] {
        // Simple keyword extraction: find capitalized words that appear multiple times
        let words = text.components(separatedBy: .whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
            .filter { !$0.isEmpty && $0.count > 3 }

        let wordCounts = Dictionary(words.map { ($0.lowercased(), 1) }, uniquingKeysWith: +)
        return wordCounts
            .filter { $0.value >= 2 && $0.key.count > 4 }
            .sorted { $0.value > $1.value }
            .prefix(10)
            .map { $0.key }
    }

    private static func detectSourceType(from fileName: String) -> KnowledgeSourceType {
        let lowercased = fileName.lowercased()

        if lowercased.contains("youtube") || lowercased.contains("video") || lowercased.contains("transcript") {
            return .youtubeVideo
        } else if lowercased.contains("article") || lowercased.contains("web") || lowercased.contains("link") {
            return .webArticle
        } else if lowercased.contains("character_memories") || lowercased.contains("persona") {
            return .personaExtraction
        } else if lowercased.contains("research") || lowercased.contains("perplexity") {
            return .research
        } else {
            return .manualText
        }
    }

    private static func parseTitle(from fileName: String) -> String {
        var title = fileName
            .replacingOccurrences(of: ".jsonl", with: "")
            .replacingOccurrences(of: ".json", with: "")
            .replacingOccurrences(of: "_memories", with: "")
            .replacingOccurrences(of: "_augmentation", with: "")
            .replacingOccurrences(of: "structured_knowledge_base", with: "Video Knowledge")
            .replacingOccurrences(of: "character_memories", with: "Persona Memories")
            .replacingOccurrences(of: "_", with: " ")

        // Capitalize words
        title = title.split(separator: " ").map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }.joined(separator: " ")

        return title
    }

    private static func parseEntries(from content: String) -> [KnowledgeEntry] {
        let lines = content.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        return lines.compactMap { line -> KnowledgeEntry? in
            guard let data = line.data(using: .utf8) else { return nil }

            do {
                let decoder = JSONDecoder()
                let entry = try decoder.decode(KnowledgeEntry.self, from: data)
                return entry
            } catch {
                // Try parsing as a simpler format
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let id = json["id"] as? String,
                   let content = json["content"] as? String {
                    return KnowledgeEntry(
                        id: id,
                        section: json["section"] as? String ?? "General",
                        content: content,
                        keywords: json["keywords"] as? [String] ?? []
                    )
                }
                return nil
            }
        }
    }
}

// MARK: - Source Metadata Integration

extension KnowledgeSource {
    /// Create a KnowledgeSource from source folder metadata
    static func from(
        metadata: SourceMetadata,
        characterId: UUID,
        transcriptContent: String?,
        knowledgeContent: String?
    ) -> KnowledgeSource {
        // Parse knowledge entries from content
        var entries: [KnowledgeEntry] = []
        if let content = knowledgeContent {
            entries = parseEntries(from: content)
        }

        // Determine source type
        let sourceType: KnowledgeSourceType
        switch metadata.type.lowercased() {
        case "youtube":
            sourceType = .youtubeVideo
        case "web":
            sourceType = .webArticle
        case "text":
            sourceType = .manualText
        case "persona":
            sourceType = .personaExtraction
        case "research":
            sourceType = .research
        default:
            sourceType = .manualText
        }

        // Map upload status
        let uploadStatus: KnowledgeUploadStatus
        switch metadata.uploadStatus.lowercased() {
        case "uploaded":
            uploadStatus = .uploaded
        case "uploading":
            uploadStatus = .uploading
        case "failed":
            uploadStatus = .failed
        default:
            uploadStatus = .pending
        }

        // Map summary status
        let summaryStatus: SummaryStatus
        switch metadata.summaryStatus.lowercased() {
        case "generated":
            summaryStatus = .generated
        case "generating":
            summaryStatus = .generating
        case "failed":
            summaryStatus = .failed
        default:
            summaryStatus = .notGenerated
        }

        return KnowledgeSource(
            id: metadata.id,
            characterId: characterId,
            sourceType: sourceType,
            title: metadata.resolvedDisplayName,
            sourceURL: metadata.sourceUrl,
            sourceDescription: metadata.description,
            createdAt: metadata.processedAt,
            modifiedAt: metadata.processedAt,
            entries: entries,
            rawContent: transcriptContent,
            rawTranscript: transcriptContent,
            speakerUtterances: nil,
            identifiedSpeaker: metadata.speaker,
            includeInBrainCreation: metadata.includeInBrainCreation,
            knowledgeFileName: metadata.files.knowledge ?? "knowledge.jsonl",
            uploadStatus: uploadStatus,
            uploadedAt: nil,
            vectorCount: nil,
            summary: nil,
            summaryStatus: summaryStatus
        )
    }
}

// MARK: - Character Extension for Knowledge Sources

extension Character {
    /// Convert knowledge files to knowledge sources
    var knowledgeSources: [KnowledgeSource] {
        knowledgeFiles.map { KnowledgeSource.from(knowledgeFile: $0, characterId: id) }
    }

    /// Get knowledge sources grouped by type
    var knowledgeSourcesByType: [KnowledgeSourceType: [KnowledgeSource]] {
        Dictionary(grouping: knowledgeSources, by: { $0.sourceType })
    }

    /// Get all persona sections that have knowledge backing
    var sectionsWithKnowledge: [String: [KnowledgeSource]] {
        var result: [String: [KnowledgeSource]] = [:]

        for source in knowledgeSources {
            for section in source.relatedPersonaSections {
                if result[section] == nil {
                    result[section] = []
                }
                result[section]?.append(source)
            }
        }

        return result
    }

    /// Total number of knowledge entries across all sources
    var totalKnowledgeEntries: Int {
        knowledgeSources.reduce(0) { $0 + $1.entryCount }
    }
}
