import SwiftUI

struct CharacterSelectorView: View {
    @Binding var selectedCharacter: Character?
    let characters: [Character]
    let availableVersions: [Character]
    var isLoading: Bool = false
    let onSync: () async -> Void
    let onNewCharacter: () -> Void
    let onVersionSelected: (Character) -> Void
    var onDelete: ((String) -> Void)? = nil

    @Environment(BackgroundJobManager.self) private var backgroundJobManager
    @State private var isSyncing = false
    @State private var showingCharacterPicker = false
    @State private var searchText = ""

    // Get unique character names (folders)
    private var uniqueCharacterNames: [String] {
        Array(Set(characters.map { $0.name })).sorted()
    }

    // Get filtered character names based on search
    private var filteredCharacterNames: [String] {
        if searchText.isEmpty {
            return uniqueCharacterNames
        }
        return uniqueCharacterNames.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }

    // Get selected character name (folder)
    private var selectedCharacterName: String? {
        selectedCharacter?.name
    }

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            // Loading state
            if isLoading {
                HStack(spacing: DesignSystem.Spacing.sm) {
                    ProgressView()
                        .controlSize(.small)

                    Text("Loading characters...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, DesignSystem.Spacing.lg)
                .padding(.vertical, DesignSystem.Spacing.sm)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
            } else {
                // Character selector with avatar
                Button {
                    showingCharacterPicker.toggle()
                } label: {
                    HStack(spacing: DesignSystem.Spacing.md) {
                        // Character avatar
                        if let character = selectedCharacter {
                            CharacterAvatar(name: character.name, size: 32)
                        } else {
                            ZStack {
                                Circle()
                                    .fill(Color.accentColor)
                                    .frame(width: 32, height: 32)

                                Image(systemName: "person.fill")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.white)
                            }
                        }

                        // Character info
                        VStack(alignment: .leading, spacing: 0) {
                            HStack(spacing: DesignSystem.Spacing.xs) {
                                Text(selectedCharacter?.name ?? "Select Character")
                                    .font(.headline)
                                    .foregroundStyle(selectedCharacter == nil ? .white : .primary)

                                if let name = selectedCharacter?.name, backgroundJobManager.isGenerating(characterName: name) {
                                    ProgressView()
                                        .controlSize(.mini)
                                }

                                Image(systemName: "chevron.down")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(selectedCharacter == nil ? .white.opacity(0.8) : .secondary)
                            }

                            if let character = selectedCharacter {
                                Text("Last edited \(character.lastModified.formatted(.relative(presentation: .named)))")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.horizontal, DesignSystem.Spacing.md)
                    .padding(.vertical, DesignSystem.Spacing.sm)
                    .background(selectedCharacter == nil ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                            .stroke(selectedCharacter == nil ? Color.clear : DesignSystem.Colors.cardBorder, lineWidth: 1)
                    )
                }
                .buttonStyle(PressableButtonStyle())
                .disabled(uniqueCharacterNames.isEmpty)
                .fixedSize()
                .help("Switch character (⌘K)")
                .popover(isPresented: $showingCharacterPicker, arrowEdge: .bottom) {
                    CharacterPickerPopover(
                        searchText: $searchText,
                        filteredCharacterNames: filteredCharacterNames,
                        selectedCharacterName: selectedCharacterName,
                        characters: characters,
                        onSelect: { characterName in
                            if let latestVersion = characters.filter({ $0.name == characterName }).max(by: { $0.version < $1.version }) {
                                selectedCharacter = latestVersion
                            }
                            showingCharacterPicker = false
                            searchText = ""
                        },
                        onDelete: onDelete.map { callback in
                            { characterName in
                                showingCharacterPicker = false
                                searchText = ""
                                callback(characterName)
                            }
                        }
                    )
                }

                // Version selector (if multiple versions)
                if selectedCharacter != nil && availableVersions.count > 1 {
                    Menu {
                        ForEach(availableVersions.sorted(by: { $0.version > $1.version })) { version in
                            Button {
                                onVersionSelected(version)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(version.versionDisplay)
                                            .font(.body)

                                        Text(formatDate(version.lastModified))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer()

                                    if version.id == selectedCharacter?.id {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: DesignSystem.Spacing.xs) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Text(selectedCharacter?.versionDisplay ?? "")
                                .font(.subheadline)

                            Image(systemName: "chevron.down")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, DesignSystem.Spacing.md)
                        .padding(.vertical, DesignSystem.Spacing.sm)
                        .background(.regularMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small))
                    }
                    .fixedSize()
                } else if selectedCharacter != nil {
                    // Show version label even if only one version
                    HStack(spacing: DesignSystem.Spacing.xs) {
                        Image(systemName: "clock")
                            .font(.caption)
                            .foregroundStyle(.tertiary)

                        Text(selectedCharacter?.versionDisplay ?? "")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, DesignSystem.Spacing.md)
                    .padding(.vertical, DesignSystem.Spacing.sm)
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small))
                }
            }

            Spacer()

            // New Character button
            Button {
                onNewCharacter()
            } label: {
                Label("New", systemImage: "plus")
                    .font(.subheadline.weight(.medium))
            }
            .buttonStyle(.modernPrimary)
            .help("Create new character (⌘N)")

            // Sync button
            Button {
                Task {
                    isSyncing = true
                    await onSync()
                    isSyncing = false
                }
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.subheadline)
                    .symbolEffect(.rotate, isActive: isSyncing)
            }
            .buttonStyle(.modernSecondary)
            .disabled(isSyncing)
            .help("Refresh characters (⌘R)")
        }
        .padding(DesignSystem.Spacing.md)
    }

    // Helper to format date for version display
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Character Picker Popover
struct CharacterPickerPopover: View {
    @Binding var searchText: String
    let filteredCharacterNames: [String]
    let selectedCharacterName: String?
    let characters: [Character]
    let onSelect: (String) -> Void
    var onDelete: ((String) -> Void)? = nil

    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Search header
            HStack(spacing: DesignSystem.Spacing.sm) {
                Image(systemName: "magnifyingglass")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                TextField("Search characters...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.subheadline)
                    .focused($isSearchFocused)

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }

                // Keyboard hint
                KeyboardShortcutHint(keys: "⌘K")
            }
            .padding(DesignSystem.Spacing.md)
            .background(.regularMaterial)

