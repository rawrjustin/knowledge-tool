import Foundation

// MARK: - Processing State
enum ProcessingState: Equatable {
    case idle
    case processing(String)
    case completed
    case failed(String)

    var isProcessing: Bool {
        if case .processing = self { return true }
        return false
    }
}

// MARK: - Content Type
enum ContentType: String, Codable, CaseIterable, Identifiable {
    case video = "Video"
    case article = "Article"
    case textSnippet = "Text Snippet"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .video: return "video.fill"
        case .article: return "doc.text.fill"
        case .textSnippet: return "text.quote"
        }
    }
}

// MARK: - Transcript
struct Transcript: Identifiable, Codable {
    let id: UUID
    let text: String
    let speakerLabels: [SpeakerUtterance]?
    let createdAt: Date
    let sourceURL: String?
    let title: String?

    init(
        id: UUID = UUID(),
        text: String,
        speakerLabels: [SpeakerUtterance]? = nil,
        createdAt: Date = Date(),
        sourceURL: String? = nil,
        title: String? = nil
    ) {
        self.id = id
        self.text = text
        self.speakerLabels = speakerLabels
        self.createdAt = createdAt
        self.sourceURL = sourceURL
        self.title = title
    }
}

// MARK: - Speaker Utterance
struct SpeakerUtterance: Identifiable, Codable {
    let id: UUID
    let speaker: String
    let text: String
    let start: TimeInterval
    let end: TimeInterval

    init(
        id: UUID = UUID(),
        speaker: String,
        text: String,
        start: TimeInterval,
        end: TimeInterval
    ) {
        self.id = id
        self.speaker = speaker
        self.text = text
        self.start = start
        self.end = end
    }

    var formattedTimestamp: String {
        "\(formatTime(start)) - \(formatTime(end))"
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, secs)
    }
}

// MARK: - Summary
struct Summary: Identifiable, Codable {
    let id: UUID
    let text: String
    let createdAt: Date
    let sourceType: ContentType
    let sourceURL: String?
    let title: String?

    init(
        id: UUID = UUID(),
        text: String,
        createdAt: Date = Date(),
        sourceType: ContentType,
        sourceURL: String? = nil,
        title: String? = nil
    ) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
        self.sourceType = sourceType
        self.sourceURL = sourceURL
        self.title = title
    }
}

// MARK: - Video Info
struct VideoInfo: Codable {
    let id: String
    let title: String
    let duration: TimeInterval?
    let thumbnailURL: String?

    init(id: String, title: String, duration: TimeInterval? = nil, thumbnailURL: String? = nil) {
        self.id = id
        self.title = title
        self.duration = duration
        self.thumbnailURL = thumbnailURL
    }
}

// MARK: - Article Info
struct ArticleInfo: Codable {
    let url: String
    let title: String?
    let content: String
    let publishedDate: Date?

    init(url: String, title: String? = nil, content: String, publishedDate: Date? = nil) {
        self.url = url
        self.title = title
        self.content = content
        self.publishedDate = publishedDate
    }
}

// MARK: - Knowledge Tool Error
enum KnowledgeToolError: LocalizedError {
    case invalidURL
    case networkError(Error)
    case apiError(String)
    case fileError(String)
    case unsupportedFormat
    case missingAPIKey(String)
    case transcriptionFailed(String)
    case summarizationFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL provided"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .apiError(let message):
            return "API error: \(message)"
        case .fileError(let message):
            return "File error: \(message)"
        case .unsupportedFormat:
            return "Unsupported file format"
        case .missingAPIKey(let service):
            return "Missing API key for \(service). Please add it in Settings."
        case .transcriptionFailed(let reason):
            return "Transcription failed: \(reason)"
        case .summarizationFailed(let reason):
            return "Summarization failed: \(reason)"
        }
    }
}
