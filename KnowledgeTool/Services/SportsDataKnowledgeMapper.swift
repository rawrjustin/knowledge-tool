import Foundation

// MARK: - Sports Data Knowledge Mapper

/// Converts sports data into KnowledgeEntry and KnowledgeSource objects
/// optimized for vector database (Pinecone) storage and LLM retrieval.
///
/// Design principles:
/// - All abbreviations expanded to natural language for embedding quality
/// - Null/missing values omitted entirely (no placeholders)
/// - Content written as readable prose for LLM comprehension
/// - Keywords include both short and expanded forms for retrieval breadth
struct SportsDataKnowledgeMapper {

    // MARK: - Position Expansion

    /// Expands common sports position abbreviations to full names
    private static func expandPosition(_ abbrev: String, sport: Sport) -> String {
        switch sport {
        case .collegeBasketball, .nba:
            switch abbrev.uppercased() {
            case "PG": return "point guard"
            case "SG": return "shooting guard"
            case "SF": return "small forward"
            case "PF": return "power forward"
            case "C": return "center"
            case "G": return "guard"
            case "F": return "forward"
            case "G-F", "GF": return "guard-forward"
            case "F-G", "FG": return "forward-guard"
            case "F-C", "FC": return "forward-center"
            case "C-F", "CF": return "center-forward"
            default: return abbrev
            }
        case .mlb:
            switch abbrev.uppercased() {
            case "P": return "pitcher"
            case "C": return "catcher"
            case "1B": return "first baseman"
            case "2B": return "second baseman"
            case "3B": return "third baseman"
            case "SS": return "shortstop"
            case "LF": return "left fielder"
            case "CF": return "center fielder"
            case "RF": return "right fielder"
            case "DH": return "designated hitter"
            case "OF": return "outfielder"
            case "IF": return "infielder"
            case "UT", "UTIL": return "utility player"
            case "SP": return "starting pitcher"
            case "RP": return "relief pitcher"
            case "CL": return "closer"
            default: return abbrev
            }
        }
    }

    // MARK: - Stat Formatting Helpers

    private static func fmt(_ value: Double, decimals: Int = 1) -> String {
        String(format: "%.\(decimals)f", value)
    }

    private static func pct(_ value: Double) -> String {
        String(format: "%.1f%%", value * 100)
    }

    // MARK: - Player Stats to Knowledge

