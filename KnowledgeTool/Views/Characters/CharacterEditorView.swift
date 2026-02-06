import SwiftUI

struct CharacterEditorView: View {
    @State private var viewModel: CharacterEditorViewModel
    let onSave: (Character) -> Void
    let onCancel: () -> Void

    @State private var showingDiscardAlert = false
    @State private var showingSaveConfirmation = false
    @State private var showSaveSuccess = false
    @Environment(\.colorScheme) private var colorScheme

    init(
        mode: CharacterEditorViewModel.Mode,
        repository: CombinedCharacterRepository,
        onSave: @escaping (Character) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self._viewModel = State(initialValue: CharacterEditorViewModel(
            mode: mode,
            repository: repository
        ))
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            editorHeader

            Divider()

            // Error banner
            if let error = viewModel.error {
                ErrorBanner(
                    message: error,
                    onDismiss: { viewModel.error = nil }
                )
                .padding(DesignSystem.Spacing.md)
            }

            // Editor content
            HSplitView {
                // Left sidebar - metadata
                metadataSidebar

                // Right side - markdown editor
                markdownEditor
            }
        }
        .frame(minWidth: 800, minHeight: 600)
        .toast(isShowing: $showSaveSuccess, message: "Character saved successfully", style: .success)
        .alert("Revert Changes?", isPresented: $showingDiscardAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Revert", role: .destructive) {
                viewModel.discardChanges()
            }
        } message: {
            Text("This will revert all unsaved changes to the persona markdown.")
        }
        .sheet(isPresented: $showingSaveConfirmation) {
            SaveConfirmationSheet(
                viewModel: viewModel,
                onConfirm: {
                    Task {
                        if await viewModel.save() {
                            showingSaveConfirmation = false
                            showSaveSuccess = true
                            if let character = viewModel.character {
                                onSave(character)
                            }
                        }
                    }
                },
                onCancel: {
                    showingSaveConfirmation = false
                }
            )
        }
    }

    // MARK: - Editor Header
    private var editorHeader: some View {
        HStack {
            // Title and status
            HStack(spacing: DesignSystem.Spacing.md) {
                // Character avatar (for existing characters)
                if let character = viewModel.character {
                    CharacterAvatar(name: character.name, size: 36)
                }

                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxs) {
                    Text(viewModel.character == nil ? "Create Character" : viewModel.character?.name ?? "")
                        .font(.title3.weight(.semibold))

                    // Status indicator
                    if viewModel.hasUnsavedChanges {
                        StatusBadge(text: "Unsaved changes", status: .warning)
                    } else if viewModel.character != nil {
                        StatusBadge(text: "All changes saved", status: .success)
                    }
                }
            }

            Spacer()

            // Word count badge
            HStack(spacing: DesignSystem.Spacing.xs) {
                Image(systemName: "text.word.spacing")
                    .font(.caption)
                Text("\(wordCount) words")
                    .font(.caption.monospacedDigit())
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, DesignSystem.Spacing.md)
            .padding(.vertical, DesignSystem.Spacing.xs)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(Capsule())

            // Actions
            HStack(spacing: DesignSystem.Spacing.sm) {
                if viewModel.hasUnsavedChanges && viewModel.character != nil {
                    Button {
                        handleCancel()
                    } label: {
                        Label("Revert", systemImage: "arrow.uturn.backward")
                    }
                    .buttonStyle(.bordered)
                    .help("Revert all changes (⌘Z)")
                }

                Button {
                    if viewModel.hasUnsavedChanges {
                        showingSaveConfirmation = true
                    }
                } label: {
                    Label("Save", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.name.isEmpty || viewModel.isSaving || !viewModel.hasUnsavedChanges)
                .help("Save changes (⌘S)")
                .keyboardShortcut("s", modifiers: .command)
            }
        }
        .padding(DesignSystem.Spacing.lg)
    }

    // MARK: - Metadata Sidebar
    private var metadataSidebar: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xl) {
            // Character Name Section
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                Label("Character Name", systemImage: "person.text.rectangle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                TextField("Enter character name", text: $viewModel.name)
                    .textFieldStyle(.roundedBorder)
                    .disabled(viewModel.character != nil)
                    .onChange(of: viewModel.name) {
                        viewModel.markAsChanged()
                    }

                HelperText(text: "Sets the folder name in Personas/", icon: "folder")
            }

            Divider()

            // Metadata Section
            if let character = viewModel.character {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                    Label("Character Info", systemImage: "info.circle")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)

                    VStack(spacing: DesignSystem.Spacing.sm) {
                        MetadataCard(
                            icon: "tag",
                            label: "Version",
                            value: character.versionDisplay
                        )

                        MetadataCard(
                            icon: "calendar.badge.plus",
                            label: "Created",
                            value: character.createdAt.formatted(date: .abbreviated, time: .shortened)
                        )

                        MetadataCard(
                            icon: "clock",
                            label: "Modified",
                            value: character.lastModified.formatted(date: .abbreviated, time: .shortened)
                        )
                    }
                }

                Divider()

                // Knowledge Base Stats
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                    Label("Knowledge Base", systemImage: "books.vertical")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)

                    HStack(spacing: DesignSystem.Spacing.md) {
                        StatCard(
                            value: "\(character.knowledgeFiles.count)",
                            label: "Files",
                            icon: "doc.text"
                        )

                        StatCard(
                            value: formatNumber(character.totalKnowledgeWords),
                            label: "Words",
                            icon: "text.word.spacing"
                        )
                    }
                }
            }

            Spacer()
        }
        .padding(DesignSystem.Spacing.lg)
        .frame(minWidth: 250, idealWidth: 280, maxWidth: 320)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Markdown Editor
    private var markdownEditor: some View {
        VStack(spacing: 0) {
            // Editor toolbar
            HStack {
                Label("Persona Markdown", systemImage: "doc.text")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)

                if viewModel.hasUnsavedChanges {
                    let changedCount = viewModel.getChangedLineNumbers().count
                    StatusBadge(
                        text: "\(changedCount) line\(changedCount == 1 ? "" : "s") changed",
                        status: .warning,
                        showIcon: false
                    )
                }

                Spacer()

                // Line count
                HStack(spacing: DesignSystem.Spacing.xs) {
                    Image(systemName: "list.number")
                        .font(.caption2)
                    Text("\(lineCount) lines")
                        .font(.caption.monospacedDigit())
                }
                .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, DesignSystem.Spacing.lg)
            .padding(.vertical, DesignSystem.Spacing.md)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // Editor with line indicators
            GeometryReader { geometry in
                HStack(alignment: .top, spacing: 0) {
                    // Line change indicators
                    if viewModel.hasUnsavedChanges {
                        LineChangeIndicatorView(
                            content: viewModel.markdownContent,
                            changedLines: viewModel.getChangedLineNumbers()
                        )
                    }

                    TextEditor(text: $viewModel.markdownContent)
                        .font(.system(.body, design: .monospaced))
                        .frame(width: geometry.size.width - (viewModel.hasUnsavedChanges ? 4 : 0), height: geometry.size.height)
                        .onChange(of: viewModel.markdownContent) {
                            viewModel.markAsChanged()
                        }
                }
            }
            .background(Color(nsColor: .textBackgroundColor))
        }
    }

    // MARK: - Helpers
    private var wordCount: Int {
        viewModel.markdownContent.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count
    }

    private var lineCount: Int {
        viewModel.markdownContent.components(separatedBy: .newlines).count
    }

    private func formatNumber(_ num: Int) -> String {
        if num >= 1000 {
            return String(format: "%.1fK", Double(num) / 1000.0)
        }
        return "\(num)"
    }

    private func handleCancel() {
        if viewModel.hasUnsavedChanges {
            showingDiscardAlert = true
        } else {
            onCancel()
        }
    }
}

