import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(APIKeyManager.self) private var apiKeyManager

    // GitHub Service
    var githubAuthService: GitHubAuthService

    // Callback for when repository path changes
    var onRepositoryPathChanged: (() -> Void)?

    @State private var assemblyAIKey: String = ""
    @State private var openAIKey: String = ""
    @State private var perplexityKey: String = ""
    @State private var pineconeKey: String = ""
    @State private var pineconeIndexName: String = ""
    @State private var githubPAT: String = ""
    @State private var githubRepoOwner: String = ""
    @State private var githubRepoName: String = ""

    @State private var isSelectingFolder = false
    @State private var selectedPineconeEnvironment: APIKeyManager.PineconeEnvironment = .development
    @State private var showingSaveConfirmation = false
    @State private var recentlySavedKey: APIKeyManager.APIService?

    var body: some View {
        NavigationStack {
            Form {
                // MARK: - GitHub Configuration
                Section {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
                        // Repository Settings
                        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                            HStack {
                                Label("Repository", systemImage: "folder")
                                    .font(.subheadline.weight(.semibold))

                                Spacer()

                                Text("Optional")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }

                            HStack(spacing: DesignSystem.Spacing.sm) {
                                TextField("Owner", text: $githubRepoOwner)
                                    .textFieldStyle(.roundedBorder)
                                    .onChange(of: githubRepoOwner) { _, newValue in
                                        apiKeyManager.githubRepoOwner = newValue
                                    }

                                Text("/")
                                    .foregroundStyle(.tertiary)
                                    .font(.title3)

                                TextField("Repository", text: $githubRepoName)
                                    .textFieldStyle(.roundedBorder)
                                    .onChange(of: githubRepoName) { _, newValue in
                                        apiKeyManager.githubRepoName = newValue
                                    }
                            }

                            HelperText(text: "Sync characters with a GitHub repository", icon: "arrow.triangle.2.circlepath")
                        }

                        Divider()

                        // PAT Settings
                        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                            HStack {
                                Label("Access Token", systemImage: "key")
                                    .font(.subheadline.weight(.semibold))

                                if !githubPAT.isEmpty {
                                    StatusBadge(text: "Configured", status: .success)
                                }
                            }

                            SecureField("ghp_...", text: $githubPAT)
                                .textFieldStyle(.roundedBorder)
                                .onChange(of: githubPAT) { _, newValue in
                                    saveKey(newValue, for: .gitHubPAT)
                                    if !newValue.isEmpty {
                                        githubAuthService.useReadOnlyMode()
                                        onRepositoryPathChanged?()
                                    }
                                }

                            HStack {
                                HelperText(text: "Required for private repositories", icon: "lock")
                                Spacer()
                                Link(destination: URL(string: "https://github.com/settings/tokens")!) {
                                    Label("Generate Token", systemImage: "arrow.up.forward")
                                        .font(.caption)
                                }
                            }
                        }
                    }
                    .padding(.vertical, DesignSystem.Spacing.xs)
                } header: {
                    SettingsSectionHeader(title: "GitHub", icon: "externaldrive.connected.to.line.below")
                } footer: {
                    if githubAuthService.isAuthenticated {
                        HStack(spacing: DesignSystem.Spacing.xs) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(DesignSystem.Colors.success)
                            Text("Authenticated as \(githubAuthService.currentUser?.login ?? "Unknown")")
                        }
                        .font(.caption)
                    } else if !githubPAT.isEmpty && !githubRepoOwner.isEmpty {
                        HStack(spacing: DesignSystem.Spacing.xs) {
                            Image(systemName: "key.fill")
                                .foregroundStyle(DesignSystem.Colors.info)
                            Text("Using token for \(githubRepoOwner)/\(githubRepoName)")
                        }
                        .font(.caption)
                    } else {
                        HStack(spacing: DesignSystem.Spacing.xs) {
                            Image(systemName: "externaldrive")
                                .foregroundStyle(.secondary)
                            Text("Characters stored locally only")
                        }
                        .font(.caption)
                    }
                }

                // MARK: - API Keys
                Section {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
                        // OpenAI
                        APIKeyRow(
                            title: "OpenAI",
                            icon: "brain",
                            placeholder: "sk-...",
                            key: $openAIKey,
                            isConfigured: !openAIKey.isEmpty,
                            recentlySaved: recentlySavedKey == .openAI,
                            description: "Powers character conversations"
                        ) { newValue in
                            saveKeyWithFeedback(newValue, for: .openAI)
                        }

                        Divider()

                        // AssemblyAI
                        APIKeyRow(
                            title: "AssemblyAI",
                            icon: "waveform",
                            placeholder: "Your API key",
                            key: $assemblyAIKey,
                            isConfigured: !assemblyAIKey.isEmpty,
                            recentlySaved: recentlySavedKey == .assemblyAI,
                            description: "Transcribes video content"
                        ) { newValue in
                            saveKeyWithFeedback(newValue, for: .assemblyAI)
                        }

                        Divider()

                        // Perplexity
                        APIKeyRow(
                            title: "Perplexity",
                            icon: "magnifyingglass",
                            placeholder: "pplx-...",
                            key: $perplexityKey,
                            isConfigured: !perplexityKey.isEmpty,
                            recentlySaved: recentlySavedKey == .perplexity,
                            description: "Deep research for characters"
                        ) { newValue in
                            saveKeyWithFeedback(newValue, for: .perplexity)
                        }
                    }
                    .padding(.vertical, DesignSystem.Spacing.sm)
                } header: {
                    SettingsSectionHeader(title: "AI Services", icon: "cpu")
                } footer: {
                    HStack(spacing: DesignSystem.Spacing.xs) {
                        Image(systemName: "lock.shield")
                            .foregroundStyle(.secondary)
                        Text("Keys stored securely in Keychain")
                    }
                    .font(.caption)
                }

                // MARK: - Pinecone (RAG)
                Section {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
                        // API Key
                        APIKeyRow(
                            title: "Pinecone",
                            icon: "cylinder.split.1x2",
                            placeholder: "pcsk_...",
                            key: $pineconeKey,
                            isConfigured: !pineconeKey.isEmpty,
                            recentlySaved: recentlySavedKey == .pinecone,
                            description: "Vector database for knowledge"
                        ) { newValue in
                            saveKeyWithFeedback(newValue, for: .pinecone)
                        }

                        Divider()

                        // Index Name
                        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                            HStack {
                                Label("Index Name", systemImage: "list.bullet.rectangle")
                                    .font(.subheadline.weight(.semibold))

                                if !pineconeIndexName.isEmpty {
                                    StatusBadge(text: "Set", status: .success)
                                }
                            }

                            TextField("your-index-name", text: $pineconeIndexName)
                                .textFieldStyle(.roundedBorder)
                                .onChange(of: pineconeIndexName) { _, newValue in
                                    apiKeyManager.pineconeIndexName = newValue
                                }

                            HelperText(text: "Your Pinecone index for storing character knowledge", icon: "info.circle")
                        }
                    }
                    .padding(.vertical, DesignSystem.Spacing.sm)
                } header: {
                    SettingsSectionHeader(title: "Pinecone (RAG)", icon: "cylinder.split.1x2", optional: true)
                } footer: {
                    HStack(spacing: DesignSystem.Spacing.xs) {
                        Image(systemName: "link")
                            .foregroundStyle(.secondary)
                        Link("Create an index at pinecone.io", destination: URL(string: "https://www.pinecone.io")!)
                    }
                    .font(.caption)
                }
                
                // MARK: - Updates
                UpdateSettingsSection()

                // MARK: - Local Repository (Fallback)
                Section {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                        // Current path display
                        HStack(spacing: DesignSystem.Spacing.sm) {
                            Image(systemName: "folder.fill")
                                .foregroundStyle(.blue)
                                .font(.subheadline)

                            Text(apiKeyManager.repositoryPath.path)
                                .font(.caption.monospaced())
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .foregroundStyle(.secondary)

                            Spacer()

                            if apiKeyManager.hasCustomRepositoryPath {
                                StatusBadge(text: "Custom", status: .info, showIcon: false)
                            }
                        }
                        .padding(DesignSystem.Spacing.md)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))

                        // Action buttons
                        HStack(spacing: DesignSystem.Spacing.sm) {
                            Button {
                                isSelectingFolder = true
                                selectFolder()
                            } label: {
                                Label("Choose Folder", systemImage: "folder.badge.plus")
                            }
                            .buttonStyle(.bordered)
                            .disabled(isSelectingFolder)

                            if apiKeyManager.hasCustomRepositoryPath {
                                Button(role: .destructive) {
                                    apiKeyManager.resetRepositoryPath()
                                    onRepositoryPathChanged?()
                                } label: {
                                    Label("Reset", systemImage: "arrow.uturn.backward")
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                } header: {
                    SettingsSectionHeader(title: "Local Storage", icon: "externaldrive")
                } footer: {
                    HelperText(text: "Fallback storage when GitHub is unavailable", icon: "info.circle")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .keyboardShortcut(.return)
                }
            }
            .onAppear {
                loadKeys()
            }
        }
        .frame(width: 520, height: 680)
    }

    private func loadKeys() {
        if let key = apiKeyManager.getAPIKey(for: .assemblyAI) {
            assemblyAIKey = key
        }
        if let key = apiKeyManager.getAPIKey(for: .openAI) {
            openAIKey = key
        }
        if let key = apiKeyManager.getAPIKey(for: .perplexity) {
            perplexityKey = key
        }
        if let key = apiKeyManager.getAPIKey(for: .pinecone) {
            pineconeKey = key
        }
        if let key = apiKeyManager.getAPIKey(for: .gitHubPAT) {
            githubPAT = key
        }
        // Load GitHub repo settings
        githubRepoOwner = apiKeyManager.githubRepoOwner
        githubRepoName = apiKeyManager.githubRepoName
        // Load Pinecone index name
        pineconeIndexName = apiKeyManager.pineconeIndexName
    }

    private func saveKey(_ key: String, for service: APIKeyManager.APIService) {
        apiKeyManager.setAPIKey(key, for: service)
    }

    private func saveKeyWithFeedback(_ key: String, for service: APIKeyManager.APIService) {
        apiKeyManager.setAPIKey(key, for: service)
        withAnimation(DesignSystem.Animation.quick) {
            recentlySavedKey = service
        }
        // Reset after a delay
        Task {
            try? await Task.sleep(for: .seconds(2))
            await MainActor.run {
                withAnimation(DesignSystem.Animation.quick) {
                    if recentlySavedKey == service {
                        recentlySavedKey = nil
                    }
                }
            }
        }
    }
    
    private func selectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select the folder containing your Personas directory"
        
        panel.begin { response in
            isSelectingFolder = false
            if response == .OK, let url = panel.url {
                apiKeyManager.repositoryPath = url
                onRepositoryPathChanged?()
            }
        }
    }
}