    static func mapPlayerStats(
        _ stats: SportsPlayerStats,
        player: SportsPlayer? = nil,
        sport: Sport
    ) -> [KnowledgeEntry] {
        var entries: [KnowledgeEntry] = []
        let name = player?.fullName ?? stats.playerName
        guard stats.games > 0 else { return entries }

        // Build natural-language overview
        var parts: [String] = []
        parts.append("\(name) is a \(sport.displayName) player")

        if let pos = stats.position ?? player?.position {
            parts[0] += " who plays \(expandPosition(pos, sport: sport))"
        }

        if let cls = player?.playerClass {
            parts.append("Classification: \(cls)")
        }

        if let height = player?.heightDisplay {
            var bio = "Height: \(height)"
            if let weight = player?.weight {
                bio += ", Weight: \(weight) pounds"
            }
            parts.append(bio)
        }

        parts.append("Games played this season: \(stats.games)")

        switch sport {
        case .collegeBasketball, .nba:
            var scoringParts: [String] = []
            if let pts = stats.points {
                scoringParts.append("\(fmt(pts)) points per game")
            }
            if let reb = stats.rebounds {
                scoringParts.append("\(fmt(reb)) rebounds per game")
            }
            if let ast = stats.assists {
                scoringParts.append("\(fmt(ast)) assists per game")
            }
            if let stl = stats.steals {
                scoringParts.append("\(fmt(stl)) steals per game")
            }
            if let blk = stats.blocks {
                scoringParts.append("\(fmt(blk)) blocks per game")
            }
            if let tov = stats.turnovers {
                scoringParts.append("\(fmt(tov)) turnovers per game")
            }
            if !scoringParts.isEmpty {
                parts.append("Season averages: " + scoringParts.joined(separator: ", "))
            }

            if let min = stats.minutes {
                parts.append("Minutes per game: \(fmt(min))")
            }

        case .mlb:
            var battingParts: [String] = []
            if let avg = stats.battingAverage {
                battingParts.append("batting average of \(fmt(avg, decimals: 3))")
            }
            if let hr = stats.homeRuns, hr > 0 {
                battingParts.append("\(Int(hr)) home runs")
            }
            if let rbi = stats.rbi, rbi > 0 {
                battingParts.append("\(Int(rbi)) runs batted in")
            }
            if !battingParts.isEmpty {
                parts.append("Batting stats: " + battingParts.joined(separator: ", "))
            }
        }

        let overview = parts.joined(separator: ". ") + "."

        var keywords = [name, sport.displayName, "player statistics", "season stats"]
        if let pos = stats.position ?? player?.position {
            keywords.append(expandPosition(pos, sport: sport))
        }

        entries.append(KnowledgeEntry(
            id: "sports-player-overview-\(stats.playerId)",
            section: "\(sport.displayName) Player Profile: \(name)",
            content: overview,
            keywords: keywords
        ))

        // Detailed shooting/efficiency entry for basketball
        if sport == .collegeBasketball || sport == .nba {
            var shootingParts: [String] = []
            if let fgp = stats.fieldGoalPercentage {
                var line = "Field goal percentage: \(pct(fgp))"
                if let fgm = stats.fieldGoalsMade, let fga = stats.fieldGoalsAttempted {
                    line += " (\(fmt(fgm, decimals: 0)) made on \(fmt(fga, decimals: 0)) attempts per game)"
                }
                shootingParts.append(line)
            }
            if let tpp = stats.threePointPercentage {
                var line = "Three-point percentage: \(pct(tpp))"
                if let tpm = stats.threePointersMade, let tpa = stats.threePointersAttempted {
                    line += " (\(fmt(tpm, decimals: 1)) made on \(fmt(tpa, decimals: 1)) attempts per game)"
                }
                shootingParts.append(line)
            }
            if let ftp = stats.freeThrowPercentage {
                var line = "Free throw percentage: \(pct(ftp))"
                if let ftm = stats.freeThrowsMade, let fta = stats.freeThrowsAttempted {
                    line += " (\(fmt(ftm, decimals: 1)) made on \(fmt(fta, decimals: 1)) attempts per game)"
                }
                shootingParts.append(line)
            }

            if !shootingParts.isEmpty {
                let shooting = "\(name) shooting efficiency breakdown. " + shootingParts.joined(separator: ". ") + "."

                entries.append(KnowledgeEntry(
                    id: "sports-player-shooting-\(stats.playerId)",
                    section: "Shooting Efficiency: \(name)",
                    content: shooting,
                    keywords: [name, "shooting efficiency", "field goal percentage", "three-point shooting", "free throw percentage"]
                ))
            }
        }

        // MLB pitching stats
        if sport == .mlb, let era = stats.era {
            var pitchingParts: [String] = []
            pitchingParts.append("\(name) pitching statistics")
            pitchingParts.append("Earned run average: \(fmt(era, decimals: 2))")
            if let k = stats.strikeouts {
                pitchingParts.append("Strikeouts: \(Int(k))")
            }
            if let bb = stats.walks {
                pitchingParts.append("Walks allowed: \(Int(bb))")
            }

            let pitching = pitchingParts.joined(separator: ". ") + "."

            entries.append(KnowledgeEntry(
                id: "sports-player-pitching-\(stats.playerId)",
                section: "Pitching Statistics: \(name)",
                content: pitching,
                keywords: [name, "pitching statistics", "earned run average", "strikeouts"]
            ))
        }

        return entries
    }

    // MARK: - Team Stats to Knowledge

