import Foundation

// MARK: - Scenario

/// A scenario with a current situation and live objective
struct Scenario: Identifiable, Codable, Hashable {
    let id: UUID
    let characterId: UUID
    let theme: String                 // Theme used for generation
    let title: String                 // Short descriptive title
    let currentSituation: String      // What's happening RIGHT NOW
    let liveObjective: String         // What the character is trying to accomplish
    let source: ScenarioSource        // generated or userCreated
    var isActive: Bool                // Whether this scenario is currently active
    let createdAt: Date

    init(
        id: UUID = UUID(),
        characterId: UUID,
        theme: String,
        title: String,
        currentSituation: String,
        liveObjective: String,
        source: ScenarioSource,
        isActive: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.characterId = characterId
        self.theme = theme
        self.title = title
        self.currentSituation = currentSituation
        self.liveObjective = liveObjective
        self.source = source
        self.isActive = isActive
        self.createdAt = createdAt
    }
}

// MARK: - Scenario Source

/// The origin of a scenario
enum ScenarioSource: String, Codable, CaseIterable {
    case generated    // AI-generated
    case userCreated  // Manually created by user

    var displayName: String {
        switch self {
        case .generated: return "AI Generated"
        case .userCreated: return "User Created"
        }
    }

    var icon: String {
        switch self {
        case .generated: return "sparkles"
        case .userCreated: return "person.fill"
        }
    }
}

// MARK: - Scenario Generation Config

/// Configuration for scenario generation
struct ScenarioGenerationConfig: Codable {
    var theme: String
    var numberOfScenarios: Int
    var includeDramaticStakes: Bool

    init(
        theme: String = "",
        numberOfScenarios: Int = 5,
        includeDramaticStakes: Bool = false
    ) {
        self.theme = theme
        self.numberOfScenarios = numberOfScenarios
        self.includeDramaticStakes = includeDramaticStakes
    }

    static var `default`: ScenarioGenerationConfig {
        ScenarioGenerationConfig()
    }
}
