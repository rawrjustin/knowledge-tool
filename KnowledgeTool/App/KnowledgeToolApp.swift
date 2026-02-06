import SwiftUI

@main
struct KnowledgeToolApp: App {
    @State private var apiKeyManager = APIKeyManager()
    @State private var syncManager: SyncManager?
    @State private var showSupabaseSetup = false

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(apiKeyManager)
                .frame(minWidth: 900, minHeight: 600)
                .task {
                    // Initialize combined repository and sync manager
                    let syncConfig = SupabaseSyncConfig(
                        supabaseURL: apiKeyManager.supabaseURL,
                        supabaseAnonKey: apiKeyManager.supabaseAnonKey,
                        syncEnabled: apiKeyManager.supabaseSyncEnabled
                    )
                    let combinedRepo = CombinedCharacterRepository(
                        localBaseURL: apiKeyManager.repositoryPath,
                        syncConfig: syncConfig
                    )
                    syncManager = SyncManager(apiKeyManager: apiKeyManager, repository: combinedRepo)

                    // Check if Supabase needs setup - show prompt on first launch
                    if !apiKeyManager.hasSupabaseConfigured && !hasSkippedSupabaseSetup {
                        showSupabaseSetup = true
                    } else if apiKeyManager.supabaseSyncEnabled {
                        // Perform startup sync and start periodic sync
                        await syncManager?.performStartupSync()
                        syncManager?.startPeriodicSync()
                    }
                }
                .sheet(isPresented: $showSupabaseSetup) {
                    SupabaseSetupSheet {
                        // On setup complete, reinitialize sync
                        syncManager?.onConfigurationChanged()
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
                Button("Editor") {
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
