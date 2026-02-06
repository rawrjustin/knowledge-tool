import Foundation

// MARK: - Source Deletion Result

/// Result of a source deletion operation
struct SourceDeletionResult {
    let sourceId: UUID
    let sourceTitle: String
    let entriesRemoved: Int
    let affectedSections: [String]
    let knowledgeFileDeleted: String?
}

// MARK: - Source Deletion Service

/// Service for handling source-by-source deletion from character knowledge
actor SourceDeletionService {

    // MARK: - Preview Deletion

    /// Preview what will be deleted when a source is removed
    /// - Parameters:
    ///   - sourceId: The ID of the source to delete
    ///   - character: The character containing the source
    /// - Returns: A preview of what will be affected
    nonisolated func previewDeletion(sourceId: UUID, character: Character) -> SourceDeletionResult {
        let sources = character.knowledgeSources
        guard let source = sources.first(where: { $0.id == sourceId }) else {
            return SourceDeletionResult(
                sourceId: sourceId,
                sourceTitle: "Unknown Source",
                entriesRemoved: 0,
                affectedSections: [],
                knowledgeFileDeleted: nil
            )
        }

        // Count entries that would be removed
        let entriesToRemove = source.entries.count

        // Find affected sections
        let affectedSections = Array(Set(source.entries.map { $0.section })).sorted()

        return SourceDeletionResult(
            sourceId: sourceId,
            sourceTitle: source.title,
            entriesRemoved: entriesToRemove,
            affectedSections: affectedSections,
            knowledgeFileDeleted: source.knowledgeFileName
        )
    }

    // MARK: - Delete Source Entries

    /// Delete all entries associated with a source from a character
    /// - Parameters:
    ///   - sourceId: The ID of the source to delete
    ///   - character: The character to modify
    ///   - repository: The repository to save changes
    /// - Returns: The result of the deletion and the updated character
    func deleteSourceEntries(
        sourceId: UUID,
        from character: Character,
        using repository: CombinedCharacterRepository
    ) async throws -> (result: SourceDeletionResult, updatedCharacter: Character) {
        // Get preview first
        let preview = previewDeletion(sourceId: sourceId, character: character)

        guard preview.entriesRemoved > 0 || preview.knowledgeFileDeleted != nil else {
            return (preview, character)
        }

        // Find the knowledge file to delete
        if let fileName = preview.knowledgeFileDeleted {
            // Find the matching knowledge file
            if let knowledgeFile = character.knowledgeFiles.first(where: { $0.fileName == fileName }) {
                try await repository.deleteKnowledgeFile(knowledgeFile)
            }
        }

        // Reload all characters to get the updated state
        let characters = try await repository.loadAllCharacters()
        let updatedCharacter = characters.first { $0.id == character.id }

        return (preview, updatedCharacter ?? character)
    }

    // MARK: - Delete Entries by Source ID

    /// Remove entries with a specific sourceId from a knowledge file content
    /// - Parameters:
    ///   - sourceId: The source ID to filter out
    ///   - jsonlContent: The original JSONL content
    /// - Returns: The filtered JSONL content
    nonisolated func filterEntriesBySourceId(_ sourceId: UUID, from jsonlContent: String) -> String {
        let lines = jsonlContent.components(separatedBy: .newlines)
        let sourceIdString = sourceId.uuidString

        let filteredLines = lines.filter { line in
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { return false }

            // Try to parse the line and check sourceId
            if let data = line.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let entrySourceId = json["sourceId"] as? String {
                return entrySourceId != sourceIdString
            }

            // Keep lines that don't have a sourceId (legacy entries)
            return true
        }

        return filteredLines.joined(separator: "\n")
    }
}

// MARK: - Deletion Error

enum SourceDeletionError: LocalizedError {
    case sourceNotFound(UUID)
    case deletionFailed(String)

    var errorDescription: String? {
        switch self {
        case .sourceNotFound(let id):
            return "Source with ID \(id) not found"
        case .deletionFailed(let reason):
            return "Deletion failed: \(reason)"
        }
    }
}
