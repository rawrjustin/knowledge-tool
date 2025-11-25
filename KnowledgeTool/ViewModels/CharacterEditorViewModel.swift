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

    // UI state
    private(set) var isSaving = false
    var error: String?
    private(set) var hasUnsavedChanges = false

    // Repository
    private let localRepository: LocalCharacterRepository

    // Mode
    enum Mode {
        case create
        case edit(Character)
    }

    private let mode: Mode

    init(mode: Mode, localRepository: LocalCharacterRepository) {
        self.mode = mode
        self.localRepository = localRepository

        switch mode {
        case .create:
            self.character = nil
            self.name = ""
            self.markdownContent = Self.defaultPersonaTemplate
            self.systemPromptType = .conversational

        case .edit(let character):
            self.character = character
            self.name = character.name
            self.markdownContent = character.markdownContent
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
                let newCharacter = try await localRepository.createCharacter(
                    name: name,
                    markdownContent: markdownContent
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

                // Save as new version (creates v2, v3, etc.)
                let newVersion = try await localRepository.saveCharacterAsNewVersion(existingCharacter)
                character = newVersion
                hasUnsavedChanges = false
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
