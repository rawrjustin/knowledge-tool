import Foundation

/// Metadata for a knowledge source folder
/// Stored as metadata.json in each source folder (Knowledge/sources/{uuid}/)
struct SourceMetadata: Codable, Identifiable {
    let id: UUID
    let version: Int
    let type: String                    // "youtube", "web", "text"
    let title: String                   // Human-readable: "Interview with John Smith"
    var displayName: String?            // Optional override
    let sourceUrl: String?
    let processedAt: Date
    let speaker: String?                // Identified speaker
    let duration: TimeInterval?
    let description: String?
    var includeInBrainCreation: Bool
    var uploadStatus: String
    var summaryStatus: String

    // Files present in this source folder
    struct Files: Codable {
        var transcript: String?         // "transcript.txt"
        var knowledge: String?          // "knowledge.jsonl"
        var summary: String?            // "summary.md"

        init(transcript: String? = nil, knowledge: String? = nil, summary: String? = nil) {
            self.transcript = transcript
            self.knowledge = knowledge
            self.summary = summary
        }
    }
    var files: Files

    var resolvedDisplayName: String {
        displayName ?? title
    }

    init(
        id: UUID = UUID(),
        version: Int = 1,
        type: String,
        title: String,
        displayName: String? = nil,
        sourceUrl: String? = nil,
        processedAt: Date = Date(),
        speaker: String? = nil,
        duration: TimeInterval? = nil,
        description: String? = nil,
        includeInBrainCreation: Bool = true,
        uploadStatus: String = "pending",
        summaryStatus: String = "notGenerated",
        files: Files = Files()
    ) {
        self.id = id
        self.version = version
        self.type = type
        self.title = title
        self.displayName = displayName
        self.sourceUrl = sourceUrl
        self.processedAt = processedAt
        self.speaker = speaker
        self.duration = duration
        self.description = description
        self.includeInBrainCreation = includeInBrainCreation
        self.uploadStatus = uploadStatus
        self.summaryStatus = summaryStatus
        self.files = files
    }
}
