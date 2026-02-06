import Foundation

// MARK: - Dialog Example

/// A single dialog example representing how a character speaks in a specific situation
struct DialogExample: Identifiable, Codable, Hashable {
    let id: UUID
    let categoryId: String        // Reference to DialogCategory
    let scenario: String          // Specific scenario description
    let dialog: String            // The actual dialog
    let source: DialogSource      // generated, transcript, researched
    let keywords: [String]        // For RAG retrieval
    let createdAt: Date

    // Source traceability
    var sourceId: UUID?           // Link to KnowledgeSource if from transcript
    var sourceTimestamp: TimeInterval?  // Timestamp in source video

    // Animation and emotion markers
    var animationMarkers: [AnimationMarker]
    var emotion: EmotionTag?
    var intensity: Double?        // 0.0 to 1.0

    init(
        id: UUID = UUID(),
        categoryId: String,
        scenario: String = "",
        dialog: String,
        source: DialogSource,
        keywords: [String] = [],
        createdAt: Date = Date(),
        sourceId: UUID? = nil,
        sourceTimestamp: TimeInterval? = nil,
        animationMarkers: [AnimationMarker] = [],
        emotion: EmotionTag? = nil,
        intensity: Double? = nil
    ) {
        self.id = id
        self.categoryId = categoryId
        self.scenario = scenario
        self.dialog = dialog
        self.source = source
        self.keywords = keywords
        self.createdAt = createdAt
        self.sourceId = sourceId
        self.sourceTimestamp = sourceTimestamp
        self.animationMarkers = animationMarkers
        self.emotion = emotion
        self.intensity = intensity
    }

    /// Formatted timestamp for display
    var formattedTimestamp: String? {
        guard let seconds = sourceTimestamp else { return nil }
        let totalSeconds = Int(seconds)
        let minutes = totalSeconds / 60
        let secs = totalSeconds % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}

// MARK: - Dialog Source

/// The origin of a dialog example
enum DialogSource: String, Codable, CaseIterable {
    case generated    // AI-generated synthetic
    case transcript   // Extracted from video transcript
    case researched   // From Perplexity research (real quotes)
    case userCreated  // Manually created by user

    var displayName: String {
        switch self {
        case .generated: return "AI Generated"
        case .transcript: return "From Transcript"
        case .researched: return "Researched"
        case .userCreated: return "User Created"
        }
    }

    var icon: String {
        switch self {
        case .generated: return "sparkles"
        case .transcript: return "text.quote"
        case .researched: return "magnifyingglass"
        case .userCreated: return "person.fill"
        }
    }
}

// MARK: - Dialog Category

/// Categories for dialog examples - conversational situations
struct DialogCategory: Identifiable, Codable, Hashable {
    let id: String
    let name: String              // "Greetings", "Moderation Redirects", etc.
    let description: String       // What this category captures
    let suggestedCount: Int       // Target number of examples
    let contextPrompt: String     // Generation guidance

    init(
        id: String,
        name: String,
        description: String,
        suggestedCount: Int,
        contextPrompt: String
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.suggestedCount = suggestedCount
        self.contextPrompt = contextPrompt
    }
}

// MARK: - Dialog Generation Config

/// Configuration for dialog example generation
struct DialogGenerationConfig: Codable {
    var selectedCategoryIds: [String]
    var toneGuidance: String
    var styleNotes: String
    var targetTotalExamples: Int  // Default: 30 (min 100 for complete set)
    var useTranscripts: Bool
    var researchQuotes: Bool

    init(
        selectedCategoryIds: [String] = [],
        toneGuidance: String = "",
        styleNotes: String = "",
        targetTotalExamples: Int = 30,
        useTranscripts: Bool = true,
        researchQuotes: Bool = true
    ) {
        self.selectedCategoryIds = selectedCategoryIds
        self.toneGuidance = toneGuidance
        self.styleNotes = styleNotes
        self.targetTotalExamples = targetTotalExamples
        self.useTranscripts = useTranscripts
        self.researchQuotes = researchQuotes
    }

    /// Default configuration with core categories selected
    static var `default`: DialogGenerationConfig {
        DialogGenerationConfig(
            selectedCategoryIds: ["greetings", "goodbyes", "moderation_redirects", "apologies", "boredom", "follow_up_questions", "humor"],
            targetTotalExamples: 30,
            useTranscripts: true,
            researchQuotes: true
        )
    }
}
