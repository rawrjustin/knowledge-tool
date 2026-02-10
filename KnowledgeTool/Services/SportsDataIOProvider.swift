import Foundation

// MARK: - SportsData.io Provider

/// Concrete SportsDataProvider implementation for the SportsData.io API.
/// Maps SportsData.io's JSON responses into unified sport models.
actor SportsDataIOProvider: SportsDataProvider {
    let sport: Sport
    private let apiKey: String
    private let session: URLSession
    private let decoder: JSONDecoder

    // Base URLs
    private var scoresBaseURL: String {
        "https://api.sportsdata.io/v3/\(sport.apiPathSegment)/scores/json"
    }
    private var statsBaseURL: String {
        "https://api.sportsdata.io/v3/\(sport.apiPathSegment)/stats/json"
    }

    init(sport: Sport, apiKey: String) {
        self.sport = sport
        self.apiKey = apiKey
        self.session = URLSession.shared
        self.decoder = JSONDecoder()
    }

    // MARK: - Protocol Methods

    func fetchTeams() async throws -> [SportsTeam] {
        let data = try await request(base: scoresBaseURL, path: "/teams")
        let raw = try decode([SDIOTeam].self, from: data)
        return raw.map { $0.toSportsTeam() }
    }

    func fetchConferences() async throws -> [SportsConference] {
        switch sport {
        case .collegeBasketball:
            // CBB has a dedicated LeagueHierarchy endpoint with nested conferences/teams
            let data = try await request(base: scoresBaseURL, path: "/LeagueHierarchy")
            let raw = try decode([SDIOConference].self, from: data)
            return raw.map { $0.toSportsConference() }

        case .nba, .mlb:
            // NBA/MLB don't have LeagueHierarchy — fetch flat teams list and group
            let data = try await request(base: scoresBaseURL, path: "/teams")
            let raw = try decode([SDIOTeam].self, from: data)
            return Self.groupTeamsIntoConferences(raw, sport: sport)
        }
    }

    func fetchPlayers(teamKey: String) async throws -> [SportsPlayer] {
        let data = try await request(base: scoresBaseURL, path: "/PlayersBasic/\(teamKey)")
        let raw = try decode([SDIOPlayer].self, from: data)
        return raw.map { $0.toSportsPlayer() }
    }

    func fetchPlayerSeasonStats(season: String, teamKey: String) async throws -> [SportsPlayerStats] {
        let data = try await request(base: statsBaseURL, path: "/PlayerSeasonStatsByTeam/\(season)/\(teamKey)")
        let raw = try decode([SDIOPlayerSeasonStats].self, from: data)
        return raw.map { $0.toSportsPlayerStats() }
    }

    func fetchTeamSeasonStats(season: String) async throws -> [SportsTeamStats] {
        let data = try await request(base: statsBaseURL, path: "/TeamSeasonStats/\(season)")
        let raw = try decode([SDIOTeamSeasonStats].self, from: data)
        return raw.map { $0.toSportsTeamStats() }
    }

    func fetchGamesByDate(date: Date) async throws -> [SportsGame] {
        let dateStr = Self.dateFormatter.string(from: date)
        let data = try await request(base: scoresBaseURL, path: "/GamesByDate/\(dateStr)")
        let raw = try decode([SDIOGame].self, from: data)
        return raw.map { $0.toSportsGame() }
    }

    func fetchTeamSchedule(season: String, teamKey: String) async throws -> [SportsGame] {
        let data = try await request(base: scoresBaseURL, path: "/TeamSchedule/\(season)/\(teamKey)")
        let raw = try decode([SDIOGame].self, from: data)
        return raw.map { $0.toSportsGame() }
    }

    func fetchBoxScore(gameId: Int) async throws -> SportsBoxScore {
        let data = try await request(base: statsBaseURL, path: "/BoxScore/\(gameId)")
        let raw = try decode(SDIOBoxScore.self, from: data)
        return raw.toSportsBoxScore()
    }

    func fetchCurrentSeason() async throws -> SportsSeason {
        let data = try await request(base: scoresBaseURL, path: "/CurrentSeason")
        let raw = try decode(SDIOSeason.self, from: data)
        return raw.toSportsSeason()
    }

    func fetchStandings() async throws -> [SportsConference] {
        switch sport {
        case .collegeBasketball:
            // CBB standings are embedded in LeagueHierarchy
            return try await fetchConferences()

        case .nba, .mlb:
            // NBA/MLB have a dedicated Standings endpoint
            let season = try await fetchCurrentSeason()
            let data = try await request(base: scoresBaseURL, path: "/Standings/\(season.apiSeason)")
            let raw = try decode([SDIOStanding].self, from: data)
            return Self.groupStandingsIntoConferences(raw, sport: sport)
        }
    }

    // MARK: - Conference Grouping Helpers

    /// Groups a flat list of teams into synthetic conferences by their Conference (NBA) or League (MLB) field.
    private static func groupTeamsIntoConferences(_ teams: [SDIOTeam], sport: Sport) -> [SportsConference] {
        let groupingKey: (SDIOTeam) -> String = { team in
            switch sport {
            case .mlb:
                return team.League ?? team.Conference ?? "Unknown"
            default:
                return team.Conference ?? "Unknown"
            }
        }

        let grouped = Dictionary(grouping: teams, by: groupingKey)
        return grouped
            .sorted { $0.key < $1.key }
            .enumerated()
            .map { index, pair in
                SportsConference(
                    id: index + 1,
                    name: pair.key,
                    teams: pair.value.map { $0.toSportsTeam() }
                )
            }
    }

    /// Groups standings into conferences for NBA/MLB.
    private static func groupStandingsIntoConferences(_ standings: [SDIOStanding], sport: Sport) -> [SportsConference] {
        let groupingKey: (SDIOStanding) -> String = { standing in
            switch sport {
            case .mlb:
                return standing.League ?? standing.Conference ?? "Unknown"
            default:
                return standing.Conference ?? "Unknown"
            }
        }

        let grouped = Dictionary(grouping: standings, by: groupingKey)
        return grouped
            .sorted { $0.key < $1.key }
            .enumerated()
            .map { index, pair in
                SportsConference(
                    id: index + 1,
                    name: pair.key,
                    teams: pair.value.map { $0.toSportsTeam() }
                )
            }
    }

    // MARK: - Networking

    private func request(base: String, path: String) async throws -> Data {
        let urlString = "\(base)\(path)?key=\(apiKey)"
        guard let url = URL(string: urlString) else {
            throw SportsDataError.invalidURL(urlString)
        }

        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SportsDataError.networkError(URLError(.badServerResponse))
        }

        switch httpResponse.statusCode {
        case 200:
            return data
        case 401:
            throw SportsDataError.invalidAPIKey
        case 429:
            throw SportsDataError.rateLimited
        default:
            let body = String(data: data, encoding: .utf8) ?? "Unknown"
            throw SportsDataError.networkError(
                NSError(domain: "SportsDataIO", code: httpResponse.statusCode,
                        userInfo: [NSLocalizedDescriptionKey: "HTTP \(httpResponse.statusCode): \(body)"])
            )
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw SportsDataError.decodingError(error)
        }
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MMM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    nonisolated(unsafe) private static let isoDateFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}

