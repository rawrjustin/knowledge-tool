import Foundation

/// Represents a loaded system prompt with its metadata
struct SystemPromptVersion: Identifiable, Hashable {
    let id = UUID()
    let type: SystemPromptType
    let version: Int
    var content: String
    let sha: String  // GitHub SHA for updates
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

    // Services
    private let githubAPI: GitHubAPIService
    private let isReadOnly: Bool

    init(githubAPI: GitHubAPIService, isReadOnly: Bool) {
        self.githubAPI = githubAPI
        self.isReadOnly = isReadOnly
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
        error = nil

        async let aspTask = loadPromptVersions(type: .action)
        async let cspTask = loadPromptVersions(type: .conversational)
        async let rspTask = loadPromptVersions(type: .roleplay)

        let (asp, csp, rsp) = await (aspTask, cspTask, rspTask)

        aspVersions = asp
        cspVersions = csp
        rspVersions = rsp

        // Select latest versions by default
        if let latest = aspVersions.max(by: { $0.version < $1.version }) {
            selectedASPVersion = latest
            editedASPContent = latest.content
        }

        if let latest = cspVersions.max(by: { $0.version < $1.version }) {
            selectedCSPVersion = latest
            editedCSPContent = latest.content
        }

        if let latest = rspVersions.max(by: { $0.version < $1.version }) {
            selectedRSPVersion = latest
            editedRSPContent = latest.content
        }

        isLoading = false
    }

    private func loadPromptVersions(type: SystemPromptType) async -> [SystemPromptVersion] {
        let path = "SystemPrompts/\(type.rawValue)"

        do {
            let files = try await githubAPI.listContents(at: path)
            var versions: [SystemPromptVersion] = []

            for file in files where file.type == "file" && file.name.hasSuffix(".md") {
                // Extract version number from filename (e.g., ASP1.md -> 1)
                let pattern = "\(type.rawValue)(\\d+)\\.md"
                if let regex = try? NSRegularExpression(pattern: pattern),
                   let match = regex.firstMatch(in: file.name, range: NSRange(file.name.startIndex..., in: file.name)),
                   let versionRange = Range(match.range(at: 1), in: file.name),
                   let version = Int(String(file.name[versionRange])) {

                    // Load the file content
                    if let fileData = try? await githubAPI.getFile(at: file.path),
                       let content = fileData.decodedContent {
                        versions.append(SystemPromptVersion(
                            type: type,
                            version: version,
                            content: content,
                            sha: fileData.sha,
                            path: file.path
                        ))
                    }
                }
            }

            return versions.sorted { $0.version < $1.version }
        } catch {
            NSLog("[SystemPromptEditor] Failed to load \(type.rawValue) versions: \(error.localizedDescription)")
            return []
        }
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
        guard let selected = selectedASPVersion else { return false }
        return await savePrompt(type: .action, content: editedASPContent, currentSha: selected.sha, option: option)
    }

    func saveCSP(option: SaveOption) async -> Bool {
        guard let selected = selectedCSPVersion else { return false }
        return await savePrompt(type: .conversational, content: editedCSPContent, currentSha: selected.sha, option: option)
    }

    func saveRSP(option: SaveOption) async -> Bool {
        guard let selected = selectedRSPVersion else { return false }
        return await savePrompt(type: .roleplay, content: editedRSPContent, currentSha: selected.sha, option: option)
    }

    private func savePrompt(type: SystemPromptType, content: String, currentSha: String, option: SaveOption) async -> Bool {
        guard !isReadOnly else {
            error = "Cannot save in read-only mode. Please authenticate with GitHub."
            return false
        }

        isSaving = true
        error = nil

        do {
            let (path, message, sha): (String, String, String?)

            switch option {
            case .overwrite(let version):
                path = "SystemPrompts/\(type.rawValue)/\(type.rawValue)\(version).md"
                message = "Update \(type.rawValue)\(version)"
                sha = currentSha

            case .createNew:
                let newVersion = nextVersion(for: type)
                path = "SystemPrompts/\(type.rawValue)/\(type.rawValue)\(newVersion).md"
                message = "Create \(type.rawValue)\(newVersion)"
                sha = nil  // New file, no SHA needed
            }

            _ = try await githubAPI.updateFile(at: path, content: content, message: message, sha: sha)

            // Reload to get updated versions
            await loadAllPrompts()

            isSaving = false
            return true

        } catch {
            self.error = "Failed to save: \(error.localizedDescription)"
            isSaving = false
            return false
        }
    }

    private func nextVersion(for type: SystemPromptType) -> Int {
        switch type {
        case .action: return nextASPVersion
        case .conversational: return nextCSPVersion
        case .roleplay: return nextRSPVersion
        }
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
