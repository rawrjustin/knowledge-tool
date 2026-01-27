import SwiftUI

@main
struct KnowledgeToolApp: App {
    @State private var apiKeyManager = APIKeyManager()
    @State private var githubAuthService = GitHubAuthService()

    var body: some Scene {
        WindowGroup {
            ContentView(githubAuthService: githubAuthService)
                .environment(apiKeyManager)
                .frame(minWidth: 900, minHeight: 600)
                .onOpenURL { url in
                    // Handle OAuth callback from GitHub
                    if url.scheme == "knowledgetool",
                       url.host == "oauth",
                       let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                       let code = components.queryItems?.first(where: { $0.name == "code" })?.value {
                        Task {
                            try? await githubAuthService.handleOAuthCallback(code: code)
                        }
                    }
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
