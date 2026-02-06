import SwiftUI

// MARK: - Navigation Section

enum NavigationSection: String, CaseIterable {
    case character = "Character"
    case characterRefinement = "Character Refinement"
    case systemPromptRefinement = "System Prompt Refinement"
}

// MARK: - Navigation Items

enum NavigationItem: String, Identifiable {
    // Character section
    case dashboard = "Dashboard"
    case editor = "Editor"
    case chat = "Chat"
    case versionCompare = "Compare Versions"

    // Character Refinement section
    case videos = "Videos"
    case knowledgeBase = "Knowledge Base"

    // System Prompt Refinement section
    case promptTesting = "Prompt Testing"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .dashboard: return "rectangle.3.group"
        case .editor: return "square.and.pencil"
        case .chat: return "bubble.left.and.bubble.right"
        case .versionCompare: return "square.split.2x1"
        case .videos: return "video.fill"
        case .knowledgeBase: return "books.vertical.fill"
        case .promptTesting: return "network"
        }
    }

    var section: NavigationSection {
        switch self {
        case .dashboard, .editor, .chat, .versionCompare:
            return .character
        case .videos, .knowledgeBase:
            return .characterRefinement
        case .promptTesting:
            return .systemPromptRefinement
        }
    }

    var requiresCharacter: Bool {
        return true
    }

    static var allItems: [NavigationItem] {
        [.dashboard, .editor, .chat, .versionCompare, .videos, .knowledgeBase, .promptTesting]
    }

    static func items(for section: NavigationSection) -> [NavigationItem] {
        allItems.filter { $0.section == section }
    }
}

// MARK: - Content View

struct ContentView: View {
    @Environment(APIKeyManager.self) private var apiKeyManager
    @State private var selectedItem: NavigationItem? = .dashboard // Optional for sidebar selection
    @State private var showingSettings = false
    @State private var showingOnboarding = false

    // Character state
    @State private var characters: [Character] = []
    @State private var selectedCharacter: Character?
    @State private var availableVersions: [Character] = []
    @State private var isLoadingCharacters = false

    // Editor state
    @State private var showingCharacterEditor = false
    @State private var characterToEdit: Character?

    // Shared ViewModels (persist across tab switches)
    @State private var videoViewModel: VideoViewModel

    // Combined repository - syncs local and Supabase
    @State private var combinedRepository: CombinedCharacterRepository

    init() {
        // Initialize combined repository with sync support
        let apiKeyManager = APIKeyManager()
        let syncConfig = SupabaseSyncConfig(
            supabaseURL: apiKeyManager.supabaseURL,
            supabaseAnonKey: apiKeyManager.supabaseAnonKey,
            syncEnabled: apiKeyManager.supabaseSyncEnabled
        )
        self._combinedRepository = State(initialValue: CombinedCharacterRepository(
            localBaseURL: apiKeyManager.repositoryPath,
            syncConfig: syncConfig
        ))

        // Initialize shared video view model
        self._videoViewModel = State(initialValue: VideoViewModel(apiKeyManager: apiKeyManager))
    }

    // Track unsaved changes for sidebar indicator
    @State private var hasUnsavedEditorChanges = false
    @State private var showingQuickSwitcher = false

