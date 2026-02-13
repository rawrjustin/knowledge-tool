import Foundation

/// Manages synchronization between local storage and Supabase
@MainActor
@Observable
final class SyncManager {
    // MARK: - State

    private(set) var isSyncing = false
    private(set) var lastSyncDate: Date?
    private(set) var syncError: String?
    private var consecutiveFailures = 0

    /// Whether Supabase is configured and sync is enabled
    var canSync: Bool {
        apiKeyManager.hasSupabaseConfigured && apiKeyManager.supabaseSyncEnabled
    }

    /// Whether we need to prompt user to configure Supabase
    var needsSupabaseSetup: Bool {
        !apiKeyManager.hasSupabaseConfigured
    }

    // MARK: - Dependencies

    private let apiKeyManager: APIKeyManager
    private let repository: CombinedCharacterRepository
    private var syncTimer: Timer?

    // MARK: - Sync Interval

    /// How often to sync (in seconds) - default 5 minutes
    private let syncInterval: TimeInterval = 5 * 60

    // MARK: - Initialization

    init(apiKeyManager: APIKeyManager, repository: CombinedCharacterRepository) {
        self.apiKeyManager = apiKeyManager
        self.repository = repository
    }

    // MARK: - Sync Operations

    /// Perform initial sync on app startup
    func performStartupSync() async {
        guard canSync else {
            NSLog("[SyncManager] Skipping startup sync - not configured or disabled")
            return
        }

        NSLog("[SyncManager] Performing startup sync...")
        await sync()
    }

    /// Start periodic sync timer
    func startPeriodicSync() {
        stopPeriodicSync() // Stop any existing timer

        guard canSync else {
            NSLog("[SyncManager] Periodic sync not started - not configured or disabled")
            return
        }

        NSLog("[SyncManager] Starting periodic sync every \(syncInterval) seconds")

        syncTimer = Timer.scheduledTimer(withTimeInterval: syncInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.sync()
            }
        }
    }

    /// Stop periodic sync timer
    func stopPeriodicSync() {
        syncTimer?.invalidate()
        syncTimer = nil
    }

    /// Main sync function - uses CombinedCharacterRepository's bulk sync
    func sync() async {
        guard canSync else {
            NSLog("[SyncManager] Cannot sync - not configured")
            return
        }

        guard !isSyncing else {
            NSLog("[SyncManager] Sync already in progress, skipping")
            return
        }

        isSyncing = true
        syncError = nil

        do {
            // Use the combined repository's bulk sync
            try await repository.syncAllToSupabase()

            // Also pull any remote-only characters
            try await repository.pullAllFromSupabase()

            consecutiveFailures = 0
            lastSyncDate = Date()
            NSLog("[SyncManager] Sync completed successfully at \(lastSyncDate!)")

        } catch {
            consecutiveFailures += 1
            syncError = error.localizedDescription
            NSLog("[SyncManager] Sync failed (%d consecutive): %@", consecutiveFailures, error.localizedDescription)

            // Stop periodic sync on persistent errors
            if consecutiveFailures >= 3 {
                NSLog("[SyncManager] Too many consecutive failures, stopping periodic sync")
                stopPeriodicSync()
            }
        }

        isSyncing = false
    }

    /// Force a manual sync (resets failure counter)
    func forceSync() async {
        consecutiveFailures = 0
        await sync()
        // Restart periodic sync if it was stopped due to errors
        if syncError == nil {
            startPeriodicSync()
        }
    }

    // MARK: - Configuration Changes

    /// Called when Supabase configuration changes
    func onConfigurationChanged() {
        // Update the combined repository's sync configuration
        let newConfig = SupabaseSyncConfig(
            supabaseURL: apiKeyManager.supabaseURL,
            supabaseAnonKey: apiKeyManager.supabaseAnonKey,
            syncEnabled: apiKeyManager.supabaseSyncEnabled
        )
        Task {
            await repository.updateSyncConfiguration(newConfig)
        }

        // Reset failure counter on reconfiguration
        consecutiveFailures = 0
        syncError = nil

        if canSync {
            Task {
                await performStartupSync()
                startPeriodicSync()
            }
        } else {
            stopPeriodicSync()
        }
    }
}
