import Foundation

// MARK: - Sport

enum Sport: String, Codable, CaseIterable, Identifiable, Hashable {
    case collegeBasketball = "cbb"
    case nba = "nba"
    case mlb = "mlb"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .collegeBasketball: return "College Basketball"
        case .nba: return "NBA"
        case .mlb: return "MLB"
        }
    }

    var shortName: String {
        switch self {
        case .collegeBasketball: return "CBB"
        case .nba: return "NBA"
        case .mlb: return "MLB"
        }
    }

    var icon: String {
        switch self {
        case .collegeBasketball: return "basketball.fill"
        case .nba: return "basketball.fill"
        case .mlb: return "baseball.fill"
        }
    }

    /// API path segment used by providers
    var apiPathSegment: String { rawValue }
}

// MARK: - Sports Conference

struct SportsConference: Identifiable, Codable, Hashable {
    let id: Int
    let name: String
    var teams: [SportsTeam]

    init(id: Int, name: String, teams: [SportsTeam] = []) {
        self.id = id
        self.name = name
        self.teams = teams
    }
}

// MARK: - Sports Team

struct SportsTeam: Identifiable, Codable, Hashable {
    let id: Int
    let key: String
    let school: String          // e.g. "Duke" (CBB) or city name (NBA/MLB)
    let name: String            // e.g. "Blue Devils"
    let conference: String?
    let logoURL: String?
    var wins: Int?
    var losses: Int?
    var conferenceWins: Int?
    var conferenceLosses: Int?
    var apRank: Int?
    var primaryColor: String?
    var secondaryColor: String?
    var stadium: SportsStadium?

    var fullName: String {
        "\(school) \(name)"
    }

    var record: String? {
        guard let w = wins, let l = losses else { return nil }
        var result = "\(w)-\(l)"
        if let cw = conferenceWins, let cl = conferenceLosses {
            result += " (\(cw)-\(cl) conf)"
        }
        return result
    }
}

// MARK: - Sports Player

struct SportsPlayer: Identifiable, Codable, Hashable {
    let id: Int
    let firstName: String
    let lastName: String
    let teamKey: String?
    let jersey: Int?
    let position: String?
    let playerClass: String?     // "Freshman", "Sophomore", etc. (CBB) or years experience
    let height: Int?             // inches
    let weight: Int?             // pounds
    let hometown: String?
    let injuryStatus: String?
    let injuryBodyPart: String?
    let injuryNotes: String?

    var fullName: String {
        "\(firstName) \(lastName)"
    }

    var heightDisplay: String? {
        guard let h = height else { return nil }
        let feet = h / 12
        let inches = h % 12
        return "\(feet)'\(inches)\""
    }
}

// MARK: - Sports Player Stats

struct SportsPlayerStats: Identifiable, Codable, Hashable {
    let id: String  // statId or constructed
    let playerId: Int
    let playerName: String
    let teamKey: String?
    let position: String?
    let games: Int
    let minutes: Double?
    let points: Double?
    let rebounds: Double?
    let assists: Double?
    let steals: Double?
    let blocks: Double?
    let turnovers: Double?
    let fieldGoalsMade: Double?
    let fieldGoalsAttempted: Double?
    let fieldGoalPercentage: Double?
    let threePointersMade: Double?
    let threePointersAttempted: Double?
    let threePointPercentage: Double?
    let freeThrowsMade: Double?
    let freeThrowsAttempted: Double?
    let freeThrowPercentage: Double?
    let offensiveRebounds: Double?
    let defensiveRebounds: Double?
    let personalFouls: Double?

    // MLB-specific
    let battingAverage: Double?
    let homeRuns: Double?
    let rbi: Double?
    let era: Double?
    let strikeouts: Double?
    let walks: Double?