    var body: some View {
        NavigationSplitView {
            SidebarView(
                selectedItem: $selectedItem,
                hasCharacterSelected: selectedCharacter != nil,
                isVideoProcessing: videoViewModel.processingState.isProcessing,
                hasUnsavedChanges: hasUnsavedEditorChanges
            )
        } detail: {
            VStack(spacing: 0) {
                // Character Selector Bar (Filter Bar Pattern)
                CharacterSelectorView(
                    selectedCharacter: $selectedCharacter,
                    characters: characters,
                    availableVersions: availableVersions,
                    isLoading: isLoadingCharacters,
                    onSync: syncCharacters,
                    onNewCharacter: {
                        characterToEdit = nil
                        showingCharacterEditor = true
                    },
                    onVersionSelected: { version in
                        selectedCharacter = version
                    }
                )
                .background(.regularMaterial)

                Divider()

                DetailView(
                    selectedItem: selectedItem ?? .editor,
                    selectedCharacter: selectedCharacter,
                    availableVersions: availableVersions,
                    apiKeyManager: apiKeyManager,
                    repository: combinedRepository,
                    videoViewModel: videoViewModel,
                    onCharacterSaved: { character in
                        // Refresh character list and versions
                        Task {
                            await loadCharacters()
                            selectedCharacter = character
                            await loadVersions(for: character)
                        }
                    },
                    onCancelEdit: {
                        // Stay on editor
                    }
                )
            }
        }
        .navigationSplitViewStyle(.balanced)
        // Keyboard shortcuts
        .keyboardShortcut("1", modifiers: .command) // Editor
        .keyboardShortcut("2", modifiers: .command) // Chat
        .keyboardShortcut("3", modifiers: .command) // Videos
        .keyboardShortcut("4", modifiers: .command) // Knowledge Base
        .keyboardShortcut("5", modifiers: .command) // Prompt Testing
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NavigateToSection"))) { notification in
            if let section = notification.object as? Int {
                switch section {
                case 1: selectedItem = .editor
                case 2: selectedItem = .chat
                case 3: selectedItem = .videos
                case 4: selectedItem = .knowledgeBase
                case 5: selectedItem = .promptTesting
                default: break
                }
            }
        }
        .sheet(isPresented: $showingCharacterEditor) {
            if characterToEdit == nil {
                // Show creation wizard for new characters
                CharacterCreationWizard(
                    repository: combinedRepository,
                    apiKeyManager: apiKeyManager,
                    onComplete: { character in
                        showingCharacterEditor = false
                        Task {
                            await loadCharacters()
                            selectedCharacter = character
                            await loadVersions(for: character)
                        }
                    },
                    onCancel: {
                        showingCharacterEditor = false
                    }
                )
            } else {
                // Show simple editor for editing existing characters
                CharacterEditorView(
                    mode: .edit(characterToEdit!),
                    repository: combinedRepository,
                    onSave: { character in
                        showingCharacterEditor = false
                        Task {
                            await loadCharacters()
                            selectedCharacter = character
                            await loadVersions(for: character)
                        }
                    },
                    onCancel: {
                        showingCharacterEditor = false
                    }
                )
            }
        }
        .onAppear {
            // Show onboarding on first launch
            if !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") {
                showingOnboarding = true
            }

