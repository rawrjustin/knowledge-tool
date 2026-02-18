import Foundation

enum JobType: String {
    case characterCreation
    case scenarioGeneration
    case videoProcessing
}

enum JobState: Equatable {
    case processing
    case completed
    case failed(String)
}

struct BackgroundJob: Identifiable {
    let id: UUID
    let type: JobType
    let characterName: String
    var state: JobState
    var progressMessage: String
}

@MainActor
@Observable
final class BackgroundJobManager {
    private(set) var jobs: [BackgroundJob] = []

    @discardableResult
    func startJob(type: JobType, characterName: String) -> UUID {
        let id = UUID()
        let job = BackgroundJob(
            id: id,
            type: type,
            characterName: characterName,
            state: .processing,
            progressMessage: "Starting..."
        )
        jobs.append(job)
        NSLog("[KnowledgeTool] Background job started: %@ for %@", type.rawValue, characterName)
        return id
    }

    func updateProgress(jobId: UUID, message: String) {
        guard let index = jobs.firstIndex(where: { $0.id == jobId }) else { return }
        jobs[index].progressMessage = message
    }

    func completeJob(jobId: UUID) {
        guard let index = jobs.firstIndex(where: { $0.id == jobId }) else { return }
        jobs[index].state = .completed
        jobs[index].progressMessage = "Complete"
        NSLog("[KnowledgeTool] Background job completed: %@", jobs[index].characterName)

        NotificationService.shared.sendCompletionNotification(for: jobs[index])

        // Auto-remove after delay
        let id = jobId
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            self.jobs.removeAll { $0.id == id }
        }
    }

    func failJob(jobId: UUID, error: String) {
        guard let index = jobs.firstIndex(where: { $0.id == jobId }) else { return }
        jobs[index].state = .failed(error)
        jobs[index].progressMessage = error
        NSLog("[KnowledgeTool] Background job failed: %@ - %@", jobs[index].characterName, error)

        NotificationService.shared.sendFailureNotification(for: jobs[index], error: error)

        // Auto-remove after delay
        let id = jobId
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(10))
            self.jobs.removeAll { $0.id == id }
        }
    }

    func isGenerating(characterName: String) -> Bool {
        jobs.contains { $0.characterName == characterName && $0.state == .processing }
    }

    func isGenerating(characterName: String, type: JobType) -> Bool {
        jobs.contains { $0.characterName == characterName && $0.type == type && $0.state == .processing }
    }

    func activeJob(for characterName: String) -> BackgroundJob? {
        jobs.first { $0.characterName == characterName && $0.state == .processing }
    }

    func activeJob(for characterName: String, type: JobType) -> BackgroundJob? {
        jobs.first { $0.characterName == characterName && $0.type == type && $0.state == .processing }
    }
}