// MARK: - SportsData.io Raw Response Types

// These structs match SportsData.io's exact JSON response shapes.
// Each has a mapping function to convert to the unified model.

private struct SDIOConference: Decodable {
    let ConferenceID: Int?
    let Name: String?
    let Teams: [SDIOTeam]?

    func toSportsConference() -> SportsConference {
        SportsConference(
            id: ConferenceID ?? 0,
            name: Name ?? "Unknown",
            teams: (Teams ?? []).map { $0.toSportsTeam() }
        )
    }
}

private struct SDIOTeam: Decodable {
    let TeamID: Int?
    let Key: String?
    let School: String?
    let Name: String?
    let Conference: String?
    let TeamLogoUrl: String?
    let Wins: Int?
    let Losses: Int?
    let ConferenceWins: Int?
    let ConferenceLosses: Int?
    let ApRank: Int?
    let PrimaryColor: String?
    let SecondaryColor: String?
    let Stadium: SDIOStadium?
    // NBA/MLB fields
    let City: String?
    let League: String?
    let Division: String?
    let WikipediaLogoUrl: String?

    func toSportsTeam() -> SportsTeam {
        SportsTeam(
            id: TeamID ?? 0,
            key: Key ?? "",
            school: School ?? City ?? "Unknown",
            name: Name ?? "",
            conference: Conference ?? League,
            logoURL: WikipediaLogoUrl ?? TeamLogoUrl,
            wins: Wins,
            losses: Losses,
            conferenceWins: ConferenceWins,
            conferenceLosses: ConferenceLosses,
            apRank: ApRank,
            primaryColor: PrimaryColor,
            secondaryColor: SecondaryColor,
            stadium: Stadium?.toSportsStadium()
        )
    }
}

private struct SDIOStadium: Decodable {
    let StadiumID: Int?
    let Name: String?
    let City: String?
    let State: String?
    let Capacity: Int?

    func toSportsStadium() -> SportsStadium {
        SportsStadium(
            id: StadiumID ?? 0,
            name: Name ?? "Unknown",
            city: City,
            state: State,
            capacity: Capacity
        )
    }
}

