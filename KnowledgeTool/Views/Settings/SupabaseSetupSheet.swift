import SwiftUI
import Supabase

/// Sheet that prompts users to configure Supabase for cloud sync
struct SupabaseSetupSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(APIKeyManager.self) private var apiKeyManager

    @State private var supabaseURL: String = ""
    @State private var supabaseAnonKey: String = ""
    @State private var isTestingConnection = false
    @State private var connectionStatus: ConnectionStatus = .notTested
    @State private var enableSyncAfterSetup = true

    var onSetupComplete: (() -> Void)?

    enum ConnectionStatus: Equatable {
        case notTested
        case testing
        case success
        case failed(String)
    }

    private var isConfigValid: Bool {
        !supabaseURL.isEmpty && !supabaseAnonKey.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: DesignSystem.Spacing.md) {
                Image(systemName: "icloud.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.blue)

                Text("Set Up Cloud Sync")
                    .font(.title2.bold())

                Text("Connect to Supabase to sync your characters and knowledge bases across devices and share with others.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .padding(.top, DesignSystem.Spacing.xl)
            .padding(.bottom, DesignSystem.Spacing.lg)

            Divider()

            // Form
            Form {
                Section {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                        Label("Project URL", systemImage: "link")
                            .font(.subheadline.weight(.semibold))

                        TextField("https://xxxx.supabase.co", text: $supabaseURL)
                            .polishedInput()

                        HelperText(text: "Your Supabase project URL", icon: "info.circle")
                    }

                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                        Label("Anon Key", systemImage: "key")
                            .font(.subheadline.weight(.semibold))

                        SecureField("sb_publishable_...", text: $supabaseAnonKey)
                            .polishedInput()

                        HelperText(text: "Your public anon key (safe to use in apps)", icon: "info.circle")
                    }
                } header: {
                    Text("Supabase Credentials")
                }

                Section {
                    Toggle("Enable sync after setup", isOn: $enableSyncAfterSetup)
                } footer: {
                    Text("You can change this later in Settings")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Connection Status
                if connectionStatus != .notTested {
                    Section {
                        HStack {
                            switch connectionStatus {
                            case .notTested:
                                EmptyView()
                            case .testing:
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Testing connection...")
                                    .foregroundStyle(.secondary)
                            case .success:
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                Text("Connected successfully!")
                                    .foregroundStyle(.green)
                            case .failed(let error):
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.red)
                                Text(error)
                                    .foregroundStyle(.red)
                                    .lineLimit(2)
                            }
                            Spacer()
                        }
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            // Footer buttons
            HStack {
                Button("Skip for Now") {
                    // Remember that user skipped so we don't prompt again
                    UserDefaults.standard.set(true, forKey: "hasSkippedSupabaseSetup")
                    dismiss()
                }
                .buttonStyle(.modernSecondary)

                Spacer()

                if connectionStatus == .success {
                    Button("Complete Setup") {
                        saveAndComplete()
                    }
                    .buttonStyle(.modernPrimary)
                } else {
                    Button {
                        Task {
                            await testConnection()
                        }
                    } label: {
                        if isTestingConnection {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Text("Test Connection")
                        }
                    }
                    .buttonStyle(.modernPrimary)
                    .disabled(!isConfigValid || isTestingConnection)
                }
            }
            .padding(DesignSystem.Spacing.lg)
        }
        .frame(width: 480, height: 520)
        .onAppear {
            // Load existing values if any
            supabaseURL = apiKeyManager.supabaseURL
            supabaseAnonKey = apiKeyManager.supabaseAnonKey
        }
    }

    private func testConnection() async {
        connectionStatus = .testing
        isTestingConnection = true

        do {
            guard let url = URL(string: supabaseURL) else {
                connectionStatus = .failed("Invalid URL format")
                isTestingConnection = false
                return
            }

            let client = SupabaseClient(
                supabaseURL: url,
                supabaseKey: supabaseAnonKey
            )

            // Test by querying profiles table
            struct ProfileIdOnly: Decodable {
                let id: UUID
            }

            let _: [ProfileIdOnly] = try await client
                .from("profiles")
                .select("id")
                .limit(1)
                .execute()
                .value

            connectionStatus = .success
        } catch {
            connectionStatus = .failed(error.localizedDescription)
        }

        isTestingConnection = false
    }

    private func saveAndComplete() {
        // Save credentials
        apiKeyManager.supabaseURL = supabaseURL
        apiKeyManager.supabaseAnonKey = supabaseAnonKey
        apiKeyManager.supabaseSyncEnabled = enableSyncAfterSetup

        // Notify completion
        onSetupComplete?()

        dismiss()
    }
}
