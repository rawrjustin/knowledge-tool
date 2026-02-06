import SwiftUI

/// Multi-version chat view for comparing responses across different character versions
struct VersionComparisonChatView: View {
    @State private var viewModel: VersionComparisonViewModel
    @State private var userInput: String = ""
    @State private var showVersionPicker = false
    @FocusState private var isInputFocused: Bool

    let characterName: String
    let initialVersions: [Character]
    let repository: CombinedCharacterRepository
    let apiKeyManager: APIKeyManager
    let onClose: () -> Void

    init(
        characterName: String,
        initialVersions: [Character] = [],
        repository: CombinedCharacterRepository,
        apiKeyManager: APIKeyManager,
        onClose: @escaping () -> Void
    ) {
        self.characterName = characterName
        self.initialVersions = initialVersions
        self.repository = repository
        self.apiKeyManager = apiKeyManager
        self.onClose = onClose
        self._viewModel = State(initialValue: VersionComparisonViewModel(
            repository: repository,
            apiKeyManager: apiKeyManager
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header

            Divider()

            // Main content
            if viewModel.selectedVersions.isEmpty {
                emptyState
            } else {
                // Split pane chat columns
                chatColumns
            }

            // Input area (only if versions selected)
            if !viewModel.selectedVersions.isEmpty {
                Divider()
                inputArea
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .task {
            // Use pre-loaded versions if available, otherwise load from repository
            if !initialVersions.isEmpty {
                viewModel.setVersions(initialVersions)
            } else {
                await viewModel.loadVersions(for: characterName)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: DesignSystem.Spacing.lg) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Compare Versions")
                    .font(.title3.weight(.semibold))

                Text(characterName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Version count
            if !viewModel.selectedVersions.isEmpty {
                HStack(spacing: DesignSystem.Spacing.xs) {
                    Image(systemName: "square.split.2x1")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("\(viewModel.selectedVersions.count) of \(VersionComparisonViewModel.maxVersionsToCompare) versions")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Add version button
            Button {
                showVersionPicker.toggle()
            } label: {
                Label("Add Version", systemImage: "plus")
                    .font(.subheadline)
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.selectedVersions.count >= VersionComparisonViewModel.maxVersionsToCompare)
            .popover(isPresented: $showVersionPicker, arrowEdge: .bottom) {
                versionPickerPopover
            }

            // Clear chat
            if viewModel.chatMessages.values.contains(where: { !$0.isEmpty }) {
                Button {
                    viewModel.clearChatHistory()
                } label: {
                    Label("Clear Chat", systemImage: "trash")
                        .font(.subheadline)
                }
                .buttonStyle(.bordered)
            }

            // Close button
            Button("Close") {
                onClose()
            }
            .keyboardShortcut(.cancelAction)
        }
        .padding(DesignSystem.Spacing.lg)
        .background(.regularMaterial)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: DesignSystem.Spacing.xl) {
            Spacer()

            Image(systemName: "square.split.2x1.fill")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)

            VStack(spacing: DesignSystem.Spacing.sm) {
                Text("Select Versions to Compare")
                    .font(.title3.weight(.medium))

                Text("Choose 2-4 versions of \(characterName) to chat with simultaneously")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if viewModel.isLoading {
                ProgressView("Loading versions...")
            } else if viewModel.versions.isEmpty {
                Text("No versions available")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                Button {
                    showVersionPicker = true
                } label: {
                    Label("Select Versions", systemImage: "plus.circle.fill")
                }
                .buttonStyle(.borderedProminent)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }

    // MARK: - Chat Columns

    private var chatColumns: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            HStack(alignment: .top, spacing: DesignSystem.Spacing.lg) {
                ForEach(Array(viewModel.selectedVersions.enumerated()), id: \.element.id) { index, version in
                    VersionChatColumn(
                        version: version,
                        label: viewModel.label(for: version),
                        messages: viewModel.chatMessages[version.id] ?? [],
                        isExecuting: viewModel.isExecuting[version.id] ?? false,
                        error: viewModel.errors[version.id],
                        onRemove: {
                            viewModel.deselectVersion(version)
                        }
                    )
                    .frame(width: 380)
                }

                // Add more versions button
                if viewModel.selectedVersions.count < VersionComparisonViewModel.maxVersionsToCompare {
                    addVersionColumn
                }
            }
            .padding(DesignSystem.Spacing.lg)
        }
        .frame(maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }

    // MARK: - Add Version Column

    private var addVersionColumn: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            Spacer()

            Button {
                showVersionPicker = true
            } label: {
                VStack(spacing: DesignSystem.Spacing.md) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(.blue)

                    Text("Add Version")
                        .font(.subheadline.weight(.medium))

                    if viewModel.selectedVersions.count < VersionComparisonViewModel.versionLabels.count {
                        Text(VersionComparisonViewModel.versionLabels[viewModel.selectedVersions.count])
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .frame(width: 200)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large))
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8, 4]))
                .foregroundStyle(Color.secondary.opacity(0.3))
        )
    }

    // MARK: - Input Area

    private var inputArea: some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            TextField("Type a message to test all versions...", text: $userInput)
                .textFieldStyle(.plain)
                .padding(DesignSystem.Spacing.md)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .disabled(viewModel.isAnyExecuting)
                .focused($isInputFocused)
                .onSubmit {
                    sendMessage()
                }

            Button {
                sendMessage()
            } label: {
                if viewModel.isAnyExecuting {
                    ProgressView()
                        .scaleEffect(0.8)
                        .frame(width: 32, height: 32)
                } else {
                    Image(systemName: "paperplane.fill")
                        .font(.title3)
                        .foregroundStyle(userInput.isEmpty ? .gray : .blue)
                        .frame(width: 32, height: 32)
                }
            }
            .buttonStyle(.plain)
            .disabled(userInput.isEmpty || viewModel.isAnyExecuting)
        }
        .padding(DesignSystem.Spacing.lg)
        .background(.bar)
    }

    // MARK: - Version Picker Popover

    private var versionPickerPopover: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Select Version")
                    .font(.subheadline.weight(.semibold))

                Spacer()

                Text("\(viewModel.selectedVersions.count)/\(VersionComparisonViewModel.maxVersionsToCompare)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(DesignSystem.Spacing.md)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            if viewModel.isLoading {
                ProgressView()
                    .padding(DesignSystem.Spacing.xl)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(viewModel.versions) { version in
                            VersionPickerRow(
                                version: version,
                                isSelected: viewModel.isSelected(version),
                                isDisabled: viewModel.selectedVersions.count >= VersionComparisonViewModel.maxVersionsToCompare && !viewModel.isSelected(version),
                                onToggle: {
                                    if viewModel.isSelected(version) {
                                        viewModel.deselectVersion(version)
                                    } else {
                                        viewModel.selectVersion(version)
                                    }
                                }
                            )

                            if version.id != viewModel.versions.last?.id {
                                Divider()
                                    .padding(.leading, 44)
                            }
                        }
                    }
                }
                .frame(maxHeight: 300)
            }
        }
        .frame(width: 280)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Actions

    private func sendMessage() {
        guard !userInput.isEmpty && !viewModel.isAnyExecuting else { return }

        let message = userInput
        userInput = ""

        Task {
            await viewModel.sendMessage(message)
        }
    }
}

