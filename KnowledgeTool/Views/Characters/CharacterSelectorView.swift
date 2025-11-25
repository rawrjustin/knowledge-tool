import SwiftUI

struct CharacterSelectorView: View {
    @Binding var selectedCharacter: Character?
    let characters: [Character]
    let availableVersions: [Character]
    var isLoading: Bool = false
    let onSync: () async -> Void
    let onNewCharacter: () -> Void
    let onVersionSelected: (Character) -> Void

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
        HStack(spacing: 12) {
            // Loading indicator
            if isLoading {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)

                    Text("Loading characters...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)
            } else {
                // Character dropdown with search - more prominent styling
                Button {
                    showingCharacterPicker.toggle()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "person.fill")
                            .foregroundStyle(selectedCharacter == nil ? .white : .blue)

                        if let character = selectedCharacter {
                            Text(character.name)
                                .font(.headline)
                                .foregroundStyle(.primary)
                        } else {
                            Text("Select Character")
                                .font(.headline)
                                .foregroundStyle(.white)
                        }

                        Image(systemName: "chevron.down")
                            .font(.caption)
                            .foregroundStyle(selectedCharacter == nil ? .white : .secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(selectedCharacter == nil ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .disabled(uniqueCharacterNames.isEmpty)
                .fixedSize()
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
                    }
                )
            }

            // Version dropdown - only visible when character is selected
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
                    HStack(spacing: 6) {
                        Text(selectedCharacter?.versionDisplay ?? "")
                            .font(.subheadline)

                        Image(systemName: "chevron.down")
                            .font(.caption2)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(6)
                }
                .fixedSize()
            } else if selectedCharacter != nil {
                // Show version label even if only one version
                Text(selectedCharacter?.versionDisplay ?? "")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(6)
            }
            } // End of isLoading else block

            // New Character button
            Button {
                onNewCharacter()
            } label: {
                Label("New Character", systemImage: "plus.circle.fill")
                    .font(.subheadline)
            }
            .buttonStyle(.borderedProminent)

            Spacer()

            // Sync button
            Button {
                Task {
                    isSyncing = true
                    await onSync()
                    isSyncing = false
                }
            } label: {
                Label("Sync", systemImage: isSyncing ? "arrow.triangle.2.circlepath" : "arrow.triangle.2.circlepath")
                    .font(.subheadline)
                    .symbolEffect(.rotate, isActive: isSyncing)
            }
            .buttonStyle(.bordered)
            .disabled(isSyncing)
        }
        .padding()
        .background(Color(nsColor: .windowBackgroundColor))
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

    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Search field
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField("Search characters...", text: $searchText)
                    .textFieldStyle(.plain)
                    .focused($isSearchFocused)

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
            .padding(10)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // Character list
            if filteredCharacterNames.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "person.slash")
                        .font(.title2)
                        .foregroundStyle(.secondary)

                    Text(searchText.isEmpty ? "No characters loaded" : "No characters match '\(searchText)'")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 100)
                .padding()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredCharacterNames, id: \.self) { characterName in
                            Button {
                                onSelect(characterName)
                            } label: {
                                HStack {
                                    Text(characterName)
                                        .foregroundStyle(.primary)

                                    Spacer()

                                    // Knowledge base indicator
                                    if let char = characters.first(where: { $0.name == characterName }), char.hasKnowledgeBase {
                                        Image(systemName: "books.vertical.fill")
                                            .foregroundStyle(.blue)
                                            .font(.caption)
                                    }

                                    if characterName == selectedCharacterName {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.blue)
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .background(characterName == selectedCharacterName ? Color.accentColor.opacity(0.1) : Color.clear)

                            if characterName != filteredCharacterNames.last {
                                Divider()
                                    .padding(.leading, 12)
                            }
                        }
                    }
                }
                .frame(maxHeight: 300)
            }
        }
        .frame(width: 280)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            isSearchFocused = true
        }
    }
}

#Preview {
    CharacterSelectorView(
        selectedCharacter: .constant(nil),
        characters: [],
        availableVersions: [],
        isLoading: true,
        onSync: {},
        onNewCharacter: {},
        onVersionSelected: { _ in }
    )
    .frame(width: 800)
}
