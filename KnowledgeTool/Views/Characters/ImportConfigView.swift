import SwiftUI

// MARK: - Import Config View

/// Sheet for importing an existing Genies dev config as a local KnowledgeTool character.
struct ImportConfigView: View {
    let repository: CombinedCharacterRepository
    let onImported: (Character) -> Void
    let onDismiss: () -> Void

    @State private var viewModel = ImportConfigViewModel()
    @State private var selectedTab: ImportTab = .browse
    @Environment(\.colorScheme) private var colorScheme

    enum ImportTab: String, CaseIterable {
        case browse = "Browse"
        case manual = "Config ID"

        var icon: String {
            switch self {
            case .browse: return "list.bullet"
            case .manual: return "number"
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                Text("Import from Genies Dev")
                    .font(.title2.bold())

                Text("Pull an existing character config into KnowledgeTool as a local character.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(DesignSystem.Spacing.xl)

            Divider()

            // Tab picker
            HStack(spacing: 0) {
                ForEach(ImportTab.allCases, id: \.self) { tab in
                    Button {
                        withAnimation(DesignSystem.Animation.quick) {
                            selectedTab = tab
                        }
                    } label: {
                        HStack(spacing: DesignSystem.Spacing.xs) {
                            Image(systemName: tab.icon)
                                .font(.caption)
                            Text(tab.rawValue)
                                .font(.subheadline.weight(selectedTab == tab ? .semibold : .regular))
                        }
                        .padding(.horizontal, DesignSystem.Spacing.md)
                        .padding(.vertical, DesignSystem.Spacing.sm)
                        .background(
                            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                                .fill(selectedTab == tab ? Color.accentColor.opacity(0.1) : Color.clear)
                        )
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(selectedTab == tab ? .primary : .secondary)
                }

                Spacer()
            }
            .padding(.horizontal, DesignSystem.Spacing.xl)
            .padding(.vertical, DesignSystem.Spacing.sm)

            Divider()

            // Content
            switch selectedTab {
            case .browse:
                browseTab
            case .manual:
                manualTab
            }

            Divider()

            // Preview + actions
            if viewModel.selectedConfig != nil {
                configPreview
            }

            // Error / success
            statusArea

            Divider()

            // Footer
            HStack {
                Button("Cancel") { onDismiss() }
                    .keyboardShortcut(.cancelAction)

                Spacer()

                Button(viewModel.isImporting ? "Importing..." : "Import Character") {
                    Task {
                        if let character = await viewModel.importConfig(repository: repository) {
                            onImported(character)
                        }
                    }
                }
                .buttonStyle(.modernPrimary)
                .disabled(viewModel.selectedConfig == nil || viewModel.isImporting)
                .keyboardShortcut(.defaultAction)
            }
            .padding(DesignSystem.Spacing.xl)
        }
        .frame(width: 640)
        .frame(minHeight: 500, maxHeight: 700)
    }

    // MARK: - Browse Tab

    private var browseTab: some View {
        VStack(spacing: 0) {
            if viewModel.availableConfigs.isEmpty && !viewModel.isBrowsing {
                // Load prompt
                VStack(spacing: DesignSystem.Spacing.md) {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 32))
                        .foregroundStyle(.tertiary)

                    Text("Load configs from your organization")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Button {
                        Task { await viewModel.browseConfigs() }
                    } label: {
                        Label("Load Configs", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.modernSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(DesignSystem.Spacing.xl)
            } else if viewModel.isBrowsing {
                VStack(spacing: DesignSystem.Spacing.md) {
                    ProgressView()
                    Text("Loading configs...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(DesignSystem.Spacing.xl)
            } else {
                configList
            }
        }
        .frame(maxHeight: 250)
    }

    private var configList: some View {
        ScrollView {
            LazyVStack(spacing: DesignSystem.Spacing.xs) {
                ForEach(viewModel.availableConfigs, id: \.id) { config in
                    ConfigListRow(
                        config: config,
                        isSelected: viewModel.selectedConfig?.id == config.id,
                        onSelect: {
                            withAnimation(DesignSystem.Animation.quick) {
                                viewModel.selectConfig(config)
                            }
                        }
                    )
                }
            }
            .padding(DesignSystem.Spacing.md)
        }
    }

    // MARK: - Manual Tab

    private var manualTab: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                Text("Config ID")
                    .font(.subheadline.weight(.medium))

                HStack(spacing: DesignSystem.Spacing.sm) {
                    TextField("Paste config ID...", text: $viewModel.manualConfigId)
                        .polishedInput()

                    Button {
                        Task {
                            await viewModel.fetchConfig(configId: viewModel.manualConfigId.trimmingCharacters(in: .whitespacesAndNewlines))
                        }
                    } label: {
                        if viewModel.isLoading {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label("Fetch", systemImage: "arrow.down.circle")
                        }
                    }
                    .buttonStyle(.modernSecondary)
                    .disabled(viewModel.manualConfigId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isLoading)
                }

                Text("Enter the config ID from the Genies dev portal to preview and import it.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(DesignSystem.Spacing.xl)
        .frame(maxHeight: 250)
    }

    // MARK: - Config Preview

    private var configPreview: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            HStack(spacing: DesignSystem.Spacing.sm) {
                Text("Preview")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                // Editable name
                Text("Name:")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                TextField("Character name", text: $viewModel.previewName)
                    .textFieldStyle(.plain)
                    .font(.subheadline.weight(.medium))
                    .frame(width: 200)
                    .padding(.horizontal, DesignSystem.Spacing.sm)
                    .padding(.vertical, DesignSystem.Spacing.xs)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small))
            }

            HStack(spacing: DesignSystem.Spacing.md) {
                // Prompt type
                HStack(spacing: DesignSystem.Spacing.xs) {
                    Text("Type:")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Text(viewModel.previewPromptType.shortDisplayName)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(Capsule().fill(promptTypeColor(viewModel.previewPromptType)))
                }

                // Config ID
                if let config = viewModel.selectedConfig {
                    HStack(spacing: DesignSystem.Spacing.xs) {
                        Text("Config:")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Text(String(config.id.prefix(12)) + "...")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Persona snippet
            if !viewModel.previewPersonaSnippet.isEmpty {
                Text(viewModel.previewPersonaSnippet)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(DesignSystem.Spacing.sm)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small))
            }
        }
        .padding(DesignSystem.Spacing.xl)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
    }

    // MARK: - Status Area

    @ViewBuilder
    private var statusArea: some View {
        if let error = viewModel.error {
            Text(error)
                .font(.caption)
                .foregroundStyle(.red)
                .padding(DesignSystem.Spacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.red.opacity(0.1))
                .padding(.horizontal, DesignSystem.Spacing.xl)
                .padding(.vertical, DesignSystem.Spacing.sm)
        }

        if let success = viewModel.importSuccess {
            Text(success)
                .font(.caption)
                .foregroundStyle(.green)
                .padding(DesignSystem.Spacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.green.opacity(0.1))
                .padding(.horizontal, DesignSystem.Spacing.xl)
                .padding(.vertical, DesignSystem.Spacing.sm)
        }
    }

    private func promptTypeColor(_ type: SystemPromptType) -> Color {
        switch type {
        case .conversational: return .blue
        case .roleplay: return .purple
        case .action: return .orange
        }
    }
}

// MARK: - Config List Row

private struct ConfigListRow: View {
    let config: GeniesConfigResponse
    let isSelected: Bool
    let onSelect: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: DesignSystem.Spacing.md) {
                // Selection indicator
                Circle()
                    .fill(isSelected ? Color.accentColor : Color.clear)
                    .frame(width: 8, height: 8)
                    .overlay(
                        Circle()
                            .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: 1)
                    )

                // Config name
                VStack(alignment: .leading, spacing: 1) {
                    Text(config.name.isEmpty ? "Unnamed Config" : config.name)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)

                    Text(String(config.id.prefix(16)) + "...")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                // Created date
                if let createdAt = config.createdAt {
                    Text(formatDate(createdAt))
                        .font(.caption2)
                        .foregroundStyle(.quaternary)
                }
            }
            .padding(.horizontal, DesignSystem.Spacing.md)
            .padding(.vertical, DesignSystem.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                    .fill(isSelected ? Color.accentColor.opacity(0.08) : (isHovered ? Color.primary.opacity(0.03) : Color.clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                    .stroke(isSelected ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in isHovered = hovering }
    }

    private func formatDate(_ isoString: String) -> String {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: isoString) {
            return date.formatted(.relative(presentation: .named))
        }
        return isoString.prefix(10).description
    }
}