            Divider()

            // Character list
            if filteredCharacterNames.isEmpty {
                VStack(spacing: DesignSystem.Spacing.md) {
                    Image(systemName: searchText.isEmpty ? "person.crop.circle.badge.questionmark" : "magnifyingglass")
                        .font(.system(size: 32))
                        .foregroundStyle(.tertiary)

                    Text(searchText.isEmpty ? "No characters yet" : "No results for \"\(searchText)\"")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if searchText.isEmpty {
                        Text("Create your first character to get started")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 120)
                .padding(DesignSystem.Spacing.lg)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredCharacterNames, id: \.self) { characterName in
                            CharacterPickerRow(
                                characterName: characterName,
                                isSelected: characterName == selectedCharacterName,
                                character: characters.first(where: { $0.name == characterName }),
                                onSelect: { onSelect(characterName) },
                                onDelete: onDelete.map { callback in
                                    { callback(characterName) }
                                }
                            )

                            if characterName != filteredCharacterNames.last {
                                Divider()
                                    .padding(.leading, 52)
                            }
                        }
                    }
                }
                .frame(maxHeight: 320)
            }
        }
        .frame(width: 300)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            isSearchFocused = true
        }
    }
}

// MARK: - Character Picker Row
struct CharacterPickerRow: View {
    let characterName: String
    let isSelected: Bool
    let character: Character?
    let onSelect: () -> Void
    var onDelete: (() -> Void)? = nil

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 0) {
            Button {
                onSelect()
            } label: {
                HStack(spacing: DesignSystem.Spacing.md) {
                    // Avatar
                    CharacterAvatar(name: characterName, size: 28)

                    // Info
                    VStack(alignment: .leading, spacing: 0) {
                        Text(characterName)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)

                        if let character = character, character.isGenerating {
                            HStack(spacing: 4) {
                                ProgressView()
                                    .controlSize(.mini)
                                Text("Generating...")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                            }
                        } else if let character = character {
                            HStack(spacing: DesignSystem.Spacing.xs) {
                                if character.hasKnowledgeBase {
                                    Image(systemName: "books.vertical.fill")
                                        .font(.caption2)
                                        .foregroundStyle(.blue)
                                }

                                Text("\(character.totalKnowledgeWords) words")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }

                    Spacer()

                    // Selection indicator
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.subheadline)
                            .foregroundStyle(.blue)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Delete button (visible on hover)
            if let onDelete = onDelete, isHovered {
                Button {
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundStyle(.red.opacity(0.8))
                        .padding(DesignSystem.Spacing.xs)
                }
                .buttonStyle(.plain)
                .help("Delete character")
                .transition(.opacity)
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.md)
        .padding(.vertical, DesignSystem.Spacing.sm)
        .background(isSelected ? Color.accentColor.opacity(0.08) : (isHovered ? Color.primary.opacity(0.04) : Color.clear))
        .onHover { hovering in
            withAnimation(DesignSystem.Animation.quick) {
                isHovered = hovering
            }
        }
        .contextMenu {
            if let onDelete = onDelete {
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }
}

#Preview {
    CharacterSelectorView(
        selectedCharacter: .constant(nil),
        characters: [],
        availableVersions: [],
        isLoading: false,
        onSync: {},
        onNewCharacter: {},
        onVersionSelected: { _ in },
        onDelete: { _ in }
    )
    .frame(width: 800)
    .padding()
}
