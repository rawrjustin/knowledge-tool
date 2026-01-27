import Foundation

@MainActor
@Observable
final class VersionComparisonViewModel {
    // MARK: - State

    /// All available versions for the current character
    private(set) var versions: [Character] = []

    /// Currently selected versions for comparison (up to 4)
    var selectedVersions: [Character] = []

    /// Chat messages for each version (keyed by version ID)
    private(set) var chatMessages: [UUID: [ChatMessage]] = [:]

    /// Execution state for each version
    private(set) var isExecuting: [UUID: Bool] = [:]

    /// Error state for each version
    private(set) var errors: [UUID: String] = [:]

    /// Loading state
    private(set) var isLoading = false

    /// Error message
    var error: String?

    // MARK: - Dependencies

    private let localRepository: LocalCharacterRepository
    private let apiKeyManager: APIKeyManager

    // Computed property to get OpenAI service
    private var openAIService: OpenAIService? {
        guard let apiKey = apiKeyManager.getAPIKey(for: .openAI) else { return nil }
        return OpenAIService(apiKey: apiKey)
    }

    // MARK: - Constants

    static let maxVersionsToCompare = 4
    static let versionLabels = ["Version A", "Version B", "Version C", "Version D"]

    // MARK: - Initialization

    init(localRepository: LocalCharacterRepository, apiKeyManager: APIKeyManager) {
        self.localRepository = localRepository
        self.apiKeyManager = apiKeyManager
    }

    // MARK: - Version Loading

    /// Load all versions for a character
    func loadVersions(for characterName: String) async {
        isLoading = true
        error = nil

        do {
            versions = try await localRepository.loadAllVersions(for: characterName)
            // Sort by version number descending (newest first)
            versions.sort { $0.version > $1.version }
        } catch {
            self.error = "Failed to load versions: \(error.localizedDescription)"
            versions = []
        }

        isLoading = false
    }

    /// Set versions directly (for when they're pre-loaded)
    func setVersions(_ preloadedVersions: [Character]) {
        versions = preloadedVersions.sorted { $0.version > $1.version }
    }

    /// Select a version for comparison
    func selectVersion(_ version: Character) {
        guard selectedVersions.count < Self.maxVersionsToCompare else { return }
        guard !selectedVersions.contains(where: { $0.id == version.id }) else { return }

        selectedVersions.append(version)
        chatMessages[version.id] = []
        isExecuting[version.id] = false
        errors[version.id] = nil
    }

    /// Deselect a version
    func deselectVersion(_ version: Character) {
        selectedVersions.removeAll { $0.id == version.id }
        chatMessages.removeValue(forKey: version.id)
        isExecuting.removeValue(forKey: version.id)
        errors.removeValue(forKey: version.id)
    }

    /// Check if a version is selected
    func isSelected(_ version: Character) -> Bool {
        selectedVersions.contains { $0.id == version.id }
    }

    /// Clear all selections
    func clearSelections() {
        selectedVersions.removeAll()
        chatMessages.removeAll()
        isExecuting.removeAll()
        errors.removeAll()
    }

    /// Get label for a selected version (Version A, B, C, D)
    func label(for version: Character) -> String {
        guard let index = selectedVersions.firstIndex(where: { $0.id == version.id }) else {
            return version.versionDisplay
        }
        return Self.versionLabels[index]
    }

    // MARK: - Chat Management

    /// Send a message to all selected versions simultaneously
    func sendMessage(_ userMessage: String) async {
        guard let openAIService = openAIService else {
            error = "OpenAI API key not configured"
            return
        }

        guard !selectedVersions.isEmpty else {
            error = "No versions selected for comparison"
            return
        }

        let trimmedMessage = userMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty else { return }

        // Add user message to all versions
        let userChatMessage = ChatMessage(role: .user, content: trimmedMessage)
        for version in selectedVersions {
            chatMessages[version.id, default: []].append(userChatMessage)
            isExecuting[version.id] = true
            errors[version.id] = nil
        }

        // Execute all versions in parallel
        await withTaskGroup(of: (UUID, Result<String, Error>).self) { group in
            for version in selectedVersions {
                group.addTask {
                    do {
                        let response = try await self.executeChat(
                            for: version,
                            userMessage: trimmedMessage,
                            openAIService: openAIService
                        )
                        return (version.id, .success(response))
                    } catch {
                        return (version.id, .failure(error))
                    }
                }
            }

            // Collect results as they complete
            for await (versionId, result) in group {
                isExecuting[versionId] = false

                switch result {
                case .success(let response):
                    let assistantMessage = ChatMessage(role: .assistant, content: response)
                    chatMessages[versionId, default: []].append(assistantMessage)
                case .failure(let error):
                    errors[versionId] = error.localizedDescription
                }
            }
        }
    }