    static func mapTeamStats(_ stats: SportsTeamStats, sport: Sport) -> [KnowledgeEntry] {
        var parts: [String] = []

        parts.append("\(stats.teamName) \(sport.displayName) season overview")
        parts.append("Record: \(stats.wins) wins and \(stats.losses) losses in \(stats.games) games")

        switch sport {
        case .collegeBasketball, .nba:
            if let ppg = stats.points {
                parts.append("Scoring: \(fmt(ppg)) points per game")
            }
            if let opp = stats.pointsAllowed {
                parts.append("Points allowed per game: \(fmt(opp))")
            }
            if let ppg = stats.points, let opp = stats.pointsAllowed {
                let margin = ppg - opp
                let sign = margin >= 0 ? "+" : ""
                parts.append("Scoring margin: \(sign)\(fmt(margin)) points per game")
            }
            if let fgp = stats.fieldGoalPercentage {
                parts.append("Team field goal percentage: \(pct(fgp))")
            }
            if let tpp = stats.threePointPercentage {
                parts.append("Team three-point percentage: \(pct(tpp))")
            }
            if let ftp = stats.freeThrowPercentage {
                parts.append("Team free throw percentage: \(pct(ftp))")
            }
            if let reb = stats.rebounds {
                parts.append("Rebounds per game: \(fmt(reb))")
            }
            if let ast = stats.assists {
                parts.append("Assists per game: \(fmt(ast))")
            }
            if let stl = stats.steals {
                parts.append("Steals per game: \(fmt(stl))")
            }
            if let blk = stats.blocks {
                parts.append("Blocks per game: \(fmt(blk))")
            }
            if let tov = stats.turnovers {
                parts.append("Turnovers per game: \(fmt(tov))")
            }
        case .mlb:
            if let rpg = stats.points {
                parts.append("Runs scored per game: \(fmt(rpg))")
            }
        }

        let overview = parts.joined(separator: ". ") + "."

        return [KnowledgeEntry(
            id: "sports-team-overview-\(stats.teamKey)",
            section: "\(sport.displayName) Team Stats: \(stats.teamName)",
            content: overview,
            keywords: [stats.teamName, sport.displayName, "team statistics", "season record", "win-loss record"]
        )]
    }

    // MARK: - Schedule to Knowledge

    static func mapSchedule(_ games: [SportsGame], teamKey: String, teamName: String) -> [KnowledgeEntry] {
        guard !games.isEmpty else { return [] }

        let completedGames = games.filter { $0.isCompleted }
        let upcomingGames = games.filter { !$0.isCompleted }

        var entries: [KnowledgeEntry] = []
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMMM d, yyyy"

        // Recent results — each game described in full prose
        let recentGames = completedGames.suffix(5)
        if !recentGames.isEmpty {
            var resultLines: [String] = ["\(teamName) recent game results:"]
            for game in recentGames {
                let isHome = game.homeTeamKey == teamKey
                let opponent = isHome ? game.awayTeamName : game.homeTeamName
                let venue = isHome ? "home game against" : "away game at"
                let teamScore = isHome ? game.homeScore : game.awayScore
                let oppScore = isHome ? game.awayScore : game.homeScore
                if let ts = teamScore, let os = oppScore {
                    let result = ts > os ? "Won" : "Lost"
                    var line = "\(result) \(ts) to \(os) in a \(venue) \(opponent)"
                    if let dt = game.dateTime {
                        line += " on \(dateFormatter.string(from: dt))"
                    }
                    if let channel = game.channel {
                        line += " (broadcast on \(channel))"
                    }
                    resultLines.append(line)
                }
            }

            if resultLines.count > 1 {
                entries.append(KnowledgeEntry(
                    id: "sports-schedule-recent-\(teamKey)",
                    section: "Recent Game Results: \(teamName)",
                    content: resultLines.joined(separator: ". ") + ".",
                    keywords: [teamName, "game results", "recent games", "scores", "schedule"]
                ))
            }
        }

        // Upcoming games
        let nextGames = upcomingGames.prefix(5)
        if !nextGames.isEmpty {
            var upcomingLines: [String] = ["\(teamName) upcoming scheduled games:"]
            for game in nextGames {
                let isHome = game.homeTeamKey == teamKey
                let opponent = isHome ? game.awayTeamName : game.homeTeamName
                let venue = isHome ? "home game against" : "away game at"
                var line = "\(venue) \(opponent)"
                if let dt = game.dateTime {
                    line += " on \(dateFormatter.string(from: dt))"
                }
                if let channel = game.channel {
                    line += " (broadcast on \(channel))"
                }
                if let stadium = game.stadium {
                    line += " at \(stadium)"
                }
                upcomingLines.append(line)
            }

            entries.append(KnowledgeEntry(
                id: "sports-schedule-upcoming-\(teamKey)",
                section: "Upcoming Games: \(teamName)",
                content: upcomingLines.joined(separator: ". ") + ".",
                keywords: [teamName, "upcoming games", "schedule", "next game"]
            ))
        }

        return entries
    }