            // Load characters
            Task {
                await loadCharacters()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openSettings)) { _ in
            showingSettings = true
        }
        // Navigation shortcuts
        .onReceive(NotificationCenter.default.publisher(for: .navigateToSection)) { notification in
            if let section = notification.object as? Int {
                withAnimation(DesignSystem.Animation.quick) {
                    switch section {
                    case 1: selectedItem = .editor
                    case 2: selectedItem = .chat
                    case 3: selectedItem = .videos
                    case 4: selectedItem = .knowledgeBase
                    case 5: selectedItem = .promptTesting
                    default: break
                    }
                }
            }
        }
        // New character shortcut
        .onReceive(NotificationCenter.default.publisher(for: .newCharacter)) { _ in
            characterToEdit = nil
            showingCharacterEditor = true
        }
        // Quick switch character (open picker)
        .onReceive(NotificationCenter.default.publisher(for: .quickSwitchCharacter)) { _ in
            showingQuickSwitcher = true
        }
        // Refresh characters
        .onReceive(NotificationCenter.default.publisher(for: .refreshCharacters)) { _ in
            Task {
                await syncCharacters()
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(
                onRepositoryPathChanged: {
                    // Update the combined repository with the new path and reload characters
                    let syncConfig = SupabaseSyncConfig(
                        supabaseURL: apiKeyManager.supabaseURL,
                        supabaseAnonKey: apiKeyManager.supabaseAnonKey,
                        syncEnabled: apiKeyManager.supabaseSyncEnabled
                    )
                    combinedRepository = CombinedCharacterRepository(
                        localBaseURL: apiKeyManager.repositoryPath,
                        syncConfig: syncConfig
                    )
                    selectedCharacter = nil
                    characters = []
                    availableVersions = []
                    Task {
                        await loadCharacters()
                    }
                },
                onSupabaseConfigChanged: {
                    // Update sync configuration when Supabase settings change
                    let newConfig = SupabaseSyncConfig(
                        supabaseURL: apiKeyManager.supabaseURL,
                        supabaseAnonKey: apiKeyManager.supabaseAnonKey,
                        syncEnabled: apiKeyManager.supabaseSyncEnabled
                    )
                    Task {
                        await combinedRepository.updateSyncConfiguration(newConfig)
                    }
                }
            )
            .environment(apiKeyManager)
        }
        .sheet(isPresented: $showingOnboarding) {
            OnboardingView()
                .environment(apiKeyManager)
                .interactiveDismissDisabled()
        }
        // Quick switcher sheet
        .sheet(isPresented: $showingQuickSwitcher) {
            QuickCharacterSwitcher(
                characters: characters,
                selectedCharacter: $selectedCharacter,
                onDismiss: { showingQuickSwitcher = false }
            )
        }
    }

    // MARK: - Character Loading

    @MainActor
    private func loadCharacters() async {
        isLoadingCharacters = true
        defer { isLoadingCharacters = false }

        // Load from combined repository (handles local + Supabase merge)
        NSLog("[KnowledgeTool] Loading characters from combined repository...")
        do {
            let loadedCharacters = try await combinedRepository.loadAllCharacters()
            NSLog("[KnowledgeTool] Loaded %d characters", loadedCharacters.count)
            characters = loadedCharacters
        } catch {
            NSLog("[KnowledgeTool] Error loading characters: %@", error.localizedDescription)
            characters = []
        }

        NSLog("[KnowledgeTool] Total characters loaded: %d", characters.count)

        // Auto-select first character if none selected
        if selectedCharacter == nil, let firstCharacter = characters.first {
            selectedCharacter = firstCharacter
            NSLog("[KnowledgeTool] Auto-selected first character: %@", firstCharacter.name)
            await loadVersions(for: firstCharacter)
        }
    }

    @MainActor
    private func syncCharacters() async {
        // Force reload characters from repository
        await loadCharacters()
    }

    @MainActor
    private func loadVersions(for character: Character) async {
        // Load all versions from combined repository
        do {
            let versions = try await combinedRepository.loadAllVersions(for: character.name)
            availableVersions = versions.sorted { $0.version > $1.version }
        } catch {
            // Fallback to just the current character if version loading fails
            NSLog("[KnowledgeTool] Error loading versions: %@", error.localizedDescription)
            availableVersions = [character]
        }
    }
}

// MARK: - Sidebar View
struct SidebarView: View {
    @Binding var selectedItem: NavigationItem?
    let hasCharacterSelected: Bool
    var isVideoProcessing: Bool = false
    var hasUnsavedChanges: Bool = false

    var body: some View {
        List(selection: $selectedItem) {
            // Character section
            Section {
                ForEach(NavigationItem.items(for: .character)) { item in
                    SidebarNavigationItem(
                        item: item,
                        isSelected: selectedItem == item,
                        isDisabled: !hasCharacterSelected && item.requiresCharacter,
                        showActivityDot: item == .editor && hasUnsavedChanges
                    )
                }
            } header: {
                SidebarSectionHeader(title: "Character", icon: "person.fill")
            }

            // Character Refinement section
            Section {
                ForEach(NavigationItem.items(for: .characterRefinement)) { item in
                    SidebarNavigationItem(
                        item: item,
                        isSelected: selectedItem == item,
                        isDisabled: !hasCharacterSelected && item.requiresCharacter,
                        isProcessing: item == .videos && isVideoProcessing
                    )
                }
            } header: {
                SidebarSectionHeader(title: "Refinement", icon: "wand.and.stars")
            }

            // System Prompt Refinement section
            Section {
                ForEach(NavigationItem.items(for: .systemPromptRefinement)) { item in
                    SidebarNavigationItem(
                        item: item,
                        isSelected: selectedItem == item,
                        isDisabled: !hasCharacterSelected && item.requiresCharacter
                    )
                }
            } header: {
                SidebarSectionHeader(title: "Testing", icon: "testtube.2")
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Knowledge Tool")
        .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    NotificationCenter.default.post(name: .openSettings, object: nil)
                } label: {
                    Label("Settings", systemImage: "gear")
                }
                .help("Open Settings (⌘,)")
            }
        }
    }
}

