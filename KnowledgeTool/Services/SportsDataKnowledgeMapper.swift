import Foundation

// MARK: - Sports Data Knowledge Mapper

/// Converts sports data into KnowledgeEntry and KnowledgeSource objects
/// for integration into the character knowledge pipeline.
struct SportsDataKnowledgeMapper {

    // MARK: - Player Stats to Knowledge

    static func mapPlayerStats(
        _ stats: SportsPlayerStats,
        player: SportsPlayer? = nil,
        sport: Sport
    ) -> [KnowledgeEntry] {
        var entries: [KnowledgeEntry] = []
        let name = player?.fullName ?? stats.playerName

        // Overview entry
        var overview = "\(name)"
        if let pos = stats.position ?? player?.position {
            overview += " (\(pos))"
        }
        if let cls = player?.playerClass {
            overview += ", \(cls)"
        }
        overview += " played \(stats.games) games"

        switch sport {
        case .collegeBasketball, .nba:
            if let ppg = stats.points {
                overview += ", averaging \(String(format: "%.1f", ppg)) PPG"
            }
            if let rpg = stats.rebounds {
                overview += ", \(String(format: "%.1f", rpg)) RPG"
            }
            if let apg = stats.assists {
                overview += ", \(String(format: "%.1f", apg)) APG"
            }
        case .mlb:
            if let avg = stats.battingAverage {
                overview += " with a \(String(format: "%.3f", avg)) batting average"
            }
            if let hr = stats.homeRuns, hr > 0 {
                overview += ", \(Int(hr)) HR"
            }
            if let rbi = stats.rbi, rbi > 0 {
                overview += ", \(Int(rbi)) RBI"
            }
        }
        overview += "."

        entries.append(KnowledgeEntry(
            id: "sports-player-overview-\(stats.playerId)",
            section: "Player Stats: \(name)",
            content: overview,
            keywords: [name, stats.position ?? "", sport.shortName, "stats", "season"].filter { !$0.isEmpty }
        ))

        // Detailed shooting/stats entry for basketball
        if sport == .collegeBasketball || sport == .nba {
            var shooting = "\(name) shooting splits: "
            var parts: [String] = []
            if let fgp = stats.fieldGoalPercentage {
                parts.append("\(String(format: "%.1f", fgp * 100))% FG")
            }
            if let tpp = stats.threePointPercentage {
                parts.append("\(String(format: "%.1f", tpp * 100))% 3PT")
            }
            if let ftp = stats.freeThrowPercentage {
                parts.append("\(String(format: "%.1f", ftp * 100))% FT")
            }
            if !parts.isEmpty {
                shooting += parts.joined(separator: ", ")
                if let stl = stats.steals {
                    shooting += ". Also averages \(String(format: "%.1f", stl)) steals"
                }
                if let blk = stats.blocks {
                    shooting += " and \(String(format: "%.1f", blk)) blocks per game"
                }
                shooting += "."

                entries.append(KnowledgeEntry(
                    id: "sports-player-shooting-\(stats.playerId)",
                    section: "Shooting: \(name)",
                    content: shooting,
                    keywords: [name, "shooting", "field goal", "three point", "free throw"]
                ))
            }
        }

        // MLB pitching stats
        if sport == .mlb, let era = stats.era {
            var pitching = "\(name) pitching: \(String(format: "%.2f", era)) ERA"
            if let k = stats.strikeouts {
                pitching += ", \(Int(k)) strikeouts"
            }
            if let bb = stats.walks {
                pitching += ", \(Int(bb)) walks"
            }
            pitching += "."

            entries.append(KnowledgeEntry(
                id: "sports-player-pitching-\(stats.playerId)",
                section: "Pitching: \(name)",
                content: pitching,
                keywords: [name, "pitching", "ERA", "strikeouts"]
            ))
        }

        return entries
    }

    // MARK: - Team Stats to Knowledge

