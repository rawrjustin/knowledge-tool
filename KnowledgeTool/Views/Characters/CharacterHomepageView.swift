import SwiftUI

// MARK: - Character Homepage View

/// Full-screen homepage showing all available characters in a compact grid.
/// Displayed on launch before any character is selected.
struct CharacterHomepageView: View {
    let characters: [Character]
    let isLoading: Bool
    let backgroundJobs: [BackgroundJob]
    let repository: CombinedCharacterRepository
    let onSelectCharacter: (Character) -> Void
    let onNewCharacter: () -> Void
    let onSync: () async -> Void
    let onDelete: (String) -> Void

    @State private var searchText = ""
    @State private var sortOrder: SortOrder = .name
    @State private var isSyncing = false
    @State private var showingImportSheet = false

    enum SortOrder: String, CaseIterable {
        case name = "Name"
        case recentlyModified = "Recent"
        case version = "Version"

        var icon: String {
            switch self {
            case .name: return "textformat.abc"
            case .recentlyModified: return "clock"
            case .version: return "number"
            }
        }
    }

    /// Pre-computed card data to avoid repeated work during scroll
    private var cardDataList: [CardData] {
        // Deduplicate by name, keeping latest version
        var latestByName: [String: Character] = [:]
        var versionCounts: [String: Int] = [:]
        for char in characters {
            versionCounts[char.name, default: 0] += 1
            if let existing = latestByName[char.name] {
                if char.version > existing.version {
                    latestByName[char.name] = char
                }
            } else {
                latestByName[char.name] = char
            }
        }

        var unique = Array(latestByName.values)

        // Filter
        if !searchText.isEmpty {
            unique = unique.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }

        // Sort — generating characters always first
        switch sortOrder {
        case .name:
            unique.sort {
                if $0.isGenerating != $1.isGenerating { return $0.isGenerating }
                return $0.name.localizedCompare($1.name) == .orderedAscending
            }
        case .recentlyModified:
            unique.sort {
                if $0.isGenerating != $1.isGenerating { return $0.isGenerating }
                return $0.lastModified > $1.lastModified
            }
        case .version:
            unique.sort {
                if $0.isGenerating != $1.isGenerating { return $0.isGenerating }
                return $0.version > $1.version
            }
        }

        // Build a lookup for background job progress
        var jobsByName: [String: BackgroundJob] = [:]
        for job in backgroundJobs where job.state == .processing {
            jobsByName[job.characterName] = job
        }

        // Pre-compute data
        return unique.map { char in
            let sources = char.isGenerating ? [] : char.knowledgeSources
            let sourceCount = sources.count
            let entryCount = sources.reduce(0) { $0 + $1.entryCount }
            let wordCount = char.isGenerating ? 0 : char.markdownContent.split(separator: " ").count

            return CardData(
                character: char,
                versionCount: versionCounts[char.name] ?? 1,
                sourceCount: sourceCount,
                entryCount: entryCount,
                wordCount: wordCount,
                backgroundJob: jobsByName[char.name]
            )
        }
    }

    private var uniqueCount: Int {
        var seen = Set<String>()
        for char in characters where !char.isGenerating {
            seen.insert(char.name)
        }
        return seen.count
    }

    private let columns = [
        GridItem(.adaptive(minimum: 240, maximum: 340), spacing: DesignSystem.Spacing.md)
    ]

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()

