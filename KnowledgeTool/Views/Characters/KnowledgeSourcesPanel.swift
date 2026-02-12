import SwiftUI

// MARK: - Knowledge Sources Panel

/// A panel showing all knowledge sources for a character with source-based organization
struct KnowledgeSourcesPanel: View {
    let character: Character
    let repository: CombinedCharacterRepository
    let apiKeyManager: APIKeyManager
    let onSourceAdded: () -> Void
    let onCharacterUpdated: (Character) -> Void

    @Environment(SyncManager.self) private var syncManager
    @State private var selectedSource: KnowledgeSource?
    @State private var showingAddSource = false
    @State private var isUploadingAll = false
    @State private var uploadProgress: String = ""

    var body: some View {
        HSplitView {
            // Left: Sources list
            sourcesList
                .frame(minWidth: 250, idealWidth: 300, maxWidth: 400)

            // Right: Source details
            sourceDetails
                .frame(minWidth: 400, idealWidth: 500)
        }
    }

    // MARK: - Sources List

    private var sourcesList: some View {
        VStack(spacing: 0) {
            // Header with actions
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Knowledge Sources")
                        .font(.headline)

                    Text("\(character.knowledgeSources.count) sources, \(character.totalKnowledgeEntries) memories")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Menu {
                    Button {
                        showingAddSource = true
                    } label: {
                        Label("Add Source...", systemImage: "plus")
                    }

                    Divider()

                    Button {
                        Task { await uploadAllToRAG() }
                    } label: {
                        Label("Upload All to RAG", systemImage: "icloud.and.arrow.up")
                    }
                    .disabled(isUploadingAll || character.knowledgeSources.isEmpty)
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 30)
            }
            .padding(DesignSystem.Spacing.md)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // Upload progress
            if !uploadProgress.isEmpty {
                HStack {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text(uploadProgress)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(DesignSystem.Spacing.sm)
                .background(Color.blue.opacity(0.05))
            }

            // Sources by type
            if character.knowledgeSources.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: DesignSystem.Spacing.md) {
                        ForEach(KnowledgeSourceType.allCases, id: \.self) { type in
                            let sources = character.knowledgeSources.filter { $0.sourceType == type }
                            if !sources.isEmpty {
                                SourceTypeGroup(
                                    type: type,
                                    sources: sources,
                                    selectedSource: $selectedSource
                                )
                            }
                        }
                    }
                    .padding(DesignSystem.Spacing.md)
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .sheet(isPresented: $showingAddSource) {
            BrainAugmentationView(
                character: character,
                repository: repository,
                apiKeyManager: apiKeyManager,
                onComplete: { updated in
                    showingAddSource = false
                    onCharacterUpdated(updated)
                },
                onCancel: { showingAddSource = false }
            )
        }
    }