    // MARK: - Roster to Knowledge

    static func mapRoster(_ players: [SportsPlayer], team: SportsTeam) -> [KnowledgeEntry] {
        guard !players.isEmpty else { return [] }

        // Determine the sport from context — infer from position abbreviations
        let sport = inferSport(from: players)

        var rosterLines: [String] = ["\(team.fullName) current roster with \(players.count) players:"]

        for player in players {
            var details: [String] = []
            details.append(player.fullName)

            if let jersey = player.jersey {
                details.append("jersey number \(jersey)")
            }
            if let pos = player.position {
                details.append("plays \(expandPosition(pos, sport: sport))")
            }
            if let cls = player.playerClass {
                details.append(cls)
            }
            if let height = player.heightDisplay {
                details.append(height)
            }
            if let weight = player.weight {
                details.append("\(weight) pounds")
            }
            if let hometown = player.hometown {
                details.append("from \(hometown)")
            }
            if let injury = player.injuryStatus, !injury.isEmpty, injury.lowercased() != "null" {
                var injuryDesc = "injury status: \(injury)"
                if let part = player.injuryBodyPart {
                    injuryDesc += " (\(part))"
                }
                details.append(injuryDesc)
            }

            rosterLines.append(details.joined(separator: ", "))
        }

        let content = rosterLines.joined(separator: ". ") + "."

        var keywords = [team.fullName, "roster", "players", "team"]
        // Add top player names as keywords for retrieval
        keywords.append(contentsOf: players.prefix(5).map { $0.fullName })

        return [KnowledgeEntry(
            id: "sports-roster-\(team.key)",
            section: "Team Roster: \(team.fullName)",
            content: content,
            keywords: keywords
        )]
    }

    /// Infer sport from player position abbreviations
    private static func inferSport(from players: [SportsPlayer]) -> Sport {
        let positions = Set(players.compactMap { $0.position?.uppercased() })
        let mlbPositions: Set<String> = ["P", "1B", "2B", "3B", "SS", "LF", "CF", "RF", "DH", "SP", "RP", "CL", "OF", "IF", "C"]
        if !positions.intersection(mlbPositions).isEmpty && positions.intersection(["PG", "SG", "SF", "PF"]).isEmpty {
            return .mlb
        }
        // Default to basketball since CBB and NBA use similar positions
        return .collegeBasketball
    }

    // MARK: - Create Knowledge Source

    static func createKnowledgeSource(
        entries: [KnowledgeEntry],
        title: String,
        characterId: UUID,
        sport: Sport,
        teamKey: String
    ) -> KnowledgeSource {
        let fileName = "sports_\(sport.rawValue)_\(teamKey)_\(UUID().uuidString.prefix(8)).jsonl"

        return KnowledgeSource(
            characterId: characterId,
            sourceType: .sportsData,
            title: title,
            sourceDescription: "\(sport.displayName) data including roster, player statistics, and game schedule",
            entries: entries,
            knowledgeFileName: fileName,
            uploadStatus: .pending
        )
    }
}