private struct SDIOPlayer: Decodable {
    let PlayerID: Int?
    let FirstName: String?
    let LastName: String?
    let Team: String?
    let Jersey: Int?
    let Position: String?
    let Class: String?
    let Height: Int?
    let Weight: Int?
    let BirthCity: String?
    let BirthState: String?
    let InjuryStatus: String?
    let InjuryBodyPart: String?
    let InjuryNotes: String?
    // NBA uses Experience instead of Class
    let Experience: Int?

    func toSportsPlayer() -> SportsPlayer {
        let hometown: String? = {
            if let city = BirthCity, let state = BirthState {
                return "\(city), \(state)"
            }
            return BirthCity ?? BirthState
        }()

        let playerClass = Class ?? (Experience != nil ? "Year \(Experience!)" : nil)

        return SportsPlayer(
            id: PlayerID ?? 0,
            firstName: FirstName ?? "",
            lastName: LastName ?? "",
            teamKey: Team,
            jersey: Jersey,
            position: Position,
            playerClass: playerClass,
            height: Height,
            weight: Weight,
            hometown: hometown,
            injuryStatus: InjuryStatus,
            injuryBodyPart: InjuryBodyPart,
            injuryNotes: InjuryNotes
        )
    }
}

private struct SDIOPlayerSeasonStats: Decodable {
    let StatID: Int?
    let PlayerID: Int?
    let Name: String?
    let Team: String?
    let Position: String?
    let Games: Int?
    let Minutes: Double?
    let Points: Double?
    let Rebounds: Double?
    let Assists: Double?
    let Steals: Double?
    let BlockedShots: Double?
    let Turnovers: Double?
    let FieldGoalsMade: Double?
    let FieldGoalsAttempted: Double?
    let FieldGoalsPercentage: Double?
    let ThreePointersMade: Double?
    let ThreePointersAttempted: Double?
    let ThreePointersPercentage: Double?
    let FreeThrowsMade: Double?
    let FreeThrowsAttempted: Double?
    let FreeThrowsPercentage: Double?
    let OffensiveRebounds: Double?
    let DefensiveRebounds: Double?
    let PersonalFouls: Double?
    // MLB
    let BattingAverage: Double?
    let HomeRuns: Double?
    let RunsBattedIn: Double?
    let EarnedRunAverage: Double?
    let Strikeouts: Double?
    let Walks: Double?

    func toSportsPlayerStats() -> SportsPlayerStats {
        SportsPlayerStats(
            id: "stat-\(StatID ?? PlayerID ?? 0)",
            playerId: PlayerID ?? 0,
            playerName: Name ?? "Unknown",
            teamKey: Team,
            position: Position,
            games: Games ?? 0,
            minutes: Minutes,
            points: Points,
            rebounds: Rebounds,
            assists: Assists,
            steals: Steals,
            blocks: BlockedShots,
            turnovers: Turnovers,
            fieldGoalsMade: FieldGoalsMade,
            fieldGoalsAttempted: FieldGoalsAttempted,
            fieldGoalPercentage: FieldGoalsPercentage,
            threePointersMade: ThreePointersMade,
            threePointersAttempted: ThreePointersAttempted,
            threePointPercentage: ThreePointersPercentage,
            freeThrowsMade: FreeThrowsMade,
            freeThrowsAttempted: FreeThrowsAttempted,
            freeThrowPercentage: FreeThrowsPercentage,
            offensiveRebounds: OffensiveRebounds,
            defensiveRebounds: DefensiveRebounds,
            personalFouls: PersonalFouls,
            battingAverage: BattingAverage,
            homeRuns: HomeRuns,
            rbi: RunsBattedIn,
            era: EarnedRunAverage,
            strikeouts: Strikeouts,
            walks: Walks
        )
    }
}

private struct SDIOTeamSeasonStats: Decodable {
    let StatID: Int?
    let TeamID: Int?
    let Team: String?
    let Name: String?
    let Games: Int?
    let Wins: Int?
    let Losses: Int?
    let Points: Double?
    let Rebounds: Double?
    let Assists: Double?
    let Steals: Double?
    let BlockedShots: Double?
    let Turnovers: Double?
    let FieldGoalsPercentage: Double?
    let ThreePointersPercentage: Double?
    let FreeThrowsPercentage: Double?
    let OpponentPoints: Double?

    func toSportsTeamStats() -> SportsTeamStats {
        SportsTeamStats(
            id: "team-stat-\(StatID ?? TeamID ?? 0)",
            teamKey: Team ?? "",
            teamName: Name ?? Team ?? "Unknown",
            games: Games ?? 0,
            wins: Wins ?? 0,
            losses: Losses ?? 0,
            points: Points,
            rebounds: Rebounds,
            assists: Assists,
            steals: Steals,
            blocks: BlockedShots,
            turnovers: Turnovers,
            fieldGoalPercentage: FieldGoalsPercentage,
            threePointPercentage: ThreePointersPercentage,
            freeThrowPercentage: FreeThrowsPercentage,
            pointsAllowed: OpponentPoints
        )
    }
}

