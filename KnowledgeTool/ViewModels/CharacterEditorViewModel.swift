import Foundation

@MainActor
@Observable
final class CharacterEditorViewModel {
    // Character being edited
    private(set) var character: Character?

    // Editing state
    var name: String
    var markdownContent: String
    var systemPromptType: SystemPromptType
    var versionName: String = ""

    // Original content for diffing
    private(set) var originalMarkdownContent: String

    // UI state
    private(set) var isSaving = false
    var error: String?
    private(set) var hasUnsavedChanges = false

    // Repository
    private let repository: CombinedCharacterRepository

    // Mode
    enum Mode {
        case create
        case edit(Character)
    }

    private let mode: Mode

    init(mode: Mode, repository: CombinedCharacterRepository) {
        self.mode = mode
        self.repository = repository

        switch mode {
        case .create:
            self.character = nil
            self.name = ""
            self.markdownContent = Self.defaultPersonaTemplate
            self.originalMarkdownContent = Self.defaultPersonaTemplate
            self.systemPromptType = .action

        case .edit(let character):
            self.character = character
            self.name = character.name
            self.markdownContent = character.markdownContent
            self.originalMarkdownContent = character.markdownContent
            self.systemPromptType = character.systemPromptType
        }
    }

    // MARK: - Actions

    /// Save the character
    func save() async -> Bool {
        guard !isSaving else { return false }

        error = nil
        isSaving = true
        defer { isSaving = false }

        do {
            switch mode {
            case .create:
                // Create new character
                let newCharacter = try await repository.createCharacter(
                    name: name,
                    markdownContent: markdownContent,
                    systemPromptType: systemPromptType
                )
                character = newCharacter
                hasUnsavedChanges = false
                return true

            case .edit(var existingCharacter):
                // Update existing character - save as new version
                existingCharacter.name = name
                existingCharacter.markdownContent = markdownContent
                existingCharacter.systemPromptType = systemPromptType
                existingCharacter.lastModified = Date()
                let trimmedName = versionName.trimmingCharacters(in: .whitespacesAndNewlines)
                existingCharacter.versionName = trimmedName.isEmpty ? nil : trimmedName

                // Save as new version (creates v2, v3, etc.)
                let newVersion = try await repository.saveCharacterAsNewVersion(existingCharacter)
                character = newVersion
                hasUnsavedChanges = false
                versionName = ""
                return true
            }
        } catch {
            self.error = "Failed to save character: \(error.localizedDescription)"
            return false
        }
    }

    /// Mark content as changed
    func markAsChanged() {
        guard let character = character else {
            // For new characters, check if anything has been entered
            hasUnsavedChanges = !name.isEmpty || markdownContent != Self.defaultPersonaTemplate
            return
        }

        // For existing characters, check if content differs from original
        hasUnsavedChanges = name != character.name ||
                           markdownContent != character.markdownContent ||
                           systemPromptType != character.systemPromptType
    }

    /// Discard changes
    func discardChanges() {
        guard let character = character else { return }

        name = character.name
        markdownContent = character.markdownContent
        systemPromptType = character.systemPromptType
        hasUnsavedChanges = false
        error = nil
    }

    /// Get line-by-line diff between original and current content
    func getLineDiff() -> [DiffLine] {
        let originalLines = originalMarkdownContent.components(separatedBy: .newlines)
        let currentLines = markdownContent.components(separatedBy: .newlines)

        var diffLines: [DiffLine] = []

        // Use a simple line-by-line comparison with LCS for better results
        let lcs = computeLCS(originalLines, currentLines)
        var origIdx = 0
        var currIdx = 0
        var lcsIdx = 0

        while origIdx < originalLines.count || currIdx < currentLines.count {
            if lcsIdx < lcs.count &&
               origIdx < originalLines.count && originalLines[origIdx] == lcs[lcsIdx] &&
               currIdx < currentLines.count && currentLines[currIdx] == lcs[lcsIdx] {
                // Line unchanged
                diffLines.append(DiffLine(text: originalLines[origIdx], type: .unchanged, lineNumber: currIdx + 1))
                origIdx += 1
                currIdx += 1
                lcsIdx += 1
            } else if origIdx < originalLines.count &&
                      (lcsIdx >= lcs.count || originalLines[origIdx] != lcs[lcsIdx]) &&
                      !currentLines.contains(originalLines[origIdx]) {
                // Line removed
                diffLines.append(DiffLine(text: originalLines[origIdx], type: .removed, lineNumber: nil))
                origIdx += 1
            } else if currIdx < currentLines.count &&
                      (lcsIdx >= lcs.count || currentLines[currIdx] != lcs[lcsIdx]) {
                // Line added
                diffLines.append(DiffLine(text: currentLines[currIdx], type: .added, lineNumber: currIdx + 1))
                currIdx += 1
            } else {
                // Move forward
                if origIdx < originalLines.count { origIdx += 1 }
                if currIdx < currentLines.count { currIdx += 1 }
            }
        }

        return diffLines
    }

    /// Compute longest common subsequence
    private func computeLCS(_ arr1: [String], _ arr2: [String]) -> [String] {
        let m = arr1.count
        let n = arr2.count
        guard m > 0 && n > 0 else { return [] }

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

    /// Get changed line numbers for highlighting in editor
    /// Uses simple position-based comparison for inline editing UX
    func getChangedLineNumbers() -> Set<Int> {
        let originalLines = originalMarkdownContent.components(separatedBy: .newlines)
        let currentLines = markdownContent.components(separatedBy: .newlines)

        var changedLines: Set<Int> = []

        // Compare lines by position
        let maxLines = max(originalLines.count, currentLines.count)
        for i in 0..<maxLines {
            let lineNumber = i + 1 // 1-indexed

            if i >= originalLines.count {
                // New line added at the end
                changedLines.insert(lineNumber)
            } else if i >= currentLines.count {
                // Line was removed (shouldn't show in current, but track it)
                continue
            } else if originalLines[i] != currentLines[i] {
                // Line content changed
                changedLines.insert(lineNumber)
            }
        }

        return changedLines
    }

    // MARK: - Default Template

    private static let defaultPersonaTemplate = """
# Character Name

## Overview
[Brief description of the character]

## Personality Traits
- Trait 1
- Trait 2
- Trait 3

## Background
[Character's background story]

## Speaking Style
[How the character speaks and communicates]

## Interests and Expertise
[What the character knows about and is interested in]

## Goals and Motivations
[What drives this character]
"""
}