// MARK: - Metadata Card
struct MetadataCard: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(width: 16)

            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Text(value)
                .font(.caption)
                .foregroundStyle(.primary)
        }
        .padding(DesignSystem.Spacing.sm)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small))
    }
}

// MARK: - Stat Card
struct StatCard: View {
    let value: String
    let label: String
    let icon: String

    var body: some View {
        VStack(spacing: DesignSystem.Spacing.xs) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.title2.weight(.semibold).monospacedDigit())
                .foregroundStyle(.primary)

            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(DesignSystem.Spacing.md)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
    }
}

// MARK: - Save Confirmation Sheet
struct SaveConfirmationSheet: View {
    let viewModel: CharacterEditorViewModel
    let onConfirm: () -> Void
    let onCancel: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: DesignSystem.Spacing.lg) {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxs) {
                    Text("Review Changes")
                        .font(.title3.weight(.semibold))

                    Text("\(viewModel.getLineDiff().filter { $0.type != .unchanged }.count) changes to review")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: DesignSystem.Spacing.sm) {
                    Button("Cancel") {
                        onCancel()
                    }
                    .keyboardShortcut(.cancelAction)
                    .help("Cancel (Esc)")

                    Button {
                        onConfirm()
                    } label: {
                        Label("Save Changes", systemImage: "checkmark.circle.fill")
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .help("Save changes (⌘⏎)")
                }
            }
            .padding(DesignSystem.Spacing.lg)
            .background(.regularMaterial)

            Divider()

            // Diff legend
            HStack(spacing: DesignSystem.Spacing.lg) {
                DiffLegendItem(color: DesignSystem.Colors.success, label: "Added")
                DiffLegendItem(color: DesignSystem.Colors.error, label: "Removed")
                DiffLegendItem(color: DesignSystem.Colors.warning, label: "Modified")
            }
            .padding(.horizontal, DesignSystem.Spacing.lg)
            .padding(.vertical, DesignSystem.Spacing.sm)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // Diff view
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(viewModel.getLineDiff()) { line in
                        DiffLineView(line: line)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(nsColor: .textBackgroundColor))
        }
        .frame(width: 750, height: 550)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large))
    }
}

