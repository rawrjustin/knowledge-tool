import Foundation

// MARK: - Animation Marker Type

/// Types of animation markers that can be embedded in dialogue
enum AnimationMarkerType: String, Codable, CaseIterable {
    case laugh
    case smile
    case pause
    case emphasis
    case gesture
    case eyeroll
    case nod
    case shrug
    case sigh
    case think
    case surprise
    case wink

    var displayName: String {
        switch self {
        case .laugh: return "Laugh"
        case .smile: return "Smile"
        case .pause: return "Pause"
        case .emphasis: return "Emphasis"
        case .gesture: return "Gesture"
        case .eyeroll: return "Eye Roll"
        case .nod: return "Nod"
        case .shrug: return "Shrug"
        case .sigh: return "Sigh"
        case .think: return "Think"
        case .surprise: return "Surprise"
        case .wink: return "Wink"
        }
    }

    var emoji: String {
        switch self {
        case .laugh: return "😄"
        case .smile: return "😊"
        case .pause: return "⏸️"
        case .emphasis: return "💪"
        case .gesture: return "👋"
        case .eyeroll: return "🙄"
        case .nod: return "✓"
        case .shrug: return "🤷"
        case .sigh: return "😮‍💨"
        case .think: return "🤔"
        case .surprise: return "😮"
        case .wink: return "😉"
        }
    }

    var color: String {
        switch self {
        case .laugh, .smile: return "yellow"
        case .pause, .think: return "blue"
        case .emphasis: return "red"
        case .gesture, .nod, .shrug: return "green"
        case .eyeroll, .sigh: return "gray"
        case .surprise: return "orange"
        case .wink: return "purple"
        }
    }
}

// MARK: - Emotion Tag

/// Emotional tone tags for dialogue examples
enum EmotionTag: String, Codable, CaseIterable {
    case happy
    case sad
    case angry
    case surprised
    case confident
    case nervous
    case playful
    case serious
    case excited
    case calm
    case frustrated
    case curious
    case nostalgic
    case determined
    case vulnerable

    var displayName: String {
        rawValue.capitalized
    }

    var color: String {
        switch self {
        case .happy, .playful, .excited: return "yellow"
        case .sad, .nostalgic, .vulnerable: return "blue"
        case .angry, .frustrated: return "red"
        case .surprised, .curious: return "orange"
        case .confident, .determined: return "green"
        case .nervous: return "purple"
        case .serious, .calm: return "gray"
        }
    }

    var emoji: String {
        switch self {
        case .happy: return "😊"
        case .sad: return "😢"
        case .angry: return "😠"
        case .surprised: return "😲"
        case .confident: return "😎"
        case .nervous: return "😰"
        case .playful: return "😜"
        case .serious: return "😐"
        case .excited: return "🤩"
        case .calm: return "😌"
        case .frustrated: return "😤"
        case .curious: return "🤔"
        case .nostalgic: return "🥹"
        case .determined: return "💪"
        case .vulnerable: return "🥺"
        }
    }
}

// MARK: - Animation Marker

/// A single animation marker within a dialogue example
struct AnimationMarker: Codable, Hashable, Identifiable {
    var id: UUID = UUID()

    /// Character position in the dialogue text where this marker applies
    let position: Int

    /// The type of animation/gesture/expression
    let marker: AnimationMarkerType

    /// Optional duration in seconds (for extended animations)
    let duration: Double?

    enum CodingKeys: String, CodingKey {
        case id, position, marker, duration
    }

    init(position: Int, marker: AnimationMarkerType, duration: Double? = nil) {
        self.id = UUID()
        self.position = position
        self.marker = marker
        self.duration = duration
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.position = try container.decode(Int.self, forKey: .position)
        self.marker = try container.decode(AnimationMarkerType.self, forKey: .marker)
        self.duration = try container.decodeIfPresent(Double.self, forKey: .duration)
    }
}

// MARK: - Animation Markers Helper

extension Array where Element == AnimationMarker {
    /// Get all markers at or near a specific position
    func markers(near position: Int, tolerance: Int = 5) -> [AnimationMarker] {
        filter { abs($0.position - position) <= tolerance }
    }

    /// Format markers as inline text insertions
    func asInlineAnnotations(in text: String) -> String {
        let sortedMarkers = sorted { $0.position > $1.position }
        var result = text

        for marker in sortedMarkers {
            let insertPosition = Swift.min(marker.position, result.count)
            let index = result.index(result.startIndex, offsetBy: insertPosition)
            let annotation = " [\(marker.marker.displayName)]"
            result.insert(contentsOf: annotation, at: index)
        }

        return result
    }
}
