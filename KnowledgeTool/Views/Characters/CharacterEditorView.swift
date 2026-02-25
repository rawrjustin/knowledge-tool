import SwiftUI

// MARK: - Raw Markdown View

struct RawMarkdownView: View {
    let character: Character

    @State private var showCopySuccess = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            // Header
            rawMarkdownHeader

            Divider()

            // Content
            HSplitView {
                // Left sidebar - metadata
                metadataSidebar

                // Right side - read-only markdown
                markdownContent
            }
        }
        .frame(minWidth: 800, minHeight: 600)
        .toast(isShowing: $showCopySuccess, message: "Markdown copied to clipboard", style: .success)
    }

    // MARK: - Header

    private var rawMarkdownHeader: some View {
        HStack {
            // Title and info
            HStack(spacing: DesignSystem.Spacing.md) {
                CharacterAvatar(name: character.name, size: 36)

                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxs) {
                    Text(character.name)
                        .font(.title3.weight(.semibold))

                    HStack(spacing: DesignSystem.Spacing.xs) {
                        Text(character.versionDisplay)
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.purple.opacity(0.15))
                            .foregroundStyle(.purple)
                            .clipShape(Capsule())

                        StatusBadge(text: "Read-only", status: .info)
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
            .background(.regularMaterial)
            .clipShape(Capsule())

            // Copy All button
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(character.markdownContent, forType: .string)
                showCopySuccess = true
            } label: {
                Label("Copy All", systemImage: "doc.on.doc")
            }
            .buttonStyle(.modernPrimary)
            .help("Copy full markdown to clipboard")
        }
        .padding(DesignSystem.Spacing.lg)
    }

    // MARK: - Metadata Sidebar

    private var metadataSidebar: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xl) {
            // Metadata Section
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

            Divider()

            // Document Stats
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                Label("Document Stats", systemImage: "chart.bar")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                VStack(spacing: DesignSystem.Spacing.sm) {
                    MetadataCard(
                        icon: "text.word.spacing",
                        label: "Words",
                        value: "\(wordCount)"
                    )

                    MetadataCard(
                        icon: "list.number",
                        label: "Lines",
                        value: "\(lineCount)"
                    )

                    MetadataCard(
                        icon: "number",
                        label: "Sections",
                        value: "\(sectionCount)"
                    )
                }
            }

            Spacer()
        }
        .padding(DesignSystem.Spacing.lg)
        .frame(minWidth: 250, idealWidth: 280, maxWidth: 320)
        .background(.regularMaterial)
    }

    // MARK: - Markdown Content

    private var markdownContent: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Label("Raw Markdown", systemImage: "doc.text")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)

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

            // Read-only content
            ScrollView {
                Text(character.markdownContent)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(DesignSystem.Spacing.lg)
            }
            .background(Color(nsColor: .textBackgroundColor))
        }
    }

    // MARK: - Helpers

    private var wordCount: Int {
        character.markdownContent.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count
    }

    private var lineCount: Int {
        character.markdownContent.components(separatedBy: .newlines).count
    }

    private var sectionCount: Int {
        character.markdownContent.components(separatedBy: "\n").filter { $0.hasPrefix("## ") }.count
    }

    private func formatNumber(_ num: Int) -> String {
        if num >= 1000 {
            return String(format: "%.1fK", Double(num) / 1000.0)
        }
        return "\(num)"
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
    @Bindable var viewModel: CharacterEditorViewModel
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
                    .buttonStyle(.modernPrimary)
                    .help("Save changes")
                }
            }
            .padding(DesignSystem.Spacing.lg)
            .background(.regularMaterial)

            Divider()

            // Version name input
            HStack(spacing: DesignSystem.Spacing.md) {
                Image(systemName: "tag")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                TextField("Version name (e.g. \"new info\", \"justin\")", text: $viewModel.versionName)
                    .polishedInput()
                    .font(.subheadline)

                Text("Optional")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, DesignSystem.Spacing.lg)
            .padding(.vertical, DesignSystem.Spacing.md)
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
            .background(.regularMaterial)

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
