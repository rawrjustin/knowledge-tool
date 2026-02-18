import Foundation
import UserNotifications

@MainActor
final class NotificationService {
    static let shared = NotificationService()

    private init() {}

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error = error {
                NSLog("[KnowledgeTool] Notification authorization error: %@", error.localizedDescription)
            } else {
                NSLog("[KnowledgeTool] Notification authorization granted: %@", granted ? "true" : "false")
            }
        }
    }

    func sendCompletionNotification(for job: BackgroundJob) {
        let content = UNMutableNotificationContent()

        switch job.type {
        case .characterCreation:
            content.title = "Character Ready"
            content.body = "\(job.characterName) has been created successfully."
        case .scenarioGeneration:
            content.title = "Scenarios Generated"
            content.body = "Scenarios for \(job.characterName) are ready."
        case .videoProcessing:
            content.title = "Video Processed"
            content.body = "Video processing for \(job.characterName) is complete."
        }

        content.sound = .default

        let request = UNNotificationRequest(identifier: job.id.uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                NSLog("[KnowledgeTool] Failed to send notification: %@", error.localizedDescription)
            }
        }
    }

    func sendFailureNotification(for job: BackgroundJob, error: String) {
        let content = UNMutableNotificationContent()

        switch job.type {
        case .characterCreation:
            content.title = "Character Creation Failed"
            content.body = "\(job.characterName): \(error)"
        case .scenarioGeneration:
            content.title = "Scenario Generation Failed"
            content.body = "\(job.characterName): \(error)"
        case .videoProcessing:
            content.title = "Video Processing Failed"
            content.body = "\(job.characterName): \(error)"
        }

        content.sound = .default

        let request = UNNotificationRequest(identifier: job.id.uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                NSLog("[KnowledgeTool] Failed to send notification: %@", error.localizedDescription)
            }
        }
    }
}
