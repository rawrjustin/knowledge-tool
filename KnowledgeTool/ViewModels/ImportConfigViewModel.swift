import Foundation

// MARK: - Import Config ViewModel

/// Manages importing an existing Genies dev config into KnowledgeTool as a local character
@Observable
@MainActor
final class ImportConfigViewModel {
    // UI state
    var isLoading = false
    var isBrowsing = false
    var isImporting = false
    var error: String?
    var importSuccess: String?

    // Browse configs
    var availableConfigs: [GeniesConfigResponse] = []

    // Manual entry
    var manualConfigId = ""

    // Selected config preview
    var selectedConfig: GeniesConfigResponse?

    // Extracted info for preview
    var previewName: String = ""
    var previewPromptType: SystemPromptType = .conversational
    var previewPersonaSnippet: String = ""

    private let geniesService = GeniesPersonaService.shared

    // MARK: - Browse Configs

    func browseConfigs() async {
        isBrowsing = true
        error = nil

        do {
            var allConfigs: [GeniesConfigResponse] = []
            var cursor: String? = nil

            repeat {
                let response = try await geniesService.queryConfigs(limit: 1000, cursor: cursor)
                allConfigs.append(contentsOf: response.configs)
                cursor = response.nextCursor
            } while cursor != nil

            availableConfigs = allConfigs.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            NSLog("[ImportConfigViewModel] Loaded %d configs from org", availableConfigs.count)
        } catch {
            self.error = "Failed to load configs: \(error.localizedDescription)"
        }

        isBrowsing = false
    }

    // MARK: - Select Config (for preview)

    func selectConfig(_ config: GeniesConfigResponse) {
        selectedConfig = config
        error = nil
        importSuccess = nil

        // Extract preview info
        if let name = extractCharacterName(from: config) {
            previewName = name
        } else {
            previewName = config.name.isEmpty ? config.id : config.name
        }

        previewPromptType = extractPromptType(from: config)

        if let persona = config.config?.characterConfig.identity.properties?.persona.value {
            let trimmed = persona.trimmingCharacters(in: .whitespacesAndNewlines)
            previewPersonaSnippet = String(trimmed.prefix(300))
            if trimmed.count > 300 {
                previewPersonaSnippet += "..."
            }
        } else {
            previewPersonaSnippet = "(No persona content found in config)"
        }
    }

    // MARK: - Fetch Config by ID

    func fetchConfig(configId: String) async {
        isLoading = true
        error = nil
        selectedConfig = nil

        do {
            let config = try await geniesService.getConfig(configId: configId)
            selectConfig(config)
        } catch {
            self.error = "Failed to fetch config: \(error.localizedDescription)"
        }

        isLoading = false
    }

    // MARK: - Import Config as Local Character

    func importConfig(repository: CombinedCharacterRepository) async -> Character? {
        guard let config = selectedConfig else {
            error = "No config selected"
            return nil
        }

        isImporting = true
        error = nil

        do {
            // Extract persona markdown from config
            let personaContent = config.config?.characterConfig.identity.properties?.persona.value
                ?? "# \(previewName)\n\n(Imported from Genies dev config \(config.id))"

            let promptType = extractPromptType(from: config)

            // Create the character locally
            let character = try await repository.createCharacter(
                name: previewName,
                markdownContent: personaContent,
                systemPromptType: promptType
            )

            // Save publish metadata so it's immediately linked
            let sha = PublishViewModel.contentSha(for: character)
            let now = ISO8601DateFormatter().string(from: Date())
            await repository.savePublishMetadata(
                configId: config.id,
                sha: sha,
                publishedAt: now,
                characterName: previewName
            )

            importSuccess = "Imported \"\(previewName)\" and linked to config \(String(config.id.prefix(8)))..."
            NSLog("[ImportConfigViewModel] Imported config %@ as character '%@'", config.id, previewName)

            isImporting = false
            return character
        } catch {
            self.error = "Failed to import: \(error.localizedDescription)"
            isImporting = false
            return nil
        }
    }

    // MARK: - Helpers

    /// Extract the character name from config name (strips "[CSP1] " prefix)
    private func extractCharacterName(from config: GeniesConfigResponse) -> String? {
        let configName = config.name
        guard !configName.isEmpty else { return nil }

        // Try to strip "[TYPE] " prefix
        let pattern = #"^\[(?:CSP|ASP|RSP)\d*\]\s*"#
        if let range = configName.range(of: pattern, options: .regularExpression) {
            let name = String(configName[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            if !name.isEmpty { return name }
        }

        // Fall back to identity name property
        if let identityName = config.config?.characterConfig.identity.properties?.name.value,
           !identityName.isEmpty {
            return identityName
        }

        return configName
    }

    /// Determine the SystemPromptType from the config
    private func extractPromptType(from config: GeniesConfigResponse) -> SystemPromptType {
        // Try chat_prompt key first
        if let chatPrompt = config.config?.characterConfig.chatPrompt?.value {
            if chatPrompt.contains("csp") { return .conversational }
            if chatPrompt.contains("rsp") { return .roleplay }
            if chatPrompt.contains("asp") { return .action }
        }

        // Try config name prefix
        let name = config.name
        if name.hasPrefix("[CSP") { return .conversational }
        if name.hasPrefix("[RSP") { return .roleplay }
        if name.hasPrefix("[ASP") { return .action }

        return .conversational
    }

    private func getOrgId() async throws -> String {
        guard let orgId = await AuthService.shared.getStoredOrganizationId(), !orgId.isEmpty else {
            throw GeniesAPIError.unauthorized
        }
        return orgId
    }
}
