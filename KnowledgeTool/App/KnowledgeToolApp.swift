import SwiftUI

@main
struct KnowledgeToolApp: App {
    @State private var apiKeyManager = APIKeyManager()
    @State private var githubAuthService = GitHubAuthService()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(apiKeyManager)
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {}

            CommandGroup(after: .appSettings) {
                Button("Settings...") {
                    NotificationCenter.default.post(name: .openSettings, object: nil)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }

        Settings {
            SettingsView(githubAuthService: githubAuthService)
                .environment(apiKeyManager)
        }
    }
}

extension Notification.Name {
    static let openSettings = Notification.Name("openSettings")
}
