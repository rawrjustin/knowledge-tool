import Foundation

/// Represents a loaded system prompt with its metadata
struct SystemPromptVersion: Identifiable, Hashable {
    let id = UUID()
    let type: SystemPromptType
    let version: Int
    var content: String
    let path: String

    var fileName: String {
        "\(type.rawValue)\(version).md"
    }

    var displayName: String {
        "\(type.rawValue)\(version)"
    }
}

@MainActor
@Observable
final class SystemPromptEditorViewModel {
    // Loaded prompts by type
    private(set) var aspVersions: [SystemPromptVersion] = []
    private(set) var cspVersions: [SystemPromptVersion] = []
    private(set) var rspVersions: [SystemPromptVersion] = []

    // Currently selected/editing versions
    var selectedASPVersion: SystemPromptVersion?
    var selectedCSPVersion: SystemPromptVersion?
    var selectedRSPVersion: SystemPromptVersion?

    // Edited content (tracks changes)
    var editedASPContent: String = ""
    var editedCSPContent: String = ""
    var editedRSPContent: String = ""

    // UI State
    private(set) var isLoading = false
    private(set) var isSaving = false
    var error: String?

    init() {
        // System prompt editing is currently not available without GitHub
        // This feature will be reimplemented with Supabase storage
    }

    // MARK: - Computed Properties

    var hasASPChanges: Bool {
        guard let selected = selectedASPVersion else { return false }
        return editedASPContent != selected.content
    }

    var hasCSPChanges: Bool {
        guard let selected = selectedCSPVersion else { return false }
        return editedCSPContent != selected.content
    }

    var hasRSPChanges: Bool {
        guard let selected = selectedRSPVersion else { return false }
        return editedRSPContent != selected.content
    }

    var hasAnyChanges: Bool {
        hasASPChanges || hasCSPChanges || hasRSPChanges
    }

    var nextASPVersion: Int {
        (aspVersions.map { $0.version }.max() ?? 0) + 1
    }

    var nextCSPVersion: Int {
        (cspVersions.map { $0.version }.max() ?? 0) + 1
    }

    var nextRSPVersion: Int {
        (rspVersions.map { $0.version }.max() ?? 0) + 1
    }

    // MARK: - Loading

    func loadAllPrompts() async {
        isLoading = true
        error = "System prompt editing is currently unavailable. This feature is being migrated to Supabase."
        isLoading = false
    }

    // MARK: - Selection

    func selectASPVersion(_ version: SystemPromptVersion) {
        selectedASPVersion = version
        editedASPContent = version.content
    }

    func selectCSPVersion(_ version: SystemPromptVersion) {
        selectedCSPVersion = version
        editedCSPContent = version.content
    }

    func selectRSPVersion(_ version: SystemPromptVersion) {
        selectedRSPVersion = version
        editedRSPContent = version.content
    }

    // MARK: - Saving

    enum SaveOption {
        case overwrite(version: Int)
        case createNew
    }

    func saveASP(option: SaveOption) async -> Bool {
        error = "Saving is currently unavailable. This feature is being migrated to Supabase."
        return false
    }

    func saveCSP(option: SaveOption) async -> Bool {
        error = "Saving is currently unavailable. This feature is being migrated to Supabase."
        return false
    }

    func saveRSP(option: SaveOption) async -> Bool {
        error = "Saving is currently unavailable. This feature is being migrated to Supabase."
        return false
    }

    // MARK: - Discard Changes

    func discardASPChanges() {
        if let selected = selectedASPVersion {
            editedASPContent = selected.content
        }
    }

    func discardCSPChanges() {
        if let selected = selectedCSPVersion {
            editedCSPContent = selected.content
        }
    }

    func discardRSPChanges() {
        if let selected = selectedRSPVersion {
            editedRSPContent = selected.content
        }
    }

    func discardAllChanges() {
        discardASPChanges()
        discardCSPChanges()
        discardRSPChanges()
    }
}
