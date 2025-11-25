import Foundation

/// Utility for highlighting differences between two texts
actor DiffHighlighter {
    /// Compare two texts and generate diff segments
    func compare(_ text1: String, _ text2: String) async -> DiffResult {
        let words1 = text1.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        let words2 = text2.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }

        var segments: [DiffSegment] = []
        var i = 0
        var j = 0

        while i < words1.count || j < words2.count {
            if i < words1.count && j < words2.count && words1[i] == words2[j] {
                // Words match - unchanged
                segments.append(DiffSegment(text: words1[i], type: .unchanged))
                i += 1
                j += 1
            } else if i < words1.count && j < words2.count {
                // Words differ - modified
                segments.append(DiffSegment(text: words2[j], type: .modified))
                i += 1
                j += 1
            } else if i < words1.count {
                // Only in text1 - removed
                segments.append(DiffSegment(text: words1[i], type: .removed))
                i += 1
            } else {
                // Only in text2 - added
                segments.append(DiffSegment(text: words2[j], type: .added))
                j += 1
            }
        }

        return DiffResult(
            originalText: text1,
            comparedText: text2,
            segments: segments
        )
    }

    /// Calculate similarity percentage between two texts (0.0 to 1.0)
    func similarity(_ text1: String, _ text2: String) async -> Double {
        let words1 = Set(text1.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty })
        let words2 = Set(text2.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty })

        guard !words1.isEmpty || !words2.isEmpty else {
            return 1.0
        }

        let intersection = words1.intersection(words2).count
        let union = words1.union(words2).count

        return Double(intersection) / Double(union)
    }
}
