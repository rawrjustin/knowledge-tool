import Foundation

// MARK: - Sports Data Provider Protocol

/// Provider-agnostic interface for fetching sports data.
/// Implement this protocol for each data backend (SportsData.io, SportsRadar, etc.)
protocol SportsDataProvider: Actor {
    var sport: Sport { get }

    func fetchTeams() async throws -> [SportsTeam]
    func fetchConferences() async throws -> [SportsConference]
    func fetchPlayers(teamKey: String) async throws -> [SportsPlayer]
    func fetchPlayerSeasonStats(season: String, teamKey: String) async throws -> [SportsPlayerStats]
    func fetchTeamSeasonStats(season: String) async throws -> [SportsTeamStats]
    func fetchGamesByDate(date: Date) async throws -> [SportsGame]
    func fetchTeamSchedule(season: String, teamKey: String) async throws -> [SportsGame]
    func fetchBoxScore(gameId: Int) async throws -> SportsBoxScore
    func fetchCurrentSeason() async throws -> SportsSeason
    func fetchStandings() async throws -> [SportsConference]
}

// MARK: - Sports Data Backend

enum SportsDataBackend: String, Codable, CaseIterable {
    case sportsDataIO = "sportsdata_io"
    // case sportsRadar = "sportsradar"  // Future

    var displayName: String {
        switch self {
        case .sportsDataIO: return "SportsData.io"
        }
    }
}

// MARK: - Sports Data Provider Factory

struct SportsDataProviderFactory {
    static func makeProvider(
        backend: SportsDataBackend = .sportsDataIO,
        sport: Sport,
        apiKey: String
    ) -> any SportsDataProvider {
        switch backend {
        case .sportsDataIO:
            return SportsDataIOProvider(sport: sport, apiKey: apiKey)
        }
    }
}

// MARK: - Sports Data Error

enum SportsDataError: LocalizedError {
    case invalidAPIKey
    case networkError(Error)
    case decodingError(Error)
    case sportNotAvailable(Sport)
    case rateLimited
    case noData
    case invalidURL(String)

    var errorDescription: String? {
        switch self {
        case .invalidAPIKey:
            return "Invalid or missing API key. Check your SportsData.io key in Settings."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .decodingError(let error):
            return "Failed to parse response: \(error.localizedDescription)"
        case .sportNotAvailable(let sport):
            return "\(sport.displayName) is not available with your current API key."
        case .rateLimited:
            return "API rate limit reached. Please wait before making more requests."
        case .noData:
            return "No data available."
        case .invalidURL(let url):
            return "Invalid URL: \(url)"
        }
    }
}
