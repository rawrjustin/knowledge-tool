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

    /// Whether automatic update checks are enabled
    var automaticUpdateChecksEnabled: Bool {
        get {
            #if canImport(Sparkle)
            return updaterController?.updater.automaticallyChecksForUpdates ?? true
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
        // Initialize Sparkle updater
        // This automatically starts checking for updates based on user preferences
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        #endif
    }

    /// Manually check for updates
    func checkForUpdates() {
        #if canImport(Sparkle)
        updaterController?.checkForUpdates(nil)
        #else
        print("Sparkle not available - update check skipped")
        // For non-Sparkle builds, you could open a URL to releases page
        if let url = URL(string: "https://github.com/geniesinc/knowledgetool/releases") {
            NSWorkspace.shared.open(url)
        }
        #endif
    }

    /// Check if updates can be checked (Sparkle is available and configured)
    var canCheckForUpdates: Bool {
        #if canImport(Sparkle)
        return updaterController?.updater.canCheckForUpdates ?? false
        #else
        return false
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
