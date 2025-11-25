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
    case editor = "Editor"
    case chat = "Chat"

    // Character Refinement section
    case videos = "Videos"
    case knowledgeBase = "Knowledge Base"

    // System Prompt Refinement section
    case promptTesting = "Prompt Testing"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .editor: return "square.and.pencil"
        case .chat: return "bubble.left.and.bubble.right"
        case .videos: return "video.fill"
        case .knowledgeBase: return "books.vertical.fill"
        case .promptTesting: return "network"
        }
    }

    var section: NavigationSection {
        switch self {
        case .editor, .chat:
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
        [.editor, .chat, .videos, .knowledgeBase, .promptTesting]
    }

    static func items(for section: NavigationSection) -> [NavigationItem] {
        allItems.filter { $0.section == section }
    }
}

// MARK: - Content View

struct ContentView: View {
    @Environment(APIKeyManager.self) private var apiKeyManager
    @State private var selectedItem: NavigationItem = .editor
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

    // GitHub Services
    @State private var githubAuthService = GitHubAuthService()
    private var githubAPIService: GitHubAPIService
    private var characterRepository: CharacterRepository

    // Local file repository (fallback when GitHub unavailable)
    @State private var localRepository: LocalCharacterRepository

    init() {
        let authService = GitHubAuthService()
        let apiService = GitHubAPIService(
            getToken: { authService.token },
            isReadOnly: { authService.isReadOnly }
        )
        let repository = CharacterRepository(githubAPI: apiService)

        self.githubAPIService = apiService
        self.characterRepository = repository
        self._githubAuthService = State(initialValue: authService)

        // Initialize local repository with configurable path from APIKeyManager
        // Note: APIKeyManager will use stored path or default to Application Support
        let apiKeyManager = APIKeyManager()
        self._localRepository = State(initialValue: LocalCharacterRepository(baseURL: apiKeyManager.repositoryPath))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Character selector at top
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
            .onChange(of: selectedCharacter) { oldValue, newValue in
                // Load all versions when character changes
                if let character = newValue, oldValue?.name != newValue?.name {
                    Task {
                        await loadVersions(for: character)
                    }
                }
            }

            Divider()

            // Main content
            NavigationSplitView {
                SidebarView(
                    selectedItem: $selectedItem,
                    hasCharacterSelected: selectedCharacter != nil
                )
            } detail: {
                DetailView(
                    selectedItem: selectedItem,
                    selectedCharacter: selectedCharacter,
                    apiKeyManager: apiKeyManager,
                    localRepository: localRepository,
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
            .navigationSplitViewStyle(.balanced)
        }
        .sheet(isPresented: $showingCharacterEditor) {
            if characterToEdit == nil {
                // Show creation wizard for new characters
                CharacterCreationWizard(
                    localRepository: localRepository,
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
                    localRepository: localRepository,
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
        .sheet(isPresented: $showingSettings) {
            SettingsView(
                githubAuthService: githubAuthService,
                onRepositoryPathChanged: {
                    // Update the local repository with the new path and reload characters
                    localRepository = LocalCharacterRepository(baseURL: apiKeyManager.repositoryPath)
                    selectedCharacter = nil
                    characters = []
                    availableVersions = []
                    Task {
                        await loadCharacters()
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
    }

    // MARK: - Character Loading

    private func loadCharacters() async {
        isLoadingCharacters = true
        defer { isLoadingCharacters = false }

        NSLog("[KnowledgeTool] Starting to load characters from GitHub...")

        do {
            // Load characters from GitHub repository using the PAT
            characters = try await characterRepository.loadAllCharacters()
            NSLog("[KnowledgeTool] Successfully loaded %d characters from GitHub", characters.count)

            // Auto-select first character if none selected
            if selectedCharacter == nil, let firstCharacter = characters.first {
                selectedCharacter = firstCharacter
                NSLog("[KnowledgeTool] Auto-selected first character: %@", firstCharacter.name)
                // Load versions for the first character
                await loadVersions(for: firstCharacter)
            }
        } catch {
            NSLog("[KnowledgeTool] Error loading characters from GitHub: %@", error.localizedDescription)
            // Fall back to local repository if GitHub fails
            do {
                NSLog("[KnowledgeTool] Falling back to local repository...")
                characters = try await localRepository.loadAllCharacters()
                NSLog("[KnowledgeTool] Loaded %d characters from local", characters.count)
                if selectedCharacter == nil, let firstCharacter = characters.first {
                    selectedCharacter = firstCharacter
                    await loadVersions(for: firstCharacter)
                }
            } catch {
                NSLog("[KnowledgeTool] Error loading characters from local: %@", error.localizedDescription)
            }
        }
    }

    private func syncCharacters() async {
        // Force reload characters from GitHub
        await loadCharacters()
    }

    private func loadVersions(for character: Character) async {
        // For GitHub-loaded characters, we only have one version
        // Version history would require fetching git commits
        availableVersions = [character]
    }
}

// MARK: - Sidebar View
struct SidebarView: View {
    @Binding var selectedItem: NavigationItem
    let hasCharacterSelected: Bool

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $selectedItem) {
                // Character section (no header for top-level items)
                ForEach(NavigationItem.items(for: .character)) { item in
                    NavigationLink(value: item) {
                        Label {
                            Text(item.rawValue)
                                .font(.body)
                        } icon: {
                            Image(systemName: item.icon)
                        }
                    }
                    .disabled(!hasCharacterSelected && item.requiresCharacter)
                    .opacity(!hasCharacterSelected && item.requiresCharacter ? 0.5 : 1.0)
                }

                // Character Refinement section
                Section {
                    ForEach(NavigationItem.items(for: .characterRefinement)) { item in
                        NavigationLink(value: item) {
                            Label {
                                Text(item.rawValue)
                                    .font(.body)
                            } icon: {
                                Image(systemName: item.icon)
                            }
                        }
                        .disabled(!hasCharacterSelected && item.requiresCharacter)
                        .opacity(!hasCharacterSelected && item.requiresCharacter ? 0.5 : 1.0)
                    }
                } header: {
                    Text("Character Refinement")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // System Prompt Refinement section
                Section {
                    ForEach(NavigationItem.items(for: .systemPromptRefinement)) { item in
                        NavigationLink(value: item) {
                            Label {
                                Text(item.rawValue)
                                    .font(.body)
                            } icon: {
                                Image(systemName: item.icon)
                            }
                        }
                        .disabled(!hasCharacterSelected && item.requiresCharacter)
                        .opacity(!hasCharacterSelected && item.requiresCharacter ? 0.5 : 1.0)
                    }
                } header: {
                    Text("System Prompt Refinement")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            // Settings button at bottom - posts notification to open settings
            Button {
                NotificationCenter.default.post(name: .openSettings, object: nil)
            } label: {
                Label("Settings", systemImage: "gear")
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .padding(.vertical, 8)
        }
        .navigationTitle("Knowledge Tool")
        .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 250)
    }
}

// MARK: - Detail View
struct DetailView: View {
    let selectedItem: NavigationItem
    let selectedCharacter: Character?
    let apiKeyManager: APIKeyManager
    let localRepository: LocalCharacterRepository
    let onCharacterSaved: (Character) -> Void
    let onCancelEdit: () -> Void

    var body: some View {
        Group {
            if let character = selectedCharacter {
                switch selectedItem {
                case .editor:
                    CharacterEditorView(
                        mode: .edit(character),
                        localRepository: localRepository,
                        onSave: onCharacterSaved,
                        onCancel: onCancelEdit
                    )
                case .chat:
                    CharacterChatView(character: character, apiKeyManager: apiKeyManager)
                case .videos:
                    VideoView(viewModel: VideoViewModel(apiKeyManager: apiKeyManager))
                case .knowledgeBase:
                    KnowledgeBaseView(character: character, localRepository: localRepository)
                case .promptTesting:
                    PromptTestingView(character: character, apiKeyManager: apiKeyManager)
                }
            } else {
                PlaceholderView(
                    title: "Select a Character to get started",
                    message: "Choose a character from the dropdown above to begin working"
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Placeholder View
struct PlaceholderView: View {
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.fill")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text(title)
                .font(.title2.bold())

            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }
}

#Preview {
    ContentView()
        .environment(APIKeyManager())
        .frame(width: 1000, height: 700)
}
