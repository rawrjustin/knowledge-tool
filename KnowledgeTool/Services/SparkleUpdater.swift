import Foundation
import SwiftUI

#if canImport(Sparkle)
import Sparkle
#endif

/// Manages automatic updates via Sparkle framework
/// For builds without Sparkle (command-line build), this provides stub implementations
@MainActor
@Observable
final class SparkleUpdater {
    static let shared = SparkleUpdater()

    /// Whether an update check is in progress
    private(set) var isCheckingForUpdates = false

    /// Whether the updater initialized successfully
    private(set) var isUpdaterAvailable = false

    /// Whether automatic update checks are enabled
    var automaticUpdateChecksEnabled: Bool {
        get {
            #if canImport(Sparkle)
            return updaterController?.updater.automaticallyChecksForUpdates ?? false
            #else
            return UserDefaults.standard.bool(forKey: "automaticUpdateChecks")
            #endif
        }
        set {
            #if canImport(Sparkle)
            updaterController?.updater.automaticallyChecksForUpdates = newValue
            #else
            UserDefaults.standard.set(newValue, forKey: "automaticUpdateChecks")
            #endif
        }
    }

    /// Last update check date
    var lastUpdateCheckDate: Date? {
        #if canImport(Sparkle)
        return updaterController?.updater.lastUpdateCheckDate
        #else
        return UserDefaults.standard.object(forKey: "lastUpdateCheckDate") as? Date
        #endif
    }

    #if canImport(Sparkle)
    private var updaterController: SPUStandardUpdaterController?
    #endif

    private init() {
        #if canImport(Sparkle)
        // Initialize Sparkle updater with startingUpdater: false to avoid
        // showing error dialogs on startup for unsigned/ad-hoc signed apps.
        // The updater will be started manually when the user triggers an update check.
        updaterController = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        isUpdaterAvailable = true
        #endif
    }

    /// Start the updater (call this after app is fully launched)
    func startUpdater() {
        #if canImport(Sparkle)
        guard let controller = updaterController else { return }
        // Only start if not already started
        if !controller.updater.sessionInProgress {
            do {
                try controller.updater.start()
            } catch {
                // Silently fail - updater won't work but app continues normally
                NSLog("[SparkleUpdater] Failed to start updater: %@", error.localizedDescription)
                isUpdaterAvailable = false
            }
        }
        #endif
    }

    /// Manually check for updates
    func checkForUpdates() {
        #if canImport(Sparkle)
        if let controller = updaterController {
            // Try to start the updater if not already running
            if !controller.updater.sessionInProgress {
                do {
                    try controller.updater.start()
                } catch {
                    NSLog("[SparkleUpdater] Failed to start updater: %@", error.localizedDescription)
                    // Fall back to opening releases page
                    openReleasesPage()
                    return
                }
            }
            controller.checkForUpdates(nil)
        } else {
            openReleasesPage()
        }
        #else
        openReleasesPage()
        #endif
    }

    /// Open the GitHub releases page as a fallback
    private func openReleasesPage() {
        if let url = URL(string: "https://github.com/geniesinc/knowledgetool/releases") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Check if updates can be checked (Sparkle is available and configured)
    var canCheckForUpdates: Bool {
        #if canImport(Sparkle)
        // Always return true so users can try - we'll fall back to releases page if needed
        return isUpdaterAvailable
        #else
        return true  // Can always open releases page
        #endif
    }
}

// MARK: - SwiftUI View for Update Check Button

/// A button that checks for updates using Sparkle
struct CheckForUpdatesButton: View {
    @State private var updater = SparkleUpdater.shared

    var body: some View {
        Button("Check for Updates...") {
            updater.checkForUpdates()
        }
        .disabled(!updater.canCheckForUpdates)
    }
}

/// Settings view section for update preferences
struct UpdateSettingsSection: View {
    @State private var updater = SparkleUpdater.shared

    var body: some View {
        Section("Updates") {
            Toggle("Automatically check for updates", isOn: $updater.automaticUpdateChecksEnabled)

            HStack {
                Text("Last checked:")
                Spacer()
                if let date = updater.lastUpdateCheckDate {
                    Text(date, style: .relative)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Never")
                        .foregroundStyle(.secondary)
                }
            }

            Button("Check Now") {
                updater.checkForUpdates()
            }
            .disabled(!updater.canCheckForUpdates)
        }
    }
}