    init(
        id: String,
        playerId: Int,
        playerName: String,
        teamKey: String? = nil,
        position: String? = nil,
        games: Int = 0,
        minutes: Double? = nil,
        points: Double? = nil,
        rebounds: Double? = nil,
        assists: Double? = nil,
        steals: Double? = nil,
        blocks: Double? = nil,
        turnovers: Double? = nil,
        fieldGoalsMade: Double? = nil,
        fieldGoalsAttempted: Double? = nil,
        fieldGoalPercentage: Double? = nil,
        threePointersMade: Double? = nil,
        threePointersAttempted: Double? = nil,
        threePointPercentage: Double? = nil,
        freeThrowsMade: Double? = nil,
        freeThrowsAttempted: Double? = nil,
        freeThrowPercentage: Double? = nil,
        offensiveRebounds: Double? = nil,
        defensiveRebounds: Double? = nil,
        personalFouls: Double? = nil,
        battingAverage: Double? = nil,
        homeRuns: Double? = nil,
        rbi: Double? = nil,
        era: Double? = nil,
        strikeouts: Double? = nil,
        walks: Double? = nil
    ) {
        self.id = id
        self.playerId = playerId
        self.playerName = playerName
        self.teamKey = teamKey
        self.position = position
        self.games = games
        self.minutes = minutes
        self.points = points
        self.rebounds = rebounds
        self.assists = assists
        self.steals = steals
        self.blocks = blocks
        self.turnovers = turnovers
        self.fieldGoalsMade = fieldGoalsMade
        self.fieldGoalsAttempted = fieldGoalsAttempted
        self.fieldGoalPercentage = fieldGoalPercentage
        self.threePointersMade = threePointersMade
        self.threePointersAttempted = threePointersAttempted
        self.threePointPercentage = threePointPercentage
        self.freeThrowsMade = freeThrowsMade
        self.freeThrowsAttempted = freeThrowsAttempted
        self.freeThrowPercentage = freeThrowPercentage
        self.offensiveRebounds = offensiveRebounds
        self.defensiveRebounds = defensiveRebounds
        self.personalFouls = personalFouls
        self.battingAverage = battingAverage
        self.homeRuns = homeRuns
        self.rbi = rbi
        self.era = era
        self.strikeouts = strikeouts
        self.walks = walks
    }
}

// MARK: - Sports Team Stats

struct SportsTeamStats: Identifiable, Codable, Hashable {
    let id: String
    let teamKey: String
    let teamName: String
    let games: Int
    let wins: Int
    let losses: Int
    let points: Double?
    let rebounds: Double?
    let assists: Double?
    let steals: Double?
    let blocks: Double?
    let turnovers: Double?
    let fieldGoalPercentage: Double?
    let threePointPercentage: Double?
    let freeThrowPercentage: Double?
    let pointsAllowed: Double?
}

// MARK: - Sports Game

struct SportsGame: Identifiable, Codable, Hashable {
    let id: Int
    let dateTime: Date?
    let homeTeamKey: String
    let homeTeamName: String
    let awayTeamKey: String
    let awayTeamName: String
    let homeScore: Int?
    let awayScore: Int?
    let status: String           // "Final", "InProgress", "Scheduled"
    let period: String?
    let channel: String?
    let stadium: String?
    let isTournament: Bool

    var isCompleted: Bool {
        status == "Final"
    }

    var scoreDisplay: String? {
        guard let hs = homeScore, let as_ = awayScore else { return nil }
        return "\(awayTeamName) \(as_) - \(homeTeamName) \(hs)"
    }
}

// MARK: - Sports Box Score

struct SportsBoxScore: Identifiable, Codable, Hashable {
    let id: Int  // gameId
    let game: SportsGame
    let playerStats: [SportsPlayerStats]
    let homeTeamStats: SportsTeamStats?
    let awayTeamStats: SportsTeamStats?
}

// MARK: - Sports Season

struct SportsSeason: Codable, Hashable {
    let season: Int
    let startDate: Date?
    let endDate: Date?
    let description: String?
    let apiSeason: String?       // The season key used in API calls
}

// MARK: - Sports Stadium

struct SportsStadium: Identifiable, Codable, Hashable {
    let id: Int
    let name: String
    let city: String?
    let state: String?
    let capacity: Int?
}

// MARK: - Sports Data Attachment

/// Tracks which sports data is attached to a character for refresh purposes
struct SportsDataAttachment: Identifiable, Codable, Hashable {
    let id: UUID
    let characterId: UUID
    let sport: Sport
    let teamKey: String
    let teamName: String
    var playerIds: [Int]
    var lastRefreshed: Date?
    var refreshIntervalMinutes: Int
    var isAutoRefreshEnabled: Bool
    var knowledgeSourceId: UUID?

    init(
        id: UUID = UUID(),
        characterId: UUID,
        sport: Sport,
        teamKey: String,
        teamName: String,
        playerIds: [Int] = [],
        lastRefreshed: Date? = nil,
        refreshIntervalMinutes: Int = 60,
        isAutoRefreshEnabled: Bool = false,
        knowledgeSourceId: UUID? = nil
    ) {
        self.id = id
        self.characterId = characterId
        self.sport = sport
        self.teamKey = teamKey
        self.teamName = teamName
        self.playerIds = playerIds
        self.lastRefreshed = lastRefreshed
        self.refreshIntervalMinutes = refreshIntervalMinutes
        self.isAutoRefreshEnabled = isAutoRefreshEnabled
        self.knowledgeSourceId = knowledgeSourceId
    }
}
