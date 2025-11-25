import SwiftUI

struct OnboardingView: View {
    @Environment(APIKeyManager.self) private var apiKeyManager
    @Environment(\.dismiss) private var dismiss

    @State private var currentPage = 0
    @State private var assemblyAIKey: String = ""
    @State private var openAIKey: String = ""
    @State private var gitHubPATKey: String = ""
    @State private var showingError: String?
    @FocusState private var focusedField: Field?

    enum Field {
        case assemblyAI
        case openAI
        case gitHubPAT
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Welcome to KnowledgeTool")
                        .font(.title.bold())

                    Text("Let's get you set up in just a few steps")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(24)

            Divider()

            // Content
            Group {
                switch currentPage {
                case 0:
                    WelcomePage()
                case 1:
                    AssemblyAIKeyPage(
                        assemblyAIKey: $assemblyAIKey,
                        showingError: $showingError,
                        focusedField: $focusedField
                    )
                case 2:
                    OpenAIKeyPage(
                        openAIKey: $openAIKey,
                        showingError: $showingError,
                        focusedField: $focusedField
                    )
                case 3:
                    GitHubPATKeyPage(
                        gitHubPATKey: $gitHubPATKey,
                        showingError: $showingError,
                        focusedField: $focusedField
                    )
                default:
                    WelcomePage()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeInOut, value: currentPage)

            Divider()

            // Footer
            HStack {
                // Page indicators
                HStack(spacing: 8) {
                    ForEach(0..<4, id: \.self) { index in
                        Circle()
                            .fill(currentPage == index ? Color.accentColor : Color.secondary.opacity(0.3))
                            .frame(width: 8, height: 8)
                    }
                }

                Spacer()

                if let error = showingError {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)

                        Text(error)
                            .font(.subheadline)
                            .foregroundStyle(.red)
                    }
                }

                Spacer()

                if currentPage > 0 {
                    Button("Back") {
                        withAnimation {
                            currentPage -= 1
                        }
                    }
                }

                if currentPage < 3 {
                    Button("Next") {
                        withAnimation {
                            currentPage += 1
                        }
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("Get Started") {
                        completeOnboarding()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canContinue)
                    .help(missingKeysMessage ?? "Complete setup")
                }
            }
            .padding(24)
        }
        .frame(width: 700, height: 550)
    }

    private var canContinue: Bool {
        let trimmedAssemblyAIKey = assemblyAIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedOpenAIKey = openAIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedGitHubPATKey = gitHubPATKey.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmedAssemblyAIKey.isEmpty && !trimmedOpenAIKey.isEmpty && !trimmedGitHubPATKey.isEmpty
    }

    private var missingKeysMessage: String? {
        let trimmedAssemblyAIKey = assemblyAIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedOpenAIKey = openAIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedGitHubPATKey = gitHubPATKey.trimmingCharacters(in: .whitespacesAndNewlines)

        var missing: [String] = []
        if trimmedAssemblyAIKey.isEmpty { missing.append("AssemblyAI") }
        if trimmedOpenAIKey.isEmpty { missing.append("OpenAI") }
        if trimmedGitHubPATKey.isEmpty { missing.append("GitHub PAT") }

        if missing.isEmpty {
            return nil
        } else if missing.count == 3 {
            return "All API keys are required"
        } else {
            return "\(missing.joined(separator: ", ")) API key\(missing.count > 1 ? "s" : "") required"
        }
    }

    private func completeOnboarding() {
        // Clear focus to ensure SecureField commits its value
        focusedField = nil

        showingError = nil

        let trimmedAssemblyAIKey = assemblyAIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedOpenAIKey = openAIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedGitHubPATKey = gitHubPATKey.trimmingCharacters(in: .whitespacesAndNewlines)

        // Validate that ALL keys are provided
        if trimmedAssemblyAIKey.isEmpty || trimmedOpenAIKey.isEmpty || trimmedGitHubPATKey.isEmpty {
            showingError = missingKeysMessage
            return
        }

        do {
            // Save API keys
            try apiKeyManager.setAPIKey(trimmedAssemblyAIKey, for: .assemblyAI)
            try apiKeyManager.setAPIKey(trimmedOpenAIKey, for: .openAI)
            try apiKeyManager.setAPIKey(trimmedGitHubPATKey, for: .gitHubPAT)

            // Mark onboarding as complete
            UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")

            // Close onboarding
            dismiss()

        } catch {
            showingError = "Failed to save API keys: \(error.localizedDescription)"
        }
    }
}

