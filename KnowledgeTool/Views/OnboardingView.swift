import SwiftUI
import Supabase

struct OnboardingView: View {
    @Environment(APIKeyManager.self) private var apiKeyManager
    @Environment(\.dismiss) private var dismiss

    @State private var currentPage = 0
    @State private var assemblyAIKey: String = ""
    @State private var openAIKey: String = ""
    @State private var perplexityKey: String = ""
    @State private var supabaseURL: String = ""
    @State private var supabaseAnonKey: String = ""
    @State private var showingError: String?
    @State private var isTestingConnection = false
    @State private var connectionTestPassed = false
    @FocusState private var focusedField: Field?

    enum Field {
        case assemblyAI
        case openAI
        case perplexity
        case supabaseURL
        case supabaseAnonKey
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
                    SupabaseSetupPage(
                        supabaseURL: $supabaseURL,
                        supabaseAnonKey: $supabaseAnonKey,
                        showingError: $showingError,
                        isTestingConnection: $isTestingConnection,
                        connectionTestPassed: $connectionTestPassed,
                        focusedField: $focusedField,
                        onTestConnection: testSupabaseConnection
                    )
                case 2:
                    AssemblyAIKeyPage(
                        assemblyAIKey: $assemblyAIKey,
                        showingError: $showingError,
                        focusedField: $focusedField
                    )
                case 3:
                    OpenAIKeyPage(
                        openAIKey: $openAIKey,
                        showingError: $showingError,
                        focusedField: $focusedField
                    )
                case 4:
                    PerplexityKeyPage(
                        perplexityKey: $perplexityKey,
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
                    ForEach(0..<5, id: \.self) { index in
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
                            showingError = nil
                            currentPage -= 1
                        }
                    }
                }