    static func mapTeamStats(_ stats: SportsTeamStats, sport: Sport) -> [KnowledgeEntry] {
        var entries: [KnowledgeEntry] = []

        var overview = "\(stats.teamName) season record: \(stats.wins)-\(stats.losses) in \(stats.games) games."

        switch sport {
        case .collegeBasketball, .nba:
            if let ppg = stats.points {
                overview += " Scoring \(String(format: "%.1f", ppg)) points per game"
            }
            if let opp = stats.pointsAllowed {
                overview += ", allowing \(String(format: "%.1f", opp))"
            }
            overview += "."
            if let fgp = stats.fieldGoalPercentage {
                overview += " Shooting \(String(format: "%.1f", fgp * 100))% from the field"
            }
            if let tpp = stats.threePointPercentage {
                overview += ", \(String(format: "%.1f", tpp * 100))% from three"
            }
            overview += "."
        case .mlb:
            if let ppg = stats.points {
                overview += " Scoring \(String(format: "%.1f", ppg)) runs per game."
            }
        }

        entries.append(KnowledgeEntry(
            id: "sports-team-overview-\(stats.teamKey)",
            section: "Team Stats: \(stats.teamName)",
            content: overview,
            keywords: [stats.teamName, stats.teamKey, sport.shortName, "team stats", "record"]
        ))

        return entries
    }

    // MARK: - Schedule to Knowledge

    static func mapSchedule(_ games: [SportsGame], teamKey: String, teamName: String) -> [KnowledgeEntry] {
        guard !games.isEmpty else { return [] }

        let completedGames = games.filter { $0.isCompleted }
        let upcomingGames = games.filter { !$0.isCompleted }

        var entries: [KnowledgeEntry] = []

        // Recent results
        let recentGames = completedGames.suffix(5)
        if !recentGames.isEmpty {
            var results = "\(teamName) recent results: "
            let gameResults = recentGames.map { game -> String in
                let isHome = game.homeTeamKey == teamKey
                let opponent = isHome ? game.awayTeamName : game.homeTeamName
                let teamScore = isHome ? game.homeScore : game.awayScore
                let oppScore = isHome ? game.awayScore : game.homeScore
                if let ts = teamScore, let os = oppScore {
                    let result = ts > os ? "W" : "L"
                    return "\(result) vs \(opponent) \(ts)-\(os)"
                }
                return "vs \(opponent)"
            }
            results += gameResults.joined(separator: "; ") + "."

            entries.append(KnowledgeEntry(
                id: "sports-schedule-recent-\(teamKey)",
                section: "Recent Games: \(teamName)",
                content: results,
                keywords: [teamName, "schedule", "results", "recent games"]
            ))
        }

        // Upcoming games
        let nextGames = upcomingGames.prefix(5)
        if !nextGames.isEmpty {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "MMM d"

            var upcoming = "\(teamName) upcoming games: "
            let gameList = nextGames.compactMap { game -> String? in
                let isHome = game.homeTeamKey == teamKey
                let opponent = isHome ? game.awayTeamName : game.homeTeamName
                let location = isHome ? "vs" : "at"
                if let dt = game.dateTime {
                    return "\(dateFormatter.string(from: dt)) \(location) \(opponent)"
                }
                return "\(location) \(opponent)"
            }
            upcoming += gameList.joined(separator: "; ") + "."

            entries.append(KnowledgeEntry(
                id: "sports-schedule-upcoming-\(teamKey)",
                section: "Upcoming Games: \(teamName)",
                content: upcoming,
                keywords: [teamName, "schedule", "upcoming", "next game"]
            ))
        }

        return entries
    }

    // MARK: - Roster to Knowledge

    static func mapRoster(_ players: [SportsPlayer], team: SportsTeam) -> [KnowledgeEntry] {
        guard !players.isEmpty else { return [] }

        var roster = "\(team.fullName) roster (\(players.count) players): "
        let playerList = players.map { player -> String in
            var desc = "#\(player.jersey ?? 0) \(player.fullName)"
            if let pos = player.position { desc += " (\(pos))" }
            if let cls = player.playerClass { desc += " - \(cls)" }
            return desc
        }
        roster += playerList.joined(separator: "; ") + "."

        return [KnowledgeEntry(
            id: "sports-roster-\(team.key)",
            section: "Roster: \(team.fullName)",
            content: roster,
            keywords: [team.fullName, team.key, "roster", "players", "team"]
        )]
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
            sourceDescription: "Live sports data from \(sport.displayName)",
            entries: entries,
            knowledgeFileName: fileName,
            uploadStatus: .pending
        )
    }
}