// MARK: - Welcome Page
struct WelcomePage: View {
    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 28) {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 80))
                    .foregroundStyle(.blue)

                VStack(spacing: 12) {
                    Text("Welcome to KnowledgeTool")
                        .font(.largeTitle.bold())

                    Text("Build and manage AI character prompts")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 16) {
                    FeatureRow(
                        icon: "person.text.rectangle",
                        title: "Character Management",
                        description: "Create, edit, and organize AI character prompts with GitHub sync"
                    )

                    FeatureRow(
                        icon: "waveform.circle.fill",
                        title: "Content Processing",
                        description: "Transcribe videos, articles, and text to build knowledge bases"
                    )

                    FeatureRow(
                        icon: "bubble.left.and.bubble.right.fill",
                        title: "Prompt Testing",
                        description: "Chat with characters and compare prompt variations side-by-side"
                    )
                }
                .padding()
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(12)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - AssemblyAI Key Page
struct AssemblyAIKeyPage: View {
    @Binding var assemblyAIKey: String
    @Binding var showingError: String?
    var focusedField: FocusState<OnboardingView.Field?>.Binding

    private var isKeyEntered: Bool {
        !assemblyAIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 24) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "waveform")
                        .font(.system(size: 72))
                        .foregroundStyle(.blue)

                    if isKeyEntered {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title)
                            .foregroundStyle(.green)
                            .offset(x: 10, y: -10)
                    }
                }

                VStack(spacing: 12) {
                    HStack(spacing: 8) {
                        Text("AssemblyAI API Key")
                            .font(.largeTitle.bold())

                        Text("Required")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(isKeyEntered ? Color.green : Color.red)
                            .cornerRadius(4)
                    }

                    Text("Required for audio transcription and speaker diarization")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Enter your AssemblyAI API key")
                        .font(.headline)

                    SecureField("API Key", text: $assemblyAIKey)
                        .textFieldStyle(.roundedBorder)
                        .font(.body)
                        .focused(focusedField, equals: .assemblyAI)

                    HStack(spacing: 8) {
                        Image(systemName: "lock.shield.fill")
                            .foregroundStyle(.green)
                            .font(.caption)

                        Text("Your API key is securely stored in the macOS Keychain")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 4)
                }
                .padding(20)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(12)
                .frame(maxWidth: 500)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - OpenAI Key Page
struct OpenAIKeyPage: View {
    @Binding var openAIKey: String
    @Binding var showingError: String?
    var focusedField: FocusState<OnboardingView.Field?>.Binding

    private var isKeyEntered: Bool {
        !openAIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 24) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "brain")
                        .font(.system(size: 72))
                        .foregroundStyle(.blue)

                    if isKeyEntered {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title)
                            .foregroundStyle(.green)
                            .offset(x: 10, y: -10)
                    }
                }

                VStack(spacing: 12) {
                    HStack(spacing: 8) {
                        Text("OpenAI API Key")
                            .font(.largeTitle.bold())

                        Text("Required")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(isKeyEntered ? Color.green : Color.red)
                            .cornerRadius(4)
                    }

                    Text("Required for summarization, analysis, chat, and dialogue extraction")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Enter your OpenAI API key")
                        .font(.headline)

                    SecureField("API Key", text: $openAIKey)
                        .textFieldStyle(.roundedBorder)
                        .font(.body)
                        .focused(focusedField, equals: .openAI)

                    HStack(spacing: 8) {
                        Image(systemName: "lock.shield.fill")
                            .foregroundStyle(.green)
                            .font(.caption)

                        Text("Your API key is securely stored in the macOS Keychain")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 4)
                }
                .padding(20)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(12)
                .frame(maxWidth: 500)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - GitHub PAT Key Page
struct GitHubPATKeyPage: View {
    @Binding var gitHubPATKey: String
    @Binding var showingError: String?
    var focusedField: FocusState<OnboardingView.Field?>.Binding

    private var isKeyEntered: Bool {
        !gitHubPATKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 24) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "person.badge.key")
                        .font(.system(size: 72))
                        .foregroundStyle(.blue)

                    if isKeyEntered {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title)
                            .foregroundStyle(.green)
                            .offset(x: 10, y: -10)
                    }
                }

                VStack(spacing: 12) {
                    HStack(spacing: 8) {
                        Text("GitHub Personal Access Token")
                            .font(.largeTitle.bold())

                        Text("Required")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(isKeyEntered ? Color.green : Color.red)
                            .cornerRadius(4)
                    }

                    Text("Required for accessing and syncing character prompts from the repository")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Enter your GitHub Personal Access Token")
                        .font(.headline)

                    SecureField("Personal Access Token", text: $gitHubPATKey)
                        .textFieldStyle(.roundedBorder)
                        .font(.body)
                        .focused(focusedField, equals: .gitHubPAT)

                    HStack(spacing: 8) {
                        Image(systemName: "lock.shield.fill")
                            .foregroundStyle(.green)
                            .font(.caption)

                        Text("Your token is securely stored in the macOS Keychain")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 4)
                }
                .padding(20)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(12)
                .frame(maxWidth: 500)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}


// MARK: - Feature Row
struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.blue)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)

                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}


#Preview {
    OnboardingView()
        .environment(APIKeyManager())
}
