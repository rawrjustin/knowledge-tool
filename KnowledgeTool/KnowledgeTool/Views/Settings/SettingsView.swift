import SwiftUI

struct SettingsView: View {
    @Environment(APIKeyManager.self) private var apiKeyManager
    @Environment(\.dismiss) private var dismiss

    @State private var assemblyAIKey: String = ""
    @State private var openAIKey: String = ""
    @State private var showingSaveConfirmation = false
    @State private var errorMessage: String?

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

                    // Dependencies Section
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Required Dependencies")
                            .font(.headline)

                        VStack(alignment: .leading, spacing: 12) {
                            DependencyRow(
                                name: "yt-dlp",
                                description: "For downloading videos from URLs",
                                installCommand: "brew install yt-dlp"
                            )

                            DependencyRow(
                                name: "ffmpeg",
                                description: "For extracting audio from video files",
                                installCommand: "brew install ffmpeg"
                            )
                        }

                        Text("Install these dependencies using Homebrew to enable all features.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
        .frame(width: 600, height: 700)
        .onAppear {
            loadAPIKeys()
        }
    }

    // MARK: - Load API Keys
    private func loadAPIKeys() {
        if let key = apiKeyManager.getAPIKey(for: .assemblyAI) {
            assemblyAIKey = key
        }

        if let key = apiKeyManager.getAPIKey(for: .openAI) {
            openAIKey = key
        }
    }

    // MARK: - Save API Keys
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

// MARK: - Dependency Row
struct DependencyRow: View {
    let name: String
    let description: String
    let installCommand: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(name)
                .font(.subheadline.bold())
                .foregroundStyle(.primary)

            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Text(installCommand)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(nsColor: .textBackgroundColor))
                    .cornerRadius(4)

                Button {
                    copyToClipboard(installCommand)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .help("Copy command")
            }
        }
        .padding(12)
        .background(Color(nsColor: .textBackgroundColor))
        .cornerRadius(8)
    }

    private func copyToClipboard(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }
}

#Preview {
    SettingsView()
        .environment(APIKeyManager())
}