// MARK: - Sidebar Section Header
struct SidebarSectionHeader: View {
    let title: String
    let icon: String

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.xs) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Sidebar Navigation Item
struct SidebarNavigationItem: View {
    let item: NavigationItem
    let isSelected: Bool
    let isDisabled: Bool
    var showActivityDot: Bool = false
    var isProcessing: Bool = false

    @State private var isHovered = false

    var body: some View {
        NavigationLink(value: item) {
            HStack(spacing: DesignSystem.Spacing.sm) {
                // Selection indicator
                RoundedRectangle(cornerRadius: 2)
                    .fill(isSelected ? Color.accentColor : Color.clear)
                    .frame(width: 3, height: 20)

                // Icon - filled when selected, outline when not
                Image(systemName: isSelected ? filledIcon : item.icon)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .frame(width: 20)

                // Label
                Text(item.rawValue)
                    .font(.subheadline)
                    .fontWeight(isSelected ? .medium : .regular)
                    .foregroundStyle(isDisabled ? .tertiary : .primary)

                Spacer()

                // Activity indicators
                if isProcessing {
                    ProgressView()
                        .controlSize(.small)
                } else if showActivityDot {
                    Circle()
                        .fill(DesignSystem.Colors.warning)
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.vertical, DesignSystem.Spacing.xxs)
            .contentShape(Rectangle())
        }
        .disabled(isDisabled)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private var filledIcon: String {
        switch item {
        case .dashboard: return "rectangle.3.group.fill"
        case .editor: return "square.and.pencil"
        case .chat: return "bubble.left.and.bubble.right.fill"
        case .versionCompare: return "square.split.2x1.fill"
        case .videos: return "video.fill"
        case .knowledgeBase: return "books.vertical.fill"
        case .promptTesting: return "network"
        }
    }
}

// MARK: - Detail View
struct DetailView: View {
    let selectedItem: NavigationItem
    let selectedCharacter: Character?
    let availableVersions: [Character]
    let apiKeyManager: APIKeyManager
    let repository: CombinedCharacterRepository
    let videoViewModel: VideoViewModel
    let onCharacterSaved: (Character) -> Void
    let onCancelEdit: () -> Void

    var body: some View {
        Group {
            if let character = selectedCharacter {
                switch selectedItem {
                case .dashboard:
                    CharacterDashboardView(
                        character: character,
                        repository: repository,
                        apiKeyManager: apiKeyManager,
                        onCharacterUpdated: onCharacterSaved
                    )
                    .id(character.id) // Force view recreation when character changes
                case .editor:
                    CharacterEditorView(
                        mode: .edit(character),
                        repository: repository,
                        onSave: onCharacterSaved,
                        onCancel: onCancelEdit
                    )
                    .id(character.id) // Force view recreation when character changes
                case .chat:
                    CharacterChatView(character: character, apiKeyManager: apiKeyManager)
                        .id(character.id) // Force view recreation when character changes
                case .versionCompare:
                    VersionComparisonChatView(
                        characterName: character.name,
                        initialVersions: availableVersions,
                        repository: repository,
                        apiKeyManager: apiKeyManager,
                        onClose: {
                            // Navigation handled by sidebar
                        }
                    )
                    .id(character.id)
                case .videos:
                    VideoView(viewModel: videoViewModel)
                case .knowledgeBase:
                    KnowledgeBaseView(character: character, repository: repository, apiKeyManager: apiKeyManager)
                        .id(character.id) // Force view recreation when character changes
                case .promptTesting:
                    PromptTestingView(character: character, apiKeyManager: apiKeyManager)
                        .id(character.id) // Force view recreation when character changes
                }
            } else {
                EmptyStateView(
                    icon: "person.crop.circle.badge.questionmark",
                    title: "No Character Selected",
                    message: "Select a character from the dropdown above, or create a new one to get started.",
                    actionLabel: "Create Character",
                    action: {
                        NotificationCenter.default.post(name: .newCharacter, object: nil)
                    }
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Quick Character Switcher
struct QuickCharacterSwitcher: View {
    let characters: [Character]
    @Binding var selectedCharacter: Character?
    let onDismiss: () -> Void

    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool

    private var uniqueCharacterNames: [String] {
        Array(Set(characters.map { $0.name })).sorted()
    }

    private var filteredCharacterNames: [String] {
        if searchText.isEmpty {
            return uniqueCharacterNames
        }
        return uniqueCharacterNames.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search header
            HStack(spacing: DesignSystem.Spacing.md) {
                Image(systemName: "magnifyingglass")
                    .font(.title3)
                    .foregroundStyle(.secondary)

                TextField("Search characters...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($isSearchFocused)

                KeyboardShortcutHint(keys: "⌘K")
            }
            .padding(DesignSystem.Spacing.lg)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // Character list
            if filteredCharacterNames.isEmpty {
                VStack(spacing: DesignSystem.Spacing.lg) {
                    Image(systemName: searchText.isEmpty ? "person.3" : "magnifyingglass")
                        .font(.system(size: 40))
                        .foregroundStyle(.tertiary)

                    Text(searchText.isEmpty ? "No characters available" : "No results for \"\(searchText)\"")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(DesignSystem.Spacing.xxl)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredCharacterNames, id: \.self) { characterName in
                            QuickSwitcherRow(
                                characterName: characterName,
                                isSelected: characterName == selectedCharacter?.name,
                                character: characters.first(where: { $0.name == characterName })
                            ) {
                                if let character = characters.first(where: { $0.name == characterName }) {
                                    selectedCharacter = character
                                }
                                onDismiss()
                            }

                            if characterName != filteredCharacterNames.last {
                                Divider()
                                    .padding(.leading, 60)
                            }
                        }
                    }
                    .padding(.vertical, DesignSystem.Spacing.sm)
                }
            }
        }
        .frame(width: 400, height: 400)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            isSearchFocused = true
        }
    }
}

// MARK: - Quick Switcher Row
struct QuickSwitcherRow: View {
    let characterName: String
    let isSelected: Bool
    let character: Character?
    let onSelect: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: DesignSystem.Spacing.md) {
                CharacterAvatar(name: characterName, size: 36)

                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxs) {
                    Text(characterName)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    if let character = character {
                        HStack(spacing: DesignSystem.Spacing.sm) {
                            if character.hasKnowledgeBase {
                                HStack(spacing: 2) {
                                    Image(systemName: "books.vertical.fill")
                                        .font(.caption2)
                                    Text("\(character.knowledgeFiles.count)")
                                        .font(.caption2)
                                }
                                .foregroundStyle(.blue)
                            }

                            Text(character.lastModified.formatted(.relative(presentation: .named)))
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.blue)
                }
            }
            .padding(.horizontal, DesignSystem.Spacing.lg)
            .padding(.vertical, DesignSystem.Spacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(isSelected ? Color.accentColor.opacity(0.1) : (isHovered ? Color.primary.opacity(0.05) : Color.clear))
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

#Preview {
    ContentView()
        .environment(APIKeyManager())
        .frame(width: 1000, height: 700)
}