            if isLoading && characters.isEmpty {
                loadingState
            } else if characters.isEmpty {
                emptyState
            } else {
                characterGrid
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            Text("Characters")
                .font(.title2.weight(.bold))

            Text("\(uniqueCount)")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.primary.opacity(0.06)))

            if isLoading {
                ProgressView()
                    .controlSize(.small)
            }

            Spacer()

            // Search
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                TextField("Search...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.subheadline)
                    .frame(width: 140)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small)
                    .stroke(DesignSystem.Colors.inputBorder, lineWidth: 0.5)
            )

            // Sort
            Picker("Sort", selection: $sortOrder) {
                ForEach(SortOrder.allCases, id: \.self) { order in
                    Label(order.rawValue, systemImage: order.icon).tag(order)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 110)

            Button {
                Task {
                    isSyncing = true
                    await onSync()
                    isSyncing = false
                }
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.subheadline)
                    .symbolEffect(.rotate, isActive: isSyncing || isLoading)
            }
            .buttonStyle(.modernSecondary)
            .disabled(isSyncing || isLoading)
            .help("Refresh characters (⌘R)")

            Button {
                showingImportSheet = true
            } label: {
                Label("Import", systemImage: "arrow.down.circle")
                    .font(.subheadline.weight(.medium))
            }
            .buttonStyle(.modernSecondary)
            .help("Import config from Genies dev")

            Button {
                onNewCharacter()
            } label: {
                Label("New", systemImage: "plus")
                    .font(.subheadline.weight(.medium))
            }
            .buttonStyle(.modernPrimary)
            .help("Create new character (⌘N)")
        }
        .padding(.horizontal, DesignSystem.Spacing.xl)
        .padding(.vertical, DesignSystem.Spacing.md)
        .background(.regularMaterial)
        .sheet(isPresented: $showingImportSheet) {
            ImportConfigView(
                repository: repository,
                onImported: { character in
                    showingImportSheet = false
                    onSelectCharacter(character)
                },
                onDismiss: { showingImportSheet = false }
            )
        }
    }

    // MARK: - Character Grid

    private var characterGrid: some View {
        ScrollView {
            let data = cardDataList
            if data.isEmpty {
                VStack(spacing: DesignSystem.Spacing.md) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 28))
                        .foregroundStyle(.tertiary)

                    Text("No characters matching \"\(searchText)\"")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 80)
            } else {
                LazyVGrid(columns: columns, spacing: DesignSystem.Spacing.md) {
                    ForEach(data) { item in
                        CompactCharacterCard(
                            data: item,
                            repository: repository,
                            onSelect: {
                                // Don't allow selecting generating characters
                                guard !item.character.isGenerating else { return }
                                onSelectCharacter(item.character)
                            },
                            onDelete: {
                                onDelete(item.character.name)
                            }
                        )
                    }
                }
                .padding(DesignSystem.Spacing.xl)
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            Image(systemName: "person.3.fill")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)

            Text("No Characters Yet")
                .font(.headline)

            Text("Create your first character to get started.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button {
                onNewCharacter()
            } label: {
                Label("Create Character", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.modernPrimary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Loading State

    private var loadingState: some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            ProgressView()
                .controlSize(.regular)

            Text("Loading characters...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Pre-computed Card Data

/// Pre-computed data for each card to avoid expensive recomputation during scroll.
struct CardData: Identifiable {
    let character: Character
    let versionCount: Int
    let sourceCount: Int
    let entryCount: Int
    let wordCount: Int
    let backgroundJob: BackgroundJob?

    var id: UUID { character.id }

    var isGenerating: Bool { character.isGenerating }
}

// MARK: - Compact Character Card

/// Lightweight, compact card optimized for density and scroll performance.
struct CompactCharacterCard: View {
    let data: CardData
    let repository: CombinedCharacterRepository
    let onSelect: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false
    @State private var showDeleteConfirm = false
    @State private var publishState: PublishState = .unpublished
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 3) {
                // Name + badges
                HStack(spacing: 6) {
                    Text(data.character.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(data.isGenerating ? .secondary : .primary)
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    if data.isGenerating {
                        ProgressView()
                            .controlSize(.mini)
                    } else {
                        Text(data.character.systemPromptType.shortDisplayName)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Capsule().fill(promptTypeColor))

                        Text("v\(data.character.version)")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }

                // Progress or stats
                if data.isGenerating, let job = data.backgroundJob {
                    // Show generation progress
                    Text(job.progressMessage)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else if data.isGenerating {
                    Text("Creating character...")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    // Stats inline
                    HStack(spacing: DesignSystem.Spacing.sm) {
                        // Publish state dot
                        publishStateDot

                        if data.sourceCount > 0 {
                            miniStat(icon: "folder.fill", value: "\(data.sourceCount)")
                        }
                        if data.entryCount > 0 {
                            miniStat(icon: "brain", value: "\(data.entryCount)")
                        }
                        miniStat(icon: "doc.text", value: formatWordCount(data.wordCount))

                        if data.versionCount > 1 {
                            miniStat(icon: "clock.arrow.circlepath", value: "\(data.versionCount)")
                        }

                        Spacer(minLength: 0)

                        Text(data.character.lastModified.formatted(.relative(presentation: .named)))
                            .font(.caption2)
                            .foregroundStyle(.quaternary)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.horizontal, DesignSystem.Spacing.md)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                    .stroke(
                        data.isGenerating
                            ? Color.orange.opacity(0.3)
                            : (isHovered ? Color.accentColor.opacity(0.35) : DesignSystem.Colors.cardBorder),
                        lineWidth: data.isGenerating ? 1 : (isHovered ? 1 : 0.5)
                    )
            )
            .shadow(
                color: .black.opacity(colorScheme == .dark ? 0.2 : 0.04),
                radius: 3, y: 1
            )
            .opacity(data.isGenerating ? 0.7 : 1.0)
            .contentShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
        }
        .buttonStyle(.plain)
        .onHover { hovering in isHovered = hovering }
        .task {
            let metadata = await repository.loadPublishMetadata(characterName: data.character.name)
            if let configId = metadata?.configId {
                let currentSha = PublishViewModel.contentSha(for: data.character)
                if currentSha == metadata?.publishedSha {
                    publishState = .clean(configId: configId, publishedAt: metadata?.publishedAt ?? "")
                } else {
                    publishState = .dirtyEdits(configId: configId, publishedAt: metadata?.publishedAt ?? "")
                }
            } else {
                publishState = .unpublished
            }
        }
        .contextMenu {
            if !data.isGenerating {
                Button {
                    onSelect()
                } label: {
                    Label("Open", systemImage: "arrow.right.circle")
                }

                Divider()

                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }

    @ViewBuilder
    private var publishStateDot: some View {
        switch publishState {
        case .unpublished:
            EmptyView()
        case .clean:
            Circle()
                .fill(Color.green)
                .frame(width: 6, height: 6)
                .help("Published")
        case .dirtyEdits:
            Circle()
                .fill(Color.orange)
                .frame(width: 6, height: 6)
                .help("Unpublished changes")
        }
    }

    private func miniStat(icon: String, value: String) -> some View {
        HStack(spacing: 2) {
            Image(systemName: icon)
                .font(.system(size: 8))
            Text(value)
                .font(.caption2.weight(.medium).monospacedDigit())
        }
        .foregroundStyle(.tertiary)
    }

    private var promptTypeColor: Color {
        switch data.character.systemPromptType {
        case .conversational: return .blue
        case .roleplay: return .purple
        case .action: return .orange
        }
    }

    private func formatWordCount(_ count: Int) -> String {
        if count >= 1000 {
            return String(format: "%.1fk", Double(count) / 1000.0)
        }
        return "\(count)"
    }
}

#Preview {
    CharacterHomepageView(
        characters: [],
        isLoading: false,
        backgroundJobs: [],
        repository: CombinedCharacterRepository(
            localBaseURL: URL(fileURLWithPath: "/tmp"),
            syncConfig: SupabaseSyncConfig(supabaseURL: "", supabaseAnonKey: "", syncEnabled: false)
        ),
        onSelectCharacter: { _ in },
        onNewCharacter: {},
        onSync: {},
        onDelete: { _ in }
    )
    .frame(width: 900, height: 700)
}
