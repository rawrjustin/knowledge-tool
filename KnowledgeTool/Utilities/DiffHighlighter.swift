import Foundation

/// Utility for highlighting differences between two texts
actor DiffHighlighter {
    /// Compare two texts word-by-word and generate diff segments
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

    /// Compare two texts line-by-line and generate diff segments for each line
    func compareLines(_ text1: String, _ text2: String) async -> DiffResult {
        let lines1 = text1.components(separatedBy: .newlines)
        let lines2 = text2.components(separatedBy: .newlines)

        var segments: [DiffSegment] = []

        // Use longest common subsequence algorithm for better line matching
        let lcs = computeLCS(lines1, lines2)
        var i = 0
        var j = 0
        var lcsIndex = 0

        while i < lines1.count || j < lines2.count {
            if lcsIndex < lcs.count && i < lines1.count && lines1[i] == lcs[lcsIndex] &&
               j < lines2.count && lines2[j] == lcs[lcsIndex] {
                // Line is in both - unchanged
                if !lines1[i].isEmpty {
                    segments.append(DiffSegment(text: lines1[i], type: .unchanged, isLine: true))
                }
                i += 1
                j += 1
                lcsIndex += 1
            } else if i < lines1.count && (lcsIndex >= lcs.count || lines1[i] != lcs[lcsIndex]) &&
                      (j >= lines2.count || !lines2.contains(lines1[i])) {
                // Line only in text1 - removed
                if !lines1[i].isEmpty {
                    segments.append(DiffSegment(text: lines1[i], type: .removed, isLine: true))
                }
                i += 1
            } else if j < lines2.count && (lcsIndex >= lcs.count || lines2[j] != lcs[lcsIndex]) {
                // Line only in text2 - added
                if !lines2[j].isEmpty {
                    segments.append(DiffSegment(text: lines2[j], type: .added, isLine: true))
                }
                j += 1
            } else {
                // Move forward
                if i < lines1.count { i += 1 }
                if j < lines2.count { j += 1 }
            }
        }

        return DiffResult(
            originalText: text1,
            comparedText: text2,
            segments: segments
        )
    }

    /// Compute longest common subsequence of two arrays
    private func computeLCS(_ arr1: [String], _ arr2: [String]) -> [String] {
        let m = arr1.count
        let n = arr2.count

        // Create DP table
        var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)

        for i in 1...m {
            for j in 1...n {
                if arr1[i - 1] == arr2[j - 1] {
                    dp[i][j] = dp[i - 1][j - 1] + 1
                } else {
                    dp[i][j] = max(dp[i - 1][j], dp[i][j - 1])
                }
            }
        }

        // Backtrack to find LCS
        var lcs: [String] = []
        var i = m
        var j = n

        while i > 0 && j > 0 {
            if arr1[i - 1] == arr2[j - 1] {
                lcs.insert(arr1[i - 1], at: 0)
                i -= 1
                j -= 1
            } else if dp[i - 1][j] > dp[i][j - 1] {
                i -= 1
            } else {
                j -= 1
            }
        }

        return lcs
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