// MARK: - Diff Legend Item
struct DiffLegendItem: View {
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.xs) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 12, height: 12)

            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Diff Line View
struct DiffLineView: View {
    let line: DiffLine

    var body: some View {
        HStack(spacing: 0) {
            // Line indicator
            Rectangle()
                .fill(indicatorColor)
                .frame(width: 4)

            // Line number
            Text(line.lineNumber.map { String($0) } ?? "-")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 44, alignment: .trailing)
                .padding(.trailing, DesignSystem.Spacing.sm)

            // Change type indicator
            Text(changeSymbol)
                .font(.system(.caption, design: .monospaced).weight(.bold))
                .foregroundStyle(indicatorColor)
                .frame(width: 16)

            // Line content
            Text(line.text.isEmpty ? " " : line.text)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(textColor)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 3)
        .padding(.trailing, DesignSystem.Spacing.md)
        .background(backgroundColor)
    }

    private var changeSymbol: String {
        switch line.type {
        case .added: return "+"
        case .removed: return "-"
        case .modified: return "~"
        case .unchanged: return " "
        }
    }

    private var indicatorColor: Color {
        switch line.type {
        case .added: return DesignSystem.Colors.success
        case .removed: return DesignSystem.Colors.error
        case .modified: return DesignSystem.Colors.warning
        case .unchanged: return .clear
        }
    }

    private var backgroundColor: Color {
        switch line.type {
        case .added: return DesignSystem.Colors.successBackground
        case .removed: return DesignSystem.Colors.errorBackground
        case .modified: return DesignSystem.Colors.warningBackground
        case .unchanged: return .clear
        }
    }

    private var textColor: Color {
        switch line.type {
        case .removed: return .secondary
        default: return .primary
        }
    }
}

// MARK: - Line Change Indicator View
struct LineChangeIndicatorView: View {
    let content: String
    let changedLines: Set<Int>

    // Calculate the line height to match TextEditor's monospaced body font
    private var lineHeight: CGFloat {
        let font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        // TextEditor line height includes some padding
        return font.ascender - font.descender + font.leading + 4
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(1...max(1, content.components(separatedBy: .newlines).count), id: \.self) { lineNum in
                Rectangle()
                    .fill(changedLines.contains(lineNum) ? DesignSystem.Colors.warning : Color.clear)
                    .frame(width: 4, height: lineHeight)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 7) // Match TextEditor's internal top padding
    }
}

// MARK: - Metadata Row (Legacy - keeping for compatibility)
struct MetadataRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Text(value)
                .font(.caption)
        }
    }
}
