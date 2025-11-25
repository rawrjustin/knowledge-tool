import SwiftUI

struct SettingsView: View {
    @Environment(APIKeyManager.self) private var apiKeyManager
    @Environment(\.dismiss) private var dismiss

    @State private var assemblyAIKey: String = ""
    @State private var openAIKey: String = ""
    @State private var repositoryPathString: String = ""
    @State private var showingSaveConfirmation = false
    @State private var errorMessage: String?

    // GitHub authentication
    var githubAuthService: GitHubAuthService

    // Callback for when repository path changes
    var onRepositoryPathChanged: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Settings")
                        .font(.title.bold())

                    Text("Configure API keys for Knowledge Tool")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(24)

            Divider()

            // Content
            ScrollView {
                VStack(spacing: 24) {
                    // GitHub Authentication Section
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Image(systemName: "person.badge.key.fill")
                                .foregroundStyle(.blue)
                                .font(.title3)

                            Text("GitHub Authentication")
                                .font(.headline)
                        }

                        if githubAuthService.isAuthenticated, let user = githubAuthService.currentUser {
                            // Authenticated state
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Signed in as \(user.login)")
                                        .font(.subheadline.bold())

                                    Text("Full read/write access")
                                        .font(.caption)
                                        .foregroundStyle(.green)
                                }

                                Spacer()

                                Button("Sign Out") {
                                    githubAuthService.signOut()
                                }
                                .buttonStyle(.bordered)
                            }
                            .padding()
                            .background(Color(nsColor: .textBackgroundColor))
                            .cornerRadius(8)
                        } else {
                            // Read-only state
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(spacing: 8) {
                                    Image(systemName: "book.closed.fill")
                                        .foregroundStyle(.orange)

                                    Text("Read-Only Mode")
                                        .font(.subheadline.bold())
                                }

                                Text("You can browse characters but cannot make changes. Sign in with GitHub to edit characters and add knowledge files.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                Button {
                                    githubAuthService.startOAuthFlow()
                                } label: {
                                    Label("Sign in with GitHub", systemImage: "arrow.right.circle.fill")
                                }
                                .buttonStyle(.borderedProminent)
                            }
                            .padding()
                            .background(Color(nsColor: .textBackgroundColor))
                            .cornerRadius(8)
                        }

                        Text("Characters are synced from the CharacterPrompts repository. Team members with GitHub access can edit and create new characters.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(12)

                    // API Keys Section
                    VStack(alignment: .leading, spacing: 16) {
                        Text("API Keys")
                            .font(.headline)

                        Text("Your API keys are securely stored in the macOS Keychain and never leave your device.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        // AssemblyAI
                        APIKeyField(
                            service: .assemblyAI,
                            key: $assemblyAIKey,
                            isConfigured: apiKeyManager.hasAPIKey(for: .assemblyAI)
                        )

                        // OpenAI
                        APIKeyField(
                            service: .openAI,
                            key: $openAIKey,
                            isConfigured: apiKeyManager.hasAPIKey(for: .openAI)
                        )
                    }
                    .padding()
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(12)

                    // Repository Path Section
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Image(systemName: "folder.fill")
                                .foregroundStyle(.blue)
                                .font(.title3)

                            Text("Character Repository")
                                .font(.headline)
                        }

                        Text("Path to the CharacterPrompts repository containing your AI character personas.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                TextField("Repository path", text: $repositoryPathString)
                                    .textFieldStyle(.roundedBorder)

                                Button {
                                    selectRepositoryFolder()
                                } label: {
                                    Image(systemName: "folder")
                                }
                                .buttonStyle(.bordered)
                                .help("Browse for folder")
                            }

                            HStack(spacing: 12) {
                                if apiKeyManager.hasCustomRepositoryPath {
                                    Button {
                                        apiKeyManager.resetRepositoryPath()
                                        repositoryPathString = apiKeyManager.repositoryPath.path
                                    } label: {
                                        Label("Reset to Default", systemImage: "arrow.counterclockwise")
                                            .font(.caption)
                                    }
                                    .buttonStyle(.bordered)
                                }

                                Spacer()

                                if !repositoryPathString.isEmpty {
                                    let exists = FileManager.default.fileExists(atPath: repositoryPathString)
                                    HStack(spacing: 4) {
                                        Image(systemName: exists ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                            .foregroundStyle(exists ? .green : .orange)
                                            .font(.caption)

                                        Text(exists ? "Path exists" : "Path not found")
                                            .font(.caption)
                                            .foregroundStyle(exists ? .green : .orange)
                                    }
                                }
                            }
                        }
                    }
                    .padding()
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(12)

                    // Information Section
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Getting API Keys")
                            .font(.headline)

                        VStack(alignment: .leading, spacing: 12) {
                            APIKeyInfoRow(
                                service: "AssemblyAI",
                                url: "https://www.assemblyai.com/",
                                description: "Required for video transcription with speaker diarization"
                            )

                            APIKeyInfoRow(
                                service: "OpenAI",
                                url: "https://platform.openai.com/api-keys",
                                description: "Required for summarization and text analysis"
                            )
                        }
                    }
                    .padding()
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(12)

                    // Bundled Dependencies Section
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundStyle(.green)
                                .font(.title3)

                            Text("Bundled Dependencies")
                                .font(.headline)
                        }

                        Text("This app includes all required binaries - no external installations needed!")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        VStack(alignment: .leading, spacing: 8) {
                            BundledDependencyRow(
                                name: "yt-dlp",
                                description: "YouTube video downloader",
                                icon: "arrow.down.circle.fill"
                            )

                            BundledDependencyRow(
                                name: "ffmpeg & ffprobe",
                                description: "Audio/video processing tools",
                                icon: "waveform.circle.fill"
                            )

                            BundledDependencyRow(
                                name: "Node.js",
                                description: "JavaScript runtime for YouTube extraction",
                                icon: "server.rack"
                            )
                        }

                        HStack(spacing: 8) {
                            Image(systemName: "info.circle")
                                .foregroundStyle(.blue)

                            Text("No Homebrew or external dependencies required. Everything works out of the box!")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 4)
                    }
                    .padding()
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(12)
                }
                .padding(24)
            }

            Divider()

            // Footer with buttons
            HStack {
                if showingSaveConfirmation {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)

                        Text("Saved successfully")
                            .font(.subheadline)
                    }
                    .transition(.opacity)
                }

                if let errorMessage = errorMessage {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)

                        Text(errorMessage)
                            .font(.subheadline)
                            .foregroundStyle(.red)
                    }
                    .transition(.opacity)
                }

                Spacer()

                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Save") {
                    saveAPIKeys()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
            .padding(24)
        }
        .frame(width: 600, height: 800)
        .onAppear {
            loadSettings()
        }
    }

    // MARK: - Load Settings
    private func loadSettings() {
        if let key = apiKeyManager.getAPIKey(for: .assemblyAI) {
            assemblyAIKey = key
        }

        if let key = apiKeyManager.getAPIKey(for: .openAI) {
            openAIKey = key
        }

        repositoryPathString = apiKeyManager.repositoryPath.path
    }

    // MARK: - Save Settings
    private func saveAPIKeys() {
        errorMessage = nil

        do {
            // Save AssemblyAI key if provided
            if !assemblyAIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                try apiKeyManager.setAPIKey(assemblyAIKey, for: .assemblyAI)
            }

            // Save OpenAI key if provided
            if !openAIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                try apiKeyManager.setAPIKey(openAIKey, for: .openAI)
            }

            // Save repository path if changed
            let trimmedPath = repositoryPathString.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedPath.isEmpty {
                let newURL = URL(fileURLWithPath: trimmedPath)
                if newURL.path != apiKeyManager.repositoryPath.path {
                    apiKeyManager.repositoryPath = newURL
                    onRepositoryPathChanged?()
                }
            }

            // Show confirmation
            withAnimation {
                showingSaveConfirmation = true
            }

            // Hide confirmation after 2 seconds
            Task {
                try? await Task.sleep(for: .seconds(2))
                await MainActor.run {
                    withAnimation {
                        showingSaveConfirmation = false
                    }
                }
            }

        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Select Repository Folder
    private func selectRepositoryFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select the CharacterPrompts repository folder"
        panel.prompt = "Select"

        panel.begin { response in
            if response == .OK, let url = panel.url {
                repositoryPathString = url.path
            }
        }
    }
}