    /// Execute chat for a specific version
    private func executeChat(
        for version: Character,
        userMessage: String,
        openAIService: OpenAIService
    ) async throws -> String {
        // Build messages array with system prompt from the version's persona
        var messages: [[String: String]] = [
            ["role": "system", "content": version.markdownContent]
        ]

        // Add chat history
        if let history = chatMessages[version.id] {
            for message in history where message.role != .system {
                messages.append([
                    "role": message.role == .user ? "user" : "assistant",
                    "content": message.content
                ])
            }
        }

        // Add the new user message (already in history, but needed for API call)
        // Actually, it's already added, so we just call the API
        return try await openAIService.chat(messages: messages, model: "gpt-4o")
    }

    /// Clear chat history for all versions
    func clearChatHistory() {
        for version in selectedVersions {
            chatMessages[version.id] = []
            errors[version.id] = nil
        }
    }

    /// Check if any version is currently executing
    var isAnyExecuting: Bool {
        isExecuting.values.contains(true)
    }

    // MARK: - Version Diff

    /// Compute diff between two versions
    func computeDiff(between version1: Character, and version2: Character) -> [DiffLine] {
        let lines1 = version1.markdownContent.components(separatedBy: .newlines)
        let lines2 = version2.markdownContent.components(separatedBy: .newlines)

        return computeLineDiff(original: lines1, modified: lines2)
    }

    /// Line-by-line diff computation using LCS algorithm
    private func computeLineDiff(original: [String], modified: [String]) -> [DiffLine] {
        // Simple LCS-based diff
        let lcs = longestCommonSubsequence(original, modified)
        var result: [DiffLine] = []

        var i = 0, j = 0, k = 0

        while i < original.count || j < modified.count {
            if k < lcs.count && i < original.count && original[i] == lcs[k] && j < modified.count && modified[j] == lcs[k] {
                // Unchanged line
                result.append(DiffLine(text: original[i], type: .unchanged, lineNumber: j + 1))
                i += 1
                j += 1
                k += 1
            } else if j < modified.count && (k >= lcs.count || modified[j] != lcs[k]) {
                // Added line
                result.append(DiffLine(text: modified[j], type: .added, lineNumber: j + 1))
                j += 1
            } else if i < original.count && (k >= lcs.count || original[i] != lcs[k]) {
                // Removed line
                result.append(DiffLine(text: original[i], type: .removed, lineNumber: nil))
                i += 1
            }
        }

        return result
    }

    /// Compute Longest Common Subsequence
    private func longestCommonSubsequence(_ a: [String], _ b: [String]) -> [String] {
        let m = a.count
        let n = b.count
        var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)

        for i in 1...m {
            for j in 1...n {
                if a[i - 1] == b[j - 1] {
                    dp[i][j] = dp[i - 1][j - 1] + 1
                } else {
                    dp[i][j] = max(dp[i - 1][j], dp[i][j - 1])
                }
            }
        }

        // Backtrack to find LCS
        var lcs: [String] = []
        var i = m, j = n
        while i > 0 && j > 0 {
            if a[i - 1] == b[j - 1] {
                lcs.insert(a[i - 1], at: 0)
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

    /// Get response diff between two versions (for the latest assistant messages)
    func getResponseDiff(between version1: Character, and version2: Character) -> DiffResult? {
        guard let messages1 = chatMessages[version1.id],
              let messages2 = chatMessages[version2.id],
              let response1 = messages1.last(where: { $0.role == .assistant }),
              let response2 = messages2.last(where: { $0.role == .assistant }) else {
            return nil
        }

        return computeTextDiff(original: response1.content, modified: response2.content)
    }

    /// Compute word-level diff for text comparison
    private func computeTextDiff(original: String, modified: String) -> DiffResult {
        let words1 = original.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        let words2 = modified.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }

        let lcs = longestCommonSubsequence(words1, words2)
        var segments: [DiffSegment] = []

        var i = 0, j = 0, k = 0

        while i < words1.count || j < words2.count {
            if k < lcs.count && i < words1.count && words1[i] == lcs[k] && j < words2.count && words2[j] == lcs[k] {
                segments.append(DiffSegment(text: words1[i], type: .unchanged))
                i += 1
                j += 1
                k += 1
            } else if j < words2.count && (k >= lcs.count || words2[j] != lcs[k]) {
                segments.append(DiffSegment(text: words2[j], type: .added))
                j += 1
            } else if i < words1.count && (k >= lcs.count || words1[i] != lcs[k]) {
                segments.append(DiffSegment(text: words1[i], type: .removed))
                i += 1
            }
        }

        return DiffResult(originalText: original, comparedText: modified, segments: segments)
    }
}
