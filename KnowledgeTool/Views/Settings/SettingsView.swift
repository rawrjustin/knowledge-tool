import SwiftUI
import Supabase

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(APIKeyManager.self) private var apiKeyManager

    // Callback for when repository path changes
    var onRepositoryPathChanged: (() -> Void)?

    // Callback for when Supabase config changes
    var onSupabaseConfigChanged: (() -> Void)?

    @State private var assemblyAIKey: String = ""
    @State private var openAIKey: String = ""
    @State private var perplexityKey: String = ""
    @State private var pineconeKey: String = ""
    @State private var pineconeIndexName: String = ""
    @State private var sportsDataIOKey: String = ""

    @State private var isSelectingFolder = false
    @State private var selectedPineconeEnvironment: APIKeyManager.PineconeEnvironment = .development
    @State private var showingSaveConfirmation = false
    @State private var recentlySavedKey: APIKeyManager.APIService?

    // Supabase
    @State private var supabaseURL: String = ""
    @State private var supabaseAnonKey: String = ""
    @State private var supabaseSyncEnabled: Bool = false
    @State private var supabaseConnectionStatus: SupabaseConnectionStatus = .notConfigured

    /// Check if Supabase is configured based on local state (for immediate UI updates)
    private var isSupabaseConfigured: Bool {
        !supabaseURL.isEmpty && !supabaseAnonKey.isEmpty
    }

    enum SupabaseConnectionStatus: Equatable {
        case notConfigured
        case testing
        case connected
        case failed(String)

        var statusBadge: (text: String, status: StatusBadge.Status)? {
            switch self {
            case .notConfigured: return nil
            case .testing: return ("Testing...", .warning)
            case .connected: return ("Connected", .success)
            case .failed: return ("Failed", .error)
            }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
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

                // MARK: - Sports Data
                Section {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
                        APIKeyRow(
                            title: "SportsData.io",
                            icon: "sportscourt.fill",
                            placeholder: "Your API key",
                            key: $sportsDataIOKey,
                            isConfigured: !sportsDataIOKey.isEmpty,
                            recentlySaved: recentlySavedKey == .sportsDataIO,
                            description: "Powers live sports data for teams, players, and stats"
                        ) { newValue in
                            saveKeyWithFeedback(newValue, for: .sportsDataIO)
                        }
                    }
                    .padding(.vertical, DesignSystem.Spacing.sm)
                } header: {
                    SettingsSectionHeader(title: "Sports Data", icon: "sportscourt.fill", optional: true)
                } footer: {
                    HStack(spacing: DesignSystem.Spacing.xs) {
                        Image(systemName: "link")
                            .foregroundStyle(.secondary)
                        Link("Get a key at sportsdata.io", destination: URL(string: "https://sportsdata.io")!)
                    }
                    .font(.caption)
                }

                // MARK: - Supabase (Cloud Sync)
                Section {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
                        // Sync Toggle
                        Toggle(isOn: $supabaseSyncEnabled) {
                            HStack {
                                Label("Enable Cloud Sync", systemImage: "icloud")
                                    .font(.subheadline.weight(.semibold))

                                if let badge = supabaseConnectionStatus.statusBadge {
                                    StatusBadge(text: badge.text, status: badge.status)
                                }
                            }
                        }
                        .onChange(of: supabaseSyncEnabled) { _, newValue in
                            apiKeyManager.supabaseSyncEnabled = newValue
                            onSupabaseConfigChanged?()
                        }
                        .disabled(!isSupabaseConfigured)

                        Divider()

                        // Project URL
                        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                            Label("Project URL", systemImage: "link")
                                .font(.subheadline.weight(.semibold))

                            TextField("https://xxxx.supabase.co", text: $supabaseURL)
                                .textFieldStyle(.roundedBorder)
                                .onChange(of: supabaseURL) { _, newValue in
                                    apiKeyManager.supabaseURL = newValue
                                    supabaseConnectionStatus = .notConfigured
                                    onSupabaseConfigChanged?()
                                }
                        }

                        // Anon Key
                        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                            Label("Anon Key", systemImage: "key")
                                .font(.subheadline.weight(.semibold))

                            SecureField("sb_publishable_...", text: $supabaseAnonKey)
                                .textFieldStyle(.roundedBorder)
                                .onChange(of: supabaseAnonKey) { _, newValue in
                                    apiKeyManager.supabaseAnonKey = newValue
                                    supabaseConnectionStatus = .notConfigured
                                    onSupabaseConfigChanged?()
                                }
                        }

                        // Test Connection Button
                        if isSupabaseConfigured {
                            Button {
                                Task {
                                    await testSupabaseConnection()
                                }
                            } label: {
                                Label("Test Connection", systemImage: "antenna.radiowaves.left.and.right")
                            }
                            .buttonStyle(.bordered)
                            .disabled(supabaseConnectionStatus == .testing)
                        }
                    }
                    .padding(.vertical, DesignSystem.Spacing.sm)
                } header: {
                    SettingsSectionHeader(title: "Supabase (Cloud Sync)", icon: "icloud", optional: true)
                } footer: {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                        if case .failed(let error) = supabaseConnectionStatus {
                            HStack(spacing: DesignSystem.Spacing.xs) {
                                Image(systemName: "exclamationmark.triangle")
                                    .foregroundStyle(DesignSystem.Colors.error)
                                Text(error)
                            }
                            .font(.caption)
                        } else {
                            HelperText(text: "Share characters across devices and with other users", icon: "person.2")
                        }
                    }
                }

                // MARK: - Updates
                UpdateSettingsSection()

                // MARK: - Local Repository
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
                    HelperText(text: "Local storage for characters when cloud sync is unavailable", icon: "info.circle")
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
        .frame(width: 520, height: 700)
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
        if let key = apiKeyManager.getAPIKey(for: .sportsDataIO) {
            sportsDataIOKey = key
        }
        // Load Pinecone index name
        pineconeIndexName = apiKeyManager.pineconeIndexName
        // Load Supabase settings
        supabaseURL = apiKeyManager.supabaseURL
        supabaseAnonKey = apiKeyManager.supabaseAnonKey
        supabaseSyncEnabled = apiKeyManager.supabaseSyncEnabled
    }

    private func testSupabaseConnection() async {
        supabaseConnectionStatus = .testing

        do {
            guard let url = URL(string: supabaseURL) else {
                await MainActor.run {
                    supabaseConnectionStatus = .failed("Invalid URL format")
                }
                return
            }

            // Create Supabase client directly to test connection
            let client = SupabaseClient(
                supabaseURL: url,
                supabaseKey: supabaseAnonKey
            )

            // Try to query the profiles table - this validates the connection
            // Using a simple struct just for the test query
            struct ProfileIdOnly: Decodable {
                let id: UUID
            }

            let _: [ProfileIdOnly] = try await client
                .from("profiles")
                .select("id")
                .limit(1)
                .execute()
                .value

            await MainActor.run {
                supabaseConnectionStatus = .connected
            }
        } catch {
            await MainActor.run {
                supabaseConnectionStatus = .failed(error.localizedDescription)
            }
        }
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
    SettingsView(onRepositoryPathChanged: nil)
        .environment(APIKeyManager())
}
