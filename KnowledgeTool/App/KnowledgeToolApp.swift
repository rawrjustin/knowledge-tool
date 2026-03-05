import SwiftUI

@main
struct KnowledgeToolApp: App {
    @State private var apiKeyManager = APIKeyManager()
    @State private var syncManager: SyncManager
    @State private var backgroundJobManager = BackgroundJobManager()
    @State private var authViewModel = AuthViewModel()
    @State private var showSupabaseSetup = false

    init() {
        let akm = APIKeyManager()
        let syncConfig = SupabaseSyncConfig(
            supabaseURL: akm.supabaseURL,
            supabaseAnonKey: akm.supabaseAnonKey,
            syncEnabled: akm.supabaseSyncEnabled
        )
        let combinedRepo = CombinedCharacterRepository(
            localBaseURL: akm.repositoryPath,
            syncConfig: syncConfig
        )
        self._apiKeyManager = State(initialValue: akm)
        self._syncManager = State(initialValue: SyncManager(apiKeyManager: akm, repository: combinedRepo))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(apiKeyManager)
                .environment(syncManager)
                .environment(backgroundJobManager)
                .environment(authViewModel)
                .frame(minWidth: 900, minHeight: 600)
                .task {
                    NotificationService.shared.requestAuthorization()
                }
                .task {
                    await authViewModel.checkExistingSession()
                }
                .task {
                    // For users who completed old onboarding without Supabase, prompt them to set it up
                    let hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
                    if hasCompletedOnboarding && !apiKeyManager.hasSupabaseConfigured && !hasSkippedSupabaseSetup {
                        // User completed old onboarding but doesn't have Supabase - prompt them
                        showSupabaseSetup = true
                    } else if apiKeyManager.supabaseSyncEnabled {
                        // Perform startup sync and start periodic sync
                        await syncManager.performStartupSync()
                        syncManager.startPeriodicSync()
                    }
                }
                .sheet(isPresented: $showSupabaseSetup) {
                    SupabaseSetupSheet {
                        // On setup complete, reinitialize sync via SyncManager
                        syncManager.onConfigurationChanged()
                    }
                    .environment(apiKeyManager)
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Character") {
                    NotificationCenter.default.post(name: .newCharacter, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)
            }

            // Replace default Settings menu item with our custom one
            CommandGroup(replacing: .appSettings) {
                Button("Settings...") {
                    NotificationCenter.default.post(name: .openSettings, object: nil)
                }
                .keyboardShortcut(",", modifiers: .command)
            }

            // Check for Updates menu item
            CommandGroup(after: .appInfo) {
                CheckForUpdatesButton()
            }

            // Navigation shortcuts
            CommandMenu("Navigate") {
                Button("Raw Markdown") {
                    NotificationCenter.default.post(name: .navigateToSection, object: 1)
                }
                .keyboardShortcut("1", modifiers: .command)

                Button("Chat") {
                    NotificationCenter.default.post(name: .navigateToSection, object: 2)
                }
                .keyboardShortcut("2", modifiers: .command)

                Button("Videos") {
                    NotificationCenter.default.post(name: .navigateToSection, object: 3)
                }
                .keyboardShortcut("3", modifiers: .command)

                Button("Knowledge Base") {
                    NotificationCenter.default.post(name: .navigateToSection, object: 4)
                }
                .keyboardShortcut("4", modifiers: .command)

                Button("Prompt Testing") {
                    NotificationCenter.default.post(name: .navigateToSection, object: 5)
                }
                .keyboardShortcut("5", modifiers: .command)

                Button("Persona Test") {
                    NotificationCenter.default.post(name: .navigateToSection, object: 6)
                }
                .keyboardShortcut("6", modifiers: .command)

                Button("Sports Data") {
                    NotificationCenter.default.post(name: .navigateToSection, object: 7)
                }
                .keyboardShortcut("7", modifiers: .command)

                Button("Chat Visualizer") {
                    NotificationCenter.default.post(name: .navigateToSection, object: 8)
                }
                .keyboardShortcut("8", modifiers: .command)

                Divider()

                Button("Quick Switch Character") {
                    NotificationCenter.default.post(name: .quickSwitchCharacter, object: nil)
                }
                .keyboardShortcut("k", modifiers: .command)

                Button("Refresh Characters") {
                    NotificationCenter.default.post(name: .refreshCharacters, object: nil)
                }
                .keyboardShortcut("r", modifiers: .command)
            }
        }
    }
}

extension Notification.Name {
    static let openSettings = Notification.Name("openSettings")
    static let newCharacter = Notification.Name("newCharacter")
    static let navigateToSection = Notification.Name("navigateToSection")
    static let quickSwitchCharacter = Notification.Name("quickSwitchCharacter")
    static let refreshCharacters = Notification.Name("refreshCharacters")
}

// MARK: - Supabase Setup Tracking

/// Track whether user has skipped Supabase setup to avoid prompting every launch
private var hasSkippedSupabaseSetup: Bool {
    get { UserDefaults.standard.bool(forKey: "hasSkippedSupabaseSetup") }
    set { UserDefaults.standard.set(newValue, forKey: "hasSkippedSupabaseSetup") }
}