// MARK: - API Key Field
struct APIKeyField: View {
    let service: APIKeyManager.APIService
    @Binding var key: String
    let isConfigured: Bool

    @State private var isVisible = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(service.displayName, systemImage: "key.fill")
                    .font(.subheadline.bold())

                if isConfigured {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                }
            }

            HStack {
                if isVisible {
                    TextField("Enter API key", text: $key)
                        .textFieldStyle(.roundedBorder)
                } else {
                    SecureField("Enter API key", text: $key)
                        .textFieldStyle(.roundedBorder)
                }

                Button {
                    isVisible.toggle()
                } label: {
                    Image(systemName: isVisible ? "eye.slash.fill" : "eye.fill")
                }
                .buttonStyle(.bordered)
                .help(isVisible ? "Hide API key" : "Show API key")
            }
        }
    }
}

// MARK: - API Key Info Row
struct APIKeyInfoRow: View {
    let service: String
    let url: String
    let description: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(service)
                    .font(.subheadline.bold())

                Spacer()

                if let websiteURL = URL(string: url) {
                    Link("Get API Key", destination: websiteURL)
                        .font(.caption)
                }
            }

            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color(nsColor: .textBackgroundColor))
        .cornerRadius(8)
    }
}

// MARK: - Bundled Dependency Row
struct BundledDependencyRow: View {
    let name: String
    let description: String
    let icon: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.green)
                .font(.title3)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.subheadline.bold())

                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.caption)
        }
        .padding(12)
        .background(Color(nsColor: .textBackgroundColor))
        .cornerRadius(8)
    }
}

#Preview {
    SettingsView(githubAuthService: GitHubAuthService(), onRepositoryPathChanged: nil)
        .environment(APIKeyManager())
}