// MARK: - Settings Section Header
struct SettingsSectionHeader: View {
    let title: String
    let icon: String
    var optional: Bool = false

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.xs) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(title)

            if optional {
                Text("Optional")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, DesignSystem.Spacing.xs)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(Capsule())
            }
        }
    }
}

// MARK: - API Key Row
struct APIKeyRow: View {
    let title: String
    let icon: String
    let placeholder: String
    @Binding var key: String
    let isConfigured: Bool
    var recentlySaved: Bool = false
    var description: String? = nil
    let onSave: (String) -> Void

    @State private var isVisible = false
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            HStack {
                Label(title, systemImage: icon)
                    .font(.subheadline.weight(.semibold))

                Spacer()

                if recentlySaved {
                    HStack(spacing: DesignSystem.Spacing.xxs) {
                        Image(systemName: "checkmark")
                            .font(.caption.weight(.bold))
                        Text("Saved")
                            .font(.caption)
                    }
                    .foregroundStyle(DesignSystem.Colors.success)
                    .transition(.scale.combined(with: .opacity))
                } else if isConfigured {
                    StatusBadge(text: "Configured", status: .success)
                }
            }

            HStack(spacing: DesignSystem.Spacing.sm) {
                Group {
                    if isVisible {
                        TextField(placeholder, text: $key)
                    } else {
                        SecureField(placeholder, text: $key)
                    }
                }
                .textFieldStyle(.roundedBorder)
                .focused($isFocused)
                .onChange(of: key) { _, newValue in
                    onSave(newValue)
                }

                Button {
                    isVisible.toggle()
                } label: {
                    Image(systemName: isVisible ? "eye.slash" : "eye")
                        .font(.subheadline)
                }
                .buttonStyle(.bordered)
                .help(isVisible ? "Hide key" : "Show key")
            }

            if let description = description {
                HelperText(text: description, icon: nil)
            }
        }
        .animation(DesignSystem.Animation.quick, value: recentlySaved)
    }
}

// MARK: - API Key Field (Legacy)
struct APIKeyField: View {
    let service: APIKeyManager.APIService
    @Binding var key: String
    let isConfigured: Bool

    @State private var isVisible = false

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            HStack {
                Label(service.displayName, systemImage: "key.fill")
                    .font(.subheadline.bold())

                if isConfigured {
                    StatusBadge(text: "Configured", status: .success)
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

// MARK: - Bundled Dependency Row
struct BundledDependencyRow: View {
    let name: String
    let description: String
    let icon: String

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            Image(systemName: icon)
                .foregroundStyle(DesignSystem.Colors.success)
                .font(.title3)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxs) {
                Text(name)
                    .font(.subheadline.bold())

                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(DesignSystem.Colors.success)
                .font(.caption)
        }
        .padding(DesignSystem.Spacing.md)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
    }
}

#Preview {
    SettingsView(githubAuthService: GitHubAuthService(), onRepositoryPathChanged: nil)
        .environment(APIKeyManager())
}