    private var emptyState: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)

            VStack(spacing: DesignSystem.Spacing.sm) {
                Text("No Knowledge Sources")
                    .font(.headline)

                Text("Add sources like YouTube videos, articles, or notes to build this character's memory.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                showingAddSource = true
            } label: {
                Label("Add First Source", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(DesignSystem.Spacing.xxl)
    }

    // MARK: - Source Details

    @ViewBuilder
    private var sourceDetails: some View {
        if let source = selectedSource {
            SourceDetailView(
                source: source,
                character: character,
                repository: repository,
                apiKeyManager: apiKeyManager,
                onCharacterUpdated: onCharacterUpdated,
                onSourceDeleted: {
                    selectedSource = nil
                }
            )
        } else {
            VStack(spacing: DesignSystem.Spacing.lg) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 48))
                    .foregroundStyle(.tertiary)

                Text("Select a source to view details")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Actions

    private func uploadAllToRAG() async {
        guard let pineconeKey = apiKeyManager.getAPIKey(for: .pinecone),
              let openAIKey = apiKeyManager.getAPIKey(for: .openAI) else {
            return
        }

        isUploadingAll = true
        uploadProgress = "Preparing documents..."

        do {
            let documents = try PineconeService.parseCharacterKnowledge(knowledgeFiles: character.knowledgeFiles)

            guard !documents.isEmpty else {
                uploadProgress = ""
                isUploadingAll = false
                return
            }

            let service = PineconeService(
                apiKey: pineconeKey,
                openAIApiKey: openAIKey,
                indexName: apiKeyManager.pineconeIndexName
            )

            _ = try await service.uploadKnowledge(
                documents: documents,
                namespace: character.name.lowercased().replacingOccurrences(of: " ", with: "_"),
                clearExisting: false,
                onProgress: { message in
                    Task { @MainActor in
                        uploadProgress = message
                    }
                }
            )

            uploadProgress = ""
        } catch {
            uploadProgress = "Upload failed: \(error.localizedDescription)"
        }

        isUploadingAll = false
    }
}

// MARK: - Source Type Group

struct SourceTypeGroup: View {
    let type: KnowledgeSourceType
    let sources: [KnowledgeSource]
    @Binding var selectedSource: KnowledgeSource?

    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Group header
            Button {
                withAnimation(DesignSystem.Animation.quick) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: type.icon)
                        .font(.subheadline)
                        .foregroundStyle(colorFor(type))

                    Text(type.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text("(\(sources.count))")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, DesignSystem.Spacing.sm)
                .padding(.vertical, DesignSystem.Spacing.xs)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Sources
            if isExpanded {
                ForEach(sources) { source in
                    SourceRow(
                        source: source,
                        isSelected: selectedSource?.id == source.id
                    ) {
                        selectedSource = source
                    }
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
    }

    private func colorFor(_ type: KnowledgeSourceType) -> Color {
        switch type.color {
        case "red": return .red
        case "blue": return .blue
        case "purple": return .purple
        case "orange": return .orange
        case "green": return .green
        default: return .secondary
        }
    }
}

// MARK: - Source Row

struct SourceRow: View {
    let source: KnowledgeSource
    let isSelected: Bool
    let onSelect: () -> Void

    @Environment(SyncManager.self) private var syncManager
    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: DesignSystem.Spacing.sm) {
                // Status indicator
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)

                // Content
                VStack(alignment: .leading, spacing: 2) {
                    Text(source.title)
                        .font(.subheadline)
                        .lineLimit(1)

                    HStack(spacing: DesignSystem.Spacing.sm) {
                        Text("\(source.entryCount) memories")
                            .font(.caption2)

                        Text("\(source.totalWordCount) words")
                            .font(.caption2)

                        Text(source.createdAt.formatted(.relative(presentation: .named)))
                            .font(.caption2)
                    }
                    .foregroundStyle(.tertiary)
                }

                Spacer()

                // Cloud sync icon
                if syncManager.canSync {
                    Image(systemName: syncManager.isSyncing ? "icloud.and.arrow.up" : (syncManager.syncError != nil ? "exclamationmark.icloud.fill" : "checkmark.icloud.fill"))
                        .font(.caption)
                        .foregroundStyle(syncManager.isSyncing ? DesignSystem.Colors.info : (syncManager.syncError != nil ? DesignSystem.Colors.error : DesignSystem.Colors.success))
                }

                // Upload status icon
                Image(systemName: source.uploadStatus.icon)
                    .font(.caption)
                    .foregroundStyle(uploadStatusColor)
            }
            .padding(.horizontal, DesignSystem.Spacing.md)
            .padding(.vertical, DesignSystem.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small)
                    .fill(isSelected ? Color.accentColor.opacity(0.1) : (isHovered ? Color.primary.opacity(0.03) : Color.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private var statusColor: Color {
        switch source.uploadStatus {
        case .uploaded: return .green
        case .uploading: return .blue
        case .pending: return .orange
        case .failed: return .red
        }
    }

    private var uploadStatusColor: Color {
        switch source.uploadStatus {
        case .uploaded: return .green
        case .uploading: return .blue
        case .pending: return .secondary
        case .failed: return .red
        }
    }
}

// MARK: - Source Detail View

struct SourceDetailView: View {
    let source: KnowledgeSource
    let character: Character?
    let repository: CombinedCharacterRepository?
    let apiKeyManager: APIKeyManager?
    let onCharacterUpdated: ((Character) -> Void)?
    let onSourceDeleted: (() -> Void)?

    @Environment(SyncManager.self) private var syncManager
    @State private var searchText = ""
    @State private var selectedEntry: KnowledgeEntry?
    @State private var showingDeleteConfirmation = false

    init(source: KnowledgeSource) {
        self.source = source
        self.character = nil
        self.repository = nil
        self.apiKeyManager = nil
        self.onCharacterUpdated = nil
        self.onSourceDeleted = nil
    }

    init(
        source: KnowledgeSource,
        character: Character,
        repository: CombinedCharacterRepository,
        apiKeyManager: APIKeyManager,
        onCharacterUpdated: @escaping (Character) -> Void,
        onSourceDeleted: @escaping () -> Void
    ) {
        self.source = source
        self.character = character
        self.repository = repository
        self.apiKeyManager = apiKeyManager
        self.onCharacterUpdated = onCharacterUpdated
        self.onSourceDeleted = onSourceDeleted
    }

    var filteredEntries: [KnowledgeEntry] {
        if searchText.isEmpty {
            return source.entries
        }
        return source.entries.filter {
            $0.content.localizedCaseInsensitiveContains(searchText) ||
            $0.section.localizedCaseInsensitiveContains(searchText) ||
            $0.keywords.contains { $0.localizedCaseInsensitiveContains(searchText) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                HStack {
                    Image(systemName: source.sourceType.icon)
                        .font(.title2)
                        .foregroundStyle(colorFor(source.sourceType))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(source.title)
                            .font(.headline)

                        if let url = source.sourceURL {
                            Text(url)
                                .font(.caption)
                                .foregroundStyle(.blue)
                                .lineLimit(1)
                        }
                    }

                    Spacer()

                    // Actions menu
                    if character != nil {
                        Menu {
                            Button(role: .destructive) {
                                showingDeleteConfirmation = true
                            } label: {
                                Label("Delete Source...", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .font(.title3)
                        }
                        .menuStyle(.borderlessButton)
                        .frame(width: 30)
                    }

                    // Cloud sync badge
                    if syncManager.canSync {
                        SyncStatusIndicator()
                    }

                    // Upload status badge
                    HStack(spacing: 4) {
                        Image(systemName: source.uploadStatus.icon)
                        Text(source.uploadStatus.rawValue.capitalized)
                    }
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(uploadStatusBackground)
                    .foregroundStyle(uploadStatusForeground)
                    .clipShape(Capsule())
                }

                // Stats
                HStack(spacing: DesignSystem.Spacing.lg) {
                    StatPill(icon: "brain", value: "\(source.entryCount)", label: "Memories")
                    StatPill(icon: "textformat.abc", value: "\(source.totalWordCount)", label: "Words")
                    StatPill(icon: "calendar", value: source.createdAt.formatted(date: .abbreviated, time: .omitted), label: "Added")
                }
            }
            .padding(DesignSystem.Spacing.md)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // Summary section (if apiKeyManager available)
            if let apiKeyManager = apiKeyManager, let character = character {
                SummarySection(
                    source: source,
                    characterName: character.name,
                    apiKeyManager: apiKeyManager,
                    onSummaryGenerated: { _ in
                        // Summary is stored in the view model, could persist to source
                    }
                )
                .padding(DesignSystem.Spacing.sm)

                Divider()
            }

            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search memories...", text: $searchText)
                    .textFieldStyle(.plain)

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(DesignSystem.Spacing.sm)
            .background(Color(nsColor: .textBackgroundColor))

            Divider()

            // Entries list
            if filteredEntries.isEmpty {
                VStack(spacing: DesignSystem.Spacing.md) {
                    Image(systemName: searchText.isEmpty ? "tray" : "magnifyingglass")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)
                    Text(searchText.isEmpty ? "No memories in this source" : "No matches for \"\(searchText)\"")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: DesignSystem.Spacing.sm) {
                        ForEach(filteredEntries) { entry in
                            KnowledgeEntryRow(entry: entry)
                        }
                    }
                    .padding(DesignSystem.Spacing.md)
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .sheet(isPresented: $showingDeleteConfirmation) {
            if let character = character, let repository = repository {
                SourceDeletionSheet(
                    source: source,
                    character: character,
                    repository: repository,
                    onDelete: { updatedCharacter in
                        showingDeleteConfirmation = false
                        onCharacterUpdated?(updatedCharacter)
                        onSourceDeleted?()
                    },
                    onCancel: {
                        showingDeleteConfirmation = false
                    }
                )
            }
        }
    }

    private func colorFor(_ type: KnowledgeSourceType) -> Color {
        switch type.color {
        case "red": return .red
        case "blue": return .blue
        case "purple": return .purple
        case "orange": return .orange
        case "green": return .green
        default: return .secondary
        }
    }

    private var uploadStatusBackground: Color {
        switch source.uploadStatus {
        case .uploaded: return .green.opacity(0.1)
        case .uploading: return .blue.opacity(0.1)
        case .pending: return .orange.opacity(0.1)
        case .failed: return .red.opacity(0.1)
        }
    }

    private var uploadStatusForeground: Color {
        switch source.uploadStatus {
        case .uploaded: return .green
        case .uploading: return .blue
        case .pending: return .orange
        case .failed: return .red
        }
    }
}

// MARK: - Stat Pill

struct StatPill: View {
    let icon: String
    let value: String
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
            Text(value)
                .font(.caption.weight(.medium))
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Knowledge Entry Row

struct KnowledgeEntryRow: View {
    let entry: KnowledgeEntry

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            // Header
            Button {
                withAnimation(DesignSystem.Animation.quick) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Text(entry.section)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.blue)

                    // Timestamp badge (if available)
                    if let timestamp = entry.formattedTimestamp {
                        Text(timestamp)
                            .font(.caption2)
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.1))
                            .clipShape(Capsule())
                    }

                    Spacer()

                    Text("\(entry.keywords.count) keywords")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Content preview or full
            Text(entry.content)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(isExpanded ? nil : 2)
                .textSelection(.enabled)

            // Source excerpt (when expanded)
            if isExpanded, let excerpt = entry.sourceExcerpt, !excerpt.isEmpty {
                HStack(alignment: .top, spacing: DesignSystem.Spacing.xs) {
                    Image(systemName: "quote.opening")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text(excerpt)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .italic()
                        .lineLimit(3)
                }
                .padding(DesignSystem.Spacing.xs)
                .background(Color.secondary.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small))
            }

            // Keywords (when expanded)
            if isExpanded && !entry.keywords.isEmpty {
                FlowLayout(spacing: 4) {
                    ForEach(entry.keywords, id: \.self) { keyword in
                        Text(keyword)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.1))
                            .foregroundStyle(.blue)
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .padding(DesignSystem.Spacing.sm)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small))
    }
}