                if currentPage < 4 {
                    Button("Next") {
                        withAnimation {
                            showingError = nil
                            // Validate Supabase on page 1 before proceeding
                            if currentPage == 1 && !connectionTestPassed {
                                showingError = "Please test your Supabase connection before continuing"
                                return
                            }
                            currentPage += 1
                        }
                    }
                    .buttonStyle(.modernPrimary)
                    .disabled(currentPage == 1 && !connectionTestPassed)
                } else {
                    Button("Get Started") {
                        completeOnboarding()
                    }
                    .buttonStyle(.modernPrimary)
                    .disabled(!canContinue)
                    .help(missingKeysMessage ?? "Complete setup")
                }
            }
            .padding(24)
        }
        .frame(width: 700, height: 600)
    }

    private var canContinue: Bool {
        let trimmedAssemblyAIKey = assemblyAIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedOpenAIKey = openAIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPerplexityKey = perplexityKey.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmedAssemblyAIKey.isEmpty && !trimmedOpenAIKey.isEmpty && !trimmedPerplexityKey.isEmpty && connectionTestPassed
    }

    private var missingKeysMessage: String? {
        let trimmedAssemblyAIKey = assemblyAIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedOpenAIKey = openAIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPerplexityKey = perplexityKey.trimmingCharacters(in: .whitespacesAndNewlines)

        var missing: [String] = []
        if !connectionTestPassed { missing.append("Supabase") }
        if trimmedAssemblyAIKey.isEmpty { missing.append("AssemblyAI") }
        if trimmedOpenAIKey.isEmpty { missing.append("OpenAI") }
        if trimmedPerplexityKey.isEmpty { missing.append("Perplexity") }

        if missing.isEmpty {
            return nil
        } else if missing.count == 4 {
            return "All configuration is required"
        } else {
            return "\(missing.joined(separator: ", ")) \(missing.count > 1 ? "are" : "is") required"
        }
    }

    private func testSupabaseConnection() async {
        isTestingConnection = true
        showingError = nil
        connectionTestPassed = false

        do {
            guard let url = URL(string: supabaseURL.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                showingError = "Invalid URL format"
                isTestingConnection = false
                return
            }

            let client = SupabaseClient(
                supabaseURL: url,
                supabaseKey: supabaseAnonKey.trimmingCharacters(in: .whitespacesAndNewlines)
            )

            // Test by querying characters table
            struct CharacterIdOnly: Decodable {
                let id: UUID
            }

            let _: [CharacterIdOnly] = try await client
                .from("characters")
                .select("id")
                .limit(1)
                .execute()
                .value

            connectionTestPassed = true
        } catch {
            showingError = "Connection failed: \(error.localizedDescription)"
        }

        isTestingConnection = false
    }

    private func completeOnboarding() {
        // Clear focus to ensure SecureField commits its value
        focusedField = nil

        showingError = nil

        let trimmedAssemblyAIKey = assemblyAIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedOpenAIKey = openAIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPerplexityKey = perplexityKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSupabaseURL = supabaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSupabaseAnonKey = supabaseAnonKey.trimmingCharacters(in: .whitespacesAndNewlines)

        // Validate that ALL keys are provided
        if trimmedAssemblyAIKey.isEmpty || trimmedOpenAIKey.isEmpty || trimmedPerplexityKey.isEmpty {
            showingError = missingKeysMessage
            return
        }

        if !connectionTestPassed {
            showingError = "Please configure and test Supabase connection"
            return
        }

        // Save Supabase configuration
        apiKeyManager.supabaseURL = trimmedSupabaseURL
        apiKeyManager.supabaseAnonKey = trimmedSupabaseAnonKey
        apiKeyManager.supabaseSyncEnabled = true

        // Save API keys
        apiKeyManager.setAPIKey(trimmedAssemblyAIKey, for: .assemblyAI)
        apiKeyManager.setAPIKey(trimmedOpenAIKey, for: .openAI)
        apiKeyManager.setAPIKey(trimmedPerplexityKey, for: .perplexity)

        // Mark onboarding as complete
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")

        // Close onboarding
        dismiss()
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
                        icon: "icloud.fill",
                        title: "Team Collaboration",
                        description: "Sync characters and knowledge across your team with Supabase"
                    )

                    FeatureRow(
                        icon: "person.text.rectangle",
                        title: "Character Management",
                        description: "Create, edit, and organize AI character prompts"
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
                .background(.regularMaterial)
                .cornerRadius(12)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Supabase Setup Page
struct SupabaseSetupPage: View {
    @Binding var supabaseURL: String
    @Binding var supabaseAnonKey: String
    @Binding var showingError: String?
    @Binding var isTestingConnection: Bool
    @Binding var connectionTestPassed: Bool
    var focusedField: FocusState<OnboardingView.Field?>.Binding
    var onTestConnection: () async -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 24) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "icloud.fill")
                        .font(.system(size: 72))
                        .foregroundStyle(.blue)

                    if connectionTestPassed {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title)
                            .foregroundStyle(.green)
                            .offset(x: 10, y: -10)
                    }
                }

                VStack(spacing: 12) {
                    HStack(spacing: 8) {
                        Text("Team Sync Setup")
                            .font(.largeTitle.bold())

                        Text("Required")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(connectionTestPassed ? Color.green : Color.red)
                            .cornerRadius(4)
                    }

                    Text("Connect to Supabase to sync characters across your team")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Project URL", systemImage: "link")
                            .font(.headline)

                        TextField("https://xxxx.supabase.co", text: $supabaseURL)
                            .polishedInput()
                            .font(.body)
                            .focused(focusedField, equals: .supabaseURL)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Label("Anon Key", systemImage: "key")
                            .font(.headline)

                        SecureField("eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...", text: $supabaseAnonKey)
                            .polishedInput()
                            .font(.body)
                            .focused(focusedField, equals: .supabaseAnonKey)
                    }

                    HStack {
                        Button {
                            Task {
                                await onTestConnection()
                            }
                        } label: {
                            HStack(spacing: 8) {
                                if isTestingConnection {
                                    ProgressView()
                                        .controlSize(.small)
                                } else if connectionTestPassed {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                }
                                Text(connectionTestPassed ? "Connected" : "Test Connection")
                            }
                        }
                        .buttonStyle(.modernPrimary)
                        .disabled(supabaseURL.isEmpty || supabaseAnonKey.isEmpty || isTestingConnection)

                        Spacer()

                        if connectionTestPassed {
                            Text("Ready to sync!")
                                .font(.subheadline)
                                .foregroundStyle(.green)
                        }
                    }

                    HStack(spacing: 8) {
                        Image(systemName: "person.3.fill")
                            .foregroundStyle(.blue)
                            .font(.caption)

                        Text("All team members should use the same Supabase project to share characters")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 4)
                }
                .padding(20)
                .background(.regularMaterial)
                .cornerRadius(12)
                .frame(maxWidth: 500)
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
                        .polishedInput()
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
                .background(.regularMaterial)
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
                        .polishedInput()
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
                .background(.regularMaterial)
                .cornerRadius(12)
                .frame(maxWidth: 500)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Perplexity Key Page
struct PerplexityKeyPage: View {
    @Binding var perplexityKey: String
    @Binding var showingError: String?
    var focusedField: FocusState<OnboardingView.Field?>.Binding

    private var isKeyEntered: Bool {
        !perplexityKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 24) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "magnifyingglass.circle.fill")
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
                        Text("Perplexity API Key")
                            .font(.largeTitle.bold())

                        Text("Required")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(isKeyEntered ? Color.green : Color.red)
                            .cornerRadius(4)
                    }

                    Text("Powers deep research for rich character creation using sonar-deep-research")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Enter your Perplexity API key")
                        .font(.headline)

                    SecureField("API Key", text: $perplexityKey)
                        .polishedInput()
                        .font(.body)
                        .focused(focusedField, equals: .perplexity)

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
                .background(.regularMaterial)
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
