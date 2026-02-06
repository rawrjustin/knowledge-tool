import Foundation

// MARK: - Key Point

/// A single key point from a source summary
struct KeyPoint: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    let topic: String
    let summary: String
    let importance: Importance
    let timestamp: TimeInterval?

    enum Importance: String, Codable, CaseIterable {
        case high
        case medium
        case low

        var displayName: String {
            rawValue.capitalized
        }

        var color: String {
            switch self {
            case .high: return "red"
            case .medium: return "orange"
            case .low: return "gray"
            }
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, topic, summary, importance, timestamp
    }

    init(topic: String, summary: String, importance: Importance, timestamp: TimeInterval? = nil) {
        self.id = UUID()
        self.topic = topic
        self.summary = summary
        self.importance = importance
        self.timestamp = timestamp
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.topic = try container.decode(String.self, forKey: .topic)
        self.summary = try container.decode(String.self, forKey: .summary)
        self.importance = try container.decode(Importance.self, forKey: .importance)
        self.timestamp = try container.decodeIfPresent(TimeInterval.self, forKey: .timestamp)
    }
}

// MARK: - Source Summary

/// A 2-page summary of a knowledge source for quick team reference
struct SourceSummary: Codable, Hashable {
    /// 2-3 sentence overview of the source content
    let overview: String

    /// 8-12 bullet points of key information
    let keyPoints: [KeyPoint]

    /// 3-5 memorable quotes from the source
    let notableQuotes: [String]

    /// 3-5 main themes discussed
    let themes: [String]

    /// When the summary was generated
    let generatedAt: Date

    init(
        overview: String,
        keyPoints: [KeyPoint],
        notableQuotes: [String],
        themes: [String],
        generatedAt: Date = Date()
    ) {
        self.overview = overview
        self.keyPoints = keyPoints
        self.notableQuotes = notableQuotes
        self.themes = themes
        self.generatedAt = generatedAt
    }
}

// MARK: - Markdown Export

extension SourceSummary {
    /// Export the summary as a formatted markdown document
    func toMarkdown(sourceTitle: String) -> String {
        var md = """
        # \(sourceTitle)

        ## Overview

        \(overview)

        ## Key Points

        """

        for point in keyPoints {
            var line = "- **\(point.topic)**: \(point.summary)"
            if let timestamp = point.timestamp {
                line += " _(\(formatTime(timestamp)))_"
            }
            md += line + "\n"
        }

        md += "\n## Themes\n\n"
        for theme in themes {
            md += "- \(theme)\n"
        }

        if !notableQuotes.isEmpty {
            md += "\n## Notable Quotes\n\n"
            for quote in notableQuotes {
                md += "> \"\(quote)\"\n\n"
            }
        }

        md += "\n---\n_Summary generated on \(generatedAt.formatted(date: .long, time: .shortened))_\n"

        return md
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
}
