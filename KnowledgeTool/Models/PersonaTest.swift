import Foundation

// MARK: - Persona Test Config

struct PersonaTestConfig {
    var testGoal: String = ""
    var maxTurns: Int = 5
}

// MARK: - Conversation Turn

struct ConversationTurn: Identifiable {
    let id = UUID()
    let turnNumber: Int
    let userMessage: String
    let personaResponse: String
}

// MARK: - Persona Test Evaluation

struct PersonaTestEvaluation: Codable {
    let overallScore: Int
    let goalAchievement: Int
    let characterConsistency: Int
    let conversationQuality: Int
    let summary: String
    let strengths: [String]
    let weaknesses: [String]
    let recommendations: [String]

    private enum CodingKeys: String, CodingKey {
        case overallScore = "overall_score"
        case goalAchievement = "goal_achievement"
        case characterConsistency = "character_consistency"
        case conversationQuality = "conversation_quality"
        case summary, strengths, weaknesses, recommendations
    }
}

// MARK: - Persona Test Status

enum PersonaTestStatus: Equatable {
    case idle
    case running(turn: Int, maxTurns: Int)
    case evaluating
    case complete
    case error(String)

    static func == (lhs: PersonaTestStatus, rhs: PersonaTestStatus) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.evaluating, .evaluating), (.complete, .complete):
            return true
        case let (.running(lt, lm), .running(rt, rm)):
            return lt == rt && lm == rm
        case let (.error(l), .error(r)):
            return l == r
        default:
            return false
        }
    }
}