// MARK: - Version Chat Column

struct VersionChatColumn: View {
    let version: Character
    let label: String
    let messages: [ChatMessage]
    let isExecuting: Bool
    let error: String?
    let onRemove: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: DesignSystem.Spacing.sm) {
                        Text(label)
                            .font(.subheadline.weight(.semibold))

                        Text(version.versionDisplay)
                            .font(.caption.monospacedDigit())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.15))
                            .foregroundStyle(.blue)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }

                    Text(version.lastModified.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                // Remove button
                Button {
                    onRemove()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Remove from comparison")
            }
            .padding(DesignSystem.Spacing.md)
            .background(.regularMaterial)

            Divider()

            // Error banner
            if let error = error {
                HStack(spacing: DesignSystem.Spacing.sm) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.caption)

                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
                .padding(DesignSystem.Spacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.red.opacity(0.1))
            }

            // Messages
            ScrollView {
                LazyVStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                    ForEach(messages.filter { $0.role != .system }) { message in
                        ChatBubble(message: message)
                    }

                    // Loading indicator
                    if isExecuting {
                        HStack(spacing: DesignSystem.Spacing.sm) {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Generating...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(DesignSystem.Spacing.md)
                    }
                }
                .padding(DesignSystem.Spacing.md)
            }
            .frame(maxHeight: .infinity)
            .background(Color(nsColor: .textBackgroundColor))
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large))
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
}

// MARK: - Chat Bubble

struct ChatBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user {
                Spacer(minLength: 40)
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                Text(message.content)
                    .font(.body)
                    .padding(DesignSystem.Spacing.md)
                    .background(message.role == .user ? Color.blue.opacity(0.15) : Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))

                Text(message.timestamp.formatted(date: .omitted, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: 320, alignment: message.role == .user ? .trailing : .leading)

            if message.role == .assistant {
                Spacer(minLength: 40)
            }
        }
    }
}

// MARK: - Version Picker Row

struct VersionPickerRow: View {
    let version: Character
    let isSelected: Bool
    let isDisabled: Bool
    let onToggle: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button {
            onToggle()
        } label: {
            HStack(spacing: DesignSystem.Spacing.md) {
                // Selection indicator
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.subheadline)
                    .foregroundStyle(isSelected ? Color.blue : Color.secondary.opacity(0.5))

                // Version info
                VStack(alignment: .leading, spacing: 2) {
                    Text(version.versionDisplay)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(isDisabled ? .secondary : .primary)

                    Text(version.lastModified.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                // Word count
                Text("\(wordCount(version.markdownContent)) words")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, DesignSystem.Spacing.md)
            .padding(.vertical, DesignSystem.Spacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .background(isSelected ? Color.blue.opacity(0.08) : (isHovered && !isDisabled ? Color.primary.opacity(0.04) : Color.clear))
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private func wordCount(_ text: String) -> Int {
        text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count
    }
}
