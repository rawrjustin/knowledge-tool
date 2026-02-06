import Foundation

@MainActor
@Observable
final class KnowledgeBaseViewModel {
    // Character
    private(set) var character: Character

    // Knowledge files
    private(set) var knowledgeFiles: [KnowledgeFile]

    // UI state
    var searchText: String = ""
    var selectedFile: KnowledgeFile?
    private(set) var isLoading = false
    private(set) var error: String?

    // Repository
    private let repository: CombinedCharacterRepository

    init(character: Character, repository: CombinedCharacterRepository) {
        self.character = character
        self.knowledgeFiles = character.knowledgeFiles
        self.repository = repository
    }

    // MARK: - Computed Properties

    var filteredFiles: [KnowledgeFile] {
        if searchText.isEmpty {
            return knowledgeFiles
        }

        return knowledgeFiles.filter { file in
            file.fileName.localizedCaseInsensitiveContains(searchText) ||
            file.content.localizedCaseInsensitiveContains(searchText)
        }
    }

    var totalWordCount: Int {
        knowledgeFiles.reduce(0) { $0 + $1.wordCount }
    }

    var fileCount: Int {
        knowledgeFiles.count
    }

    // MARK: - Actions

    /// Refresh knowledge files from repository
    func refresh() async {
        isLoading = true
        defer { isLoading = false }

        do {
            // Reload character to get latest knowledge files
            let updatedCharacters = try await repository.loadAllCharacters()

            if let updatedCharacter = updatedCharacters.first(where: { $0.id == character.id }) {
                character = updatedCharacter
                knowledgeFiles = updatedCharacter.knowledgeFiles
            }

            error = nil
        } catch {
            self.error = "Failed to refresh knowledge files: \(error.localizedDescription)"
        }
    }

    /// Create a new knowledge file
    func createKnowledgeFile(fileName: String, content: String) async -> Bool {
        isLoading = true
        defer { isLoading = false }

        do {
            let newFile = try await repository.createKnowledgeFile(
                for: character,
                fileName: fileName,
                content: content
            )

            knowledgeFiles.append(newFile)
            selectedFile = newFile
            error = nil
            return true
        } catch {
            self.error = "Failed to create knowledge file: \(error.localizedDescription)"
            return false
        }
    }

    /// Save an existing knowledge file
    func saveKnowledgeFile(_ file: KnowledgeFile) async -> Bool {
        isLoading = true
        defer { isLoading = false }

        do {
            try await repository.saveKnowledgeFile(file, for: character)

            // Update in list
            if let index = knowledgeFiles.firstIndex(where: { $0.id == file.id }) {
                knowledgeFiles[index] = file
            }

            error = nil
            return true
        } catch {
            self.error = "Failed to save knowledge file: \(error.localizedDescription)"
            return false
        }
    }

    /// Delete a knowledge file
    func deleteKnowledgeFile(_ file: KnowledgeFile) async -> Bool {
        isLoading = true
        defer { isLoading = false }

        do {
            try await repository.deleteKnowledgeFile(file)

            knowledgeFiles.removeAll { $0.id == file.id }

            if selectedFile?.id == file.id {
                selectedFile = nil
            }

            error = nil
            return true
        } catch {
            self.error = "Failed to delete knowledge file: \(error.localizedDescription)"
            return false
        }
    }
}
