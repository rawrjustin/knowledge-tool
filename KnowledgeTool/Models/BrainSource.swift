import Foundation

// MARK: - Brain Source Type

/// Types of sources that can be queued for brain augmentation
enum BrainSourceType: String, Codable, CaseIterable {
    case youtubeVideo = "youtube"
    case rawTranscript = "transcript"
    case freeformText = "text"
    case webLink = "link"

    var displayName: String {
        switch self {
        case .youtubeVideo: return "YouTube Video"
        case .rawTranscript: return "Raw Transcript"
        case .freeformText: return "Freeform Text"
        case .webLink: return "Web Link"
        }
    }

    var icon: String {
        switch self {
        case .youtubeVideo: return "play.rectangle.fill"
        case .rawTranscript: return "text.quote"
        case .freeformText: return "doc.text.fill"
        case .webLink: return "link"
        }
    }

    var placeholder: String {
        switch self {
        case .youtubeVideo: return "https://www.youtube.com/watch?v=..."
        case .rawTranscript: return "Paste transcript content here..."
        case .freeformText: return "Enter text content here..."
        case .webLink: return "https://example.com/article..."
        }
    }

    var color: String {
        switch self {
        case .youtubeVideo: return "red"
        case .rawTranscript: return "purple"
        case .freeformText: return "blue"
        case .webLink: return "green"
        }
    }
}

// MARK: - Processing Status

/// Status of a source being processed
enum BrainSourceProcessingStatus: String, Codable {
    case pending
    case processing
    case completed
    case failed

    var icon: String {
        switch self {
        case .pending: return "clock"
        case .processing: return "arrow.clockwise"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.circle.fill"
        }
    }

    var color: String {
        switch self {
        case .pending: return "secondary"
        case .processing: return "blue"
        case .completed: return "green"
        case .failed: return "red"
        }
    }
}

// MARK: - Brain Source

/// Represents a queued source for brain augmentation
struct BrainSource: Identifiable, Codable {
    let id: UUID
    var sourceType: BrainSourceType
    var content: String              // URL or text content
    var label: String                // User-provided label
    var processingStatus: BrainSourceProcessingStatus
    var result: AugmentationAnalysisResultData?
    var error: String?
    var addedAt: Date

    init(
        id: UUID = UUID(),
        sourceType: BrainSourceType,
        content: String,
        label: String,
        processingStatus: BrainSourceProcessingStatus = .pending,
        result: AugmentationAnalysisResultData? = nil,
        error: String? = nil,
        addedAt: Date = Date()
    ) {
        self.id = id
        self.sourceType = sourceType
        self.content = content
        self.label = label
        self.processingStatus = processingStatus
        self.result = result
        self.error = error
        self.addedAt = addedAt
    }

    /// Validates the source content based on type
    var isValid: Bool {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        switch sourceType {
        case .youtubeVideo:
            return trimmed.contains("youtube.com") || trimmed.contains("youtu.be")
        case .webLink:
            return URL(string: trimmed)?.scheme?.hasPrefix("http") ?? false
        case .rawTranscript, .freeformText:
            return trimmed.count >= 50  // Require some minimum content
        }
    }

    var validationMessage: String? {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            return "Content is required"
        }

        switch sourceType {
        case .youtubeVideo:
            if !isValid { return "Enter a valid YouTube URL" }
        case .webLink:
            if !isValid { return "Enter a valid URL (http:// or https://)" }
        case .rawTranscript, .freeformText:
            if trimmed.count < 50 { return "Enter at least 50 characters" }
        }

        return nil
    }
}

// MARK: - Augmentation Analysis Result Data (Codable version)

/// Codable version of AugmentationAnalysisResult for storage in BrainSource
struct AugmentationAnalysisResultData: Codable {
    let sourceType: String
    let sourceTitle: String
    let sourceSummary: String
    let augmentationCount: Int
    let ragEntryCount: Int
    let processedAt: Date

    init(from result: AugmentationAnalysisResult) {
        self.sourceType = result.sourceType.rawValue
        self.sourceTitle = result.sourceTitle
        self.sourceSummary = result.sourceSummary
        self.augmentationCount = result.augmentations.count
        self.ragEntryCount = result.ragEntries.count
        self.processedAt = result.processedAt
    }
}

// MARK: - Source Contribution

/// Tracks what came from a specific source in merged results
struct SourceContribution: Codable {
    let sourceId: UUID
    let sourceLabel: String
    let augmentationIds: [UUID]
    let ragEntryIds: [String]
    let processedAt: Date
}

// MARK: - Merged Augmentation Result

/// Result of merging multiple source analyses with deduplication
struct MergedAugmentationResult {
    var allAugmentations: [PersonaAugmentation]
    var allRagEntries: [AugmentationKnowledgeEntry]
    var sourceContributions: [UUID: SourceContribution]
    var duplicatesRemoved: Int

    init() {
        self.allAugmentations = []
        self.allRagEntries = []
        self.sourceContributions = [:]
        self.duplicatesRemoved = 0
    }

    init(
        allAugmentations: [PersonaAugmentation],
        allRagEntries: [AugmentationKnowledgeEntry],
        sourceContributions: [UUID: SourceContribution],
        duplicatesRemoved: Int
    ) {
        self.allAugmentations = allAugmentations
        self.allRagEntries = allRagEntries
        self.sourceContributions = sourceContributions
        self.duplicatesRemoved = duplicatesRemoved
    }

    var totalAugmentations: Int { allAugmentations.count }
    var totalRagEntries: Int { allRagEntries.count }
    var totalSources: Int { sourceContributions.count }
}