private struct SDIOGame: Decodable {
    let GameID: Int?
    let DateTime: String?
    let HomeTeam: String?
    let HomeTeamName: String?
    let AwayTeam: String?
    let AwayTeamName: String?
    let HomeTeamScore: Int?
    let AwayTeamScore: Int?
    let Status: String?
    let Period: String?
    let Channel: String?
    let Stadium: SDIOGameStadium?
    let IsTournament: Bool?
    // Some responses embed stadium name directly
    let StadiumName: String?

    struct SDIOGameStadium: Decodable {
        let Name: String?
    }

    func toSportsGame() -> SportsGame {
        let dateTime: Date? = {
            guard let dtString = DateTime else { return nil }
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: dtString) { return date }
            // Try simpler format
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: dtString) { return date }
            // Try basic date format
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
            df.locale = Locale(identifier: "en_US_POSIX")
            return df.date(from: dtString)
        }()

        return SportsGame(
            id: GameID ?? 0,
            dateTime: dateTime,
            homeTeamKey: HomeTeam ?? "",
            homeTeamName: HomeTeamName ?? HomeTeam ?? "Home",
            awayTeamKey: AwayTeam ?? "",
            awayTeamName: AwayTeamName ?? AwayTeam ?? "Away",
            homeScore: HomeTeamScore,
            awayScore: AwayTeamScore,
            status: Status ?? "Unknown",
            period: Period,
            channel: Channel,
            stadium: Stadium?.Name ?? StadiumName,
            isTournament: IsTournament ?? false
        )
    }
}

private struct SDIOBoxScore: Decodable {
    let Game: SDIOGame?
    let PlayerGameStats: [SDIOPlayerSeasonStats]?
    let TeamGameStats: [SDIOTeamSeasonStats]?

    func toSportsBoxScore() -> SportsBoxScore {
        let game = Game?.toSportsGame() ?? SportsGame(
            id: 0, dateTime: nil, homeTeamKey: "", homeTeamName: "",
            awayTeamKey: "", awayTeamName: "", homeScore: nil, awayScore: nil,
            status: "Unknown", period: nil, channel: nil, stadium: nil, isTournament: false
        )
        let playerStats = (PlayerGameStats ?? []).map { $0.toSportsPlayerStats() }
        let teamStats = (TeamGameStats ?? []).map { $0.toSportsTeamStats() }

        return SportsBoxScore(
            id: game.id,
            game: game,
            playerStats: playerStats,
            homeTeamStats: teamStats.first,
            awayTeamStats: teamStats.count > 1 ? teamStats[1] : nil
        )
    }
}

private struct SDIOSeason: Decodable {
    let Season: Int?
    let StartYear: Int?
    let EndYear: Int?
    let Description: String?
    let RegularSeasonStartDate: String?
    let PostSeasonStartDate: String?
    let ApiSeason: String?

    func toSportsSeason() -> SportsSeason {
        let startDate: Date? = {
            guard let s = RegularSeasonStartDate else { return nil }
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
            df.locale = Locale(identifier: "en_US_POSIX")
            return df.date(from: s)
        }()

        return SportsSeason(
            season: Season ?? StartYear ?? 0,
            startDate: startDate,
            endDate: nil,
            description: Description,
            apiSeason: ApiSeason ?? "\(Season ?? 0)"
        )
    }
}

/// Standings response for NBA/MLB (returned by /Standings/{season})
private struct SDIOStanding: Decodable {
    let TeamID: Int?
    let Key: String?
    let City: String?
    let Name: String?
    let Conference: String?
    let Division: String?
    let League: String?
    let Wins: Int?
    let Losses: Int?
    let ConferenceWins: Int?
    let ConferenceLosses: Int?
    let DivisionWins: Int?
    let DivisionLosses: Int?
    let Percentage: Double?
    let GamesBack: Double?
    let ConferenceRank: Int?
    let DivisionRank: Int?

    func toSportsTeam() -> SportsTeam {
        SportsTeam(
            id: TeamID ?? 0,
            key: Key ?? "",
            school: City ?? "Unknown",
            name: Name ?? "",
            conference: Conference ?? League,
            logoURL: nil,
            wins: Wins,
            losses: Losses,
            conferenceWins: ConferenceWins,
            conferenceLosses: ConferenceLosses,
            apRank: nil,
            primaryColor: nil,
            secondaryColor: nil,
            stadium: nil
        )
    }
}
