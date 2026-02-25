import SwiftUI

// MARK: - Version History Panel

/// Collapsible panel showing all versions of a character with comparison options
struct VersionHistoryPanel: View {
    let versions: [Character]
    let currentVersion: Character?
    let isLoading: Bool
    let onVersionSelect: (Character) -> Void
    let onCompareVersions: ([Character]) -> Void
    let onRestoreVersion: (Character) -> Void

    @State private var isExpanded = true
    @State private var selectedForComparison: Set<UUID> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            Button {
                withAnimation(DesignSystem.Animation.smooth) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text("Version History")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Spacer()

                    if !selectedForComparison.isEmpty {
                        Text("\(selectedForComparison.count) selected")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }

                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(DesignSystem.Spacing.md)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider()

                if isLoading {
                    HStack {
                        ProgressView()
                            .controlSize(.small)
                        Text("Loading versions...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(DesignSystem.Spacing.lg)
                } else if versions.isEmpty {
                    VStack(spacing: DesignSystem.Spacing.sm) {
                        Image(systemName: "clock")
                            .font(.title2)
                            .foregroundStyle(.tertiary)
                        Text("No version history")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(DesignSystem.Spacing.lg)
                } else {
                    // Version list
                    VStack(spacing: 0) {
                        ForEach(versions) { version in
                            VersionHistoryRow(
                                version: version,
                                isCurrent: version.id == currentVersion?.id,
                                isSelectedForComparison: selectedForComparison.contains(version.id),
                                onSelect: { onVersionSelect(version) },
                                onToggleComparison: { toggleComparison(version) },
                                onRestore: { onRestoreVersion(version) }
                            )

                            if version.id != versions.last?.id {
                                Divider()
                                    .padding(.leading, 44)
                            }
                        }
                    }

                    // Compare button
                    if selectedForComparison.count >= 2 {
                        Divider()

                        Button {
                            let versionsToCompare = versions.filter { selectedForComparison.contains($0.id) }
                            onCompareVersions(versionsToCompare)
                        } label: {
                            HStack {
                                Image(systemName: "arrow.left.arrow.right")
                                Text("Compare \(selectedForComparison.count) Versions")
                            }
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.modernPrimary)
                        .padding(DesignSystem.Spacing.md)
                    }
                }
            }
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
    }

    private func toggleComparison(_ version: Character) {
        if selectedForComparison.contains(version.id) {
            selectedForComparison.remove(version.id)
        } else if selectedForComparison.count < VersionComparisonViewModel.maxVersionsToCompare {
            selectedForComparison.insert(version.id)
        }
    }
}

// MARK: - Version History Row

struct VersionHistoryRow: View {
    let version: Character
    let isCurrent: Bool
    let isSelectedForComparison: Bool
    let onSelect: () -> Void
    let onToggleComparison: () -> Void
    let onRestore: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            // Comparison checkbox
            Button {
                onToggleComparison()
            } label: {
                Image(systemName: isSelectedForComparison ? "checkmark.circle.fill" : "circle")
                    .font(.subheadline)
                    .foregroundStyle(isSelectedForComparison ? Color.blue : Color.secondary.opacity(0.5))
            }
            .buttonStyle(.plain)
            .help("Select for comparison")

            // Version info
            Button {
                onSelect()
            } label: {
                HStack(spacing: DesignSystem.Spacing.sm) {
                    // Version badge
                    Text(version.versionDisplay)
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(isCurrent ? Color.blue : Color.secondary.opacity(0.2))
                        .foregroundStyle(isCurrent ? .white : .primary)
                        .clipShape(RoundedRectangle(cornerRadius: 4))

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: DesignSystem.Spacing.xs) {
                            Text(version.lastModified.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.primary)

                            if isCurrent {
                                Text("(current)")
                                    .font(.caption2)
                                    .foregroundStyle(.blue)
                            }
                        }

                        Text("\(wordCount(version.markdownContent)) words")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Context menu for additional actions
            Menu {
                Button {
                    onSelect()
                } label: {
                    Label("View Version", systemImage: "eye")
                }

                if !isCurrent {
                    Button {
                        onRestore()
                    } label: {
                        Label("Restore This Version", systemImage: "arrow.uturn.backward")
                    }
                }

                Divider()

                Button {
                    onToggleComparison()
                } label: {
                    Label(
                        isSelectedForComparison ? "Deselect for Comparison" : "Select for Comparison",
                        systemImage: isSelectedForComparison ? "minus.circle" : "plus.circle"
                    )
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .opacity(isHovered ? 1 : 0)
        }
        .padding(.horizontal, DesignSystem.Spacing.md)
        .padding(.vertical, DesignSystem.Spacing.sm)
        .background(isHovered ? Color.primary.opacity(0.04) : Color.clear)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private func wordCount(_ text: String) -> Int {
        text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count
    }
}

// MARK: - Version Diff View

/// Side-by-side diff view comparing two versions
struct VersionDiffView: View {
    let version1: Character
    let version2: Character
    let diffLines: [DiffLine]
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Compare Versions")
                        .font(.title3.weight(.semibold))

                    Text("\(version1.versionDisplay) vs \(version2.versionDisplay)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Stats
                HStack(spacing: DesignSystem.Spacing.lg) {
                    DiffStatBadge(
                        count: diffLines.filter { $0.type == .added }.count,
                        label: "Added",
                        color: DesignSystem.Colors.success
                    )

                    DiffStatBadge(
                        count: diffLines.filter { $0.type == .removed }.count,
                        label: "Removed",
                        color: DesignSystem.Colors.error
                    )
                }

                Button("Close") {
                    onClose()
                }
                .buttonStyle(.modernSecondary)
            }
            .padding(DesignSystem.Spacing.lg)
            .background(.regularMaterial)

            Divider()

            // Diff content
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(diffLines) { line in
                        DiffLineRow(line: line)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(nsColor: .textBackgroundColor))
        }
    }
}

// MARK: - Diff Stat Badge

struct DiffStatBadge: View {
    let count: Int
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Text("\(count)")
                .font(.caption.weight(.semibold).monospacedDigit())
            Text(label)
                .font(.caption)
        }
        .foregroundStyle(color)
    }
}

// MARK: - Diff Line Row

struct DiffLineRow: View {
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
