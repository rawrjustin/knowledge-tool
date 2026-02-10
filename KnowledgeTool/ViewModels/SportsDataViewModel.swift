import Foundation

@MainActor
@Observable
final class SportsDataViewModel {
    // MARK: - Dependencies
    private(set) var character: Character
    private let repository: CombinedCharacterRepository
    private let apiKeyManager: APIKeyManager

    // MARK: - Browse State
    var selectedSport: Sport = .collegeBasketball
    var conferences: [SportsConference] = []
    var selectedConference: SportsConference?
    var teams: [SportsTeam] = []
    var selectedTeam: SportsTeam?
    var players: [SportsPlayer] = []
    var selectedPlayer: SportsPlayer?
    var searchQuery: String = ""

    // MARK: - Stats State
    var playerSeasonStats: [SportsPlayerStats] = []
    var teamSeasonStats: [SportsTeamStats] = []
    var recentGames: [SportsGame] = []
    var currentSeason: SportsSeason?

    // MARK: - Detail Tab
    enum TeamTab: String, CaseIterable {
        case roster = "Roster"
        case stats = "Stats"
        case schedule = "Schedule"
    }
    var selectedTeamTab: TeamTab = .roster

    // MARK: - Attachment State
    var attachments: [SportsDataAttachment] = []

    // MARK: - Loading State
    var isLoadingConferences = false
    var isLoadingTeam = false
    var isLoadingStats = false
    var isLoadingSchedule = false
    var isRefreshing = false
    var error: String?

    // MARK: - Attach Sheet
    var showingAttachSheet = false
    var attachPreviewEntries: [KnowledgeEntry] = []

    // MARK: - Provider
    private var provider: (any SportsDataProvider)?

    // MARK: - Persistence Key
    private var attachmentsKey: String {
        "sportsdata_attachments_\(character.id.uuidString)"
    }

    // MARK: - Init

    init(character: Character, repository: CombinedCharacterRepository, apiKeyManager: APIKeyManager) {
        self.character = character
        self.repository = repository
        self.apiKeyManager = apiKeyManager
        loadAttachments()
    }

    // MARK: - Provider Management

    private func ensureProvider() throws -> any SportsDataProvider {
        if let p = provider, Task.isCancelled == false {
            return p
        }
        guard let apiKey = apiKeyManager.getAPIKey(for: .sportsDataIO) else {
            throw SportsDataError.invalidAPIKey
        }
        let p = SportsDataProviderFactory.makeProvider(sport: selectedSport, apiKey: apiKey)
        provider = p
        return p
    }

    /// Recreate provider when sport changes
    func onSportChanged() {
        provider = nil
        conferences = []
        selectedConference = nil
        teams = []
        selectedTeam = nil
        players = []
        selectedPlayer = nil
        playerSeasonStats = []
        teamSeasonStats = []
        recentGames = []
        currentSeason = nil
        error = nil
    }

    // MARK: - Data Loading

    func loadConferences() async {
        isLoadingConferences = true
        error = nil
        defer { isLoadingConferences = false }

        do {
            let p = try ensureProvider()
            conferences = try await p.fetchConferences()

            // Also fetch current season
            currentSeason = try? await p.fetchCurrentSeason()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func loadTeam(key: String) async {
        isLoadingTeam = true
        error = nil
        defer { isLoadingTeam = false }

        do {
            let p = try ensureProvider()
            players = try await p.fetchPlayers(teamKey: key)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func loadPlayerStats(teamKey: String) async {
        isLoadingStats = true
        error = nil
        defer { isLoadingStats = false }

        do {
            let p = try ensureProvider()
            let season = currentSeason?.apiSeason ?? "\(Calendar.current.component(.year, from: Date()))"
            playerSeasonStats = try await p.fetchPlayerSeasonStats(season: season, teamKey: teamKey)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func loadTeamSchedule(teamKey: String) async {
        isLoadingSchedule = true
        error = nil
        defer { isLoadingSchedule = false }

        do {
            let p = try ensureProvider()
            let season = currentSeason?.apiSeason ?? "\(Calendar.current.component(.year, from: Date()))"
            recentGames = try await p.fetchTeamSchedule(season: season, teamKey: teamKey)
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Team Selection

    func selectTeam(_ team: SportsTeam) {
        selectedTeam = team
        selectedPlayer = nil
        selectedTeamTab = .roster
        playerSeasonStats = []
        recentGames = []

        Task {
            await loadTeam(key: team.key)
        }
    }

    func selectConference(_ conference: SportsConference) {
        selectedConference = conference
        teams = conference.teams
        selectedTeam = nil
        selectedPlayer = nil
    }

    // MARK: - Tab Loading

    func onTeamTabChanged() {
        guard let team = selectedTeam else { return }
        switch selectedTeamTab {
        case .roster:
            if players.isEmpty {
                Task { await loadTeam(key: team.key) }
            }
        case .stats:
            if playerSeasonStats.isEmpty {
                Task { await loadPlayerStats(teamKey: team.key) }
            }
        case .schedule:
            if recentGames.isEmpty {
                Task { await loadTeamSchedule(teamKey: team.key) }
            }
        }
    }

    // MARK: - Search

    var filteredConferences: [SportsConference] {
        guard !searchQuery.isEmpty else { return conferences }
        return conferences.compactMap { conf in
            let matchingTeams = conf.teams.filter {
                $0.fullName.localizedCaseInsensitiveContains(searchQuery) ||
                $0.key.localizedCaseInsensitiveContains(searchQuery)
            }
            if conf.name.localizedCaseInsensitiveContains(searchQuery) || !matchingTeams.isEmpty {
                var filtered = conf
                if !matchingTeams.isEmpty {
                    filtered.teams = matchingTeams
                }
                return filtered
            }
            return nil
        }
    }

    // MARK: - Attachment Management

    func prepareAttachment() {
        guard let team = selectedTeam else { return }

        var entries: [KnowledgeEntry] = []

        // Team roster
        if !players.isEmpty {
            entries += SportsDataKnowledgeMapper.mapRoster(players, team: team)
        }

        // Player stats
        for stat in playerSeasonStats {
            let player = players.first { $0.id == stat.playerId }
            entries += SportsDataKnowledgeMapper.mapPlayerStats(stat, player: player, sport: selectedSport)
        }

        // Schedule
        if !recentGames.isEmpty {
            entries += SportsDataKnowledgeMapper.mapSchedule(recentGames, teamKey: team.key, teamName: team.fullName)
        }

        attachPreviewEntries = entries
        showingAttachSheet = true
    }

    func attachToCharacter() async {
        guard let team = selectedTeam else { return }

        let source = SportsDataKnowledgeMapper.createKnowledgeSource(
            entries: attachPreviewEntries,
            title: "\(team.fullName) - \(selectedSport.displayName)",
            characterId: character.id,
            sport: selectedSport,
            teamKey: team.key
        )

        // Save knowledge file
        let content = attachPreviewEntries.compactMap { entry -> String? in
            guard let data = try? JSONEncoder().encode(entry),
                  let json = String(data: data, encoding: .utf8) else { return nil }
            return json
        }.joined(separator: "\n")

        do {
            _ = try await repository.createKnowledgeFile(
                for: character,
                fileName: source.knowledgeFileName,
                content: content
            )
        } catch {
            self.error = "Failed to save knowledge: \(error.localizedDescription)"
            return
        }

        // Save attachment tracking
        let attachment = SportsDataAttachment(
            characterId: character.id,
            sport: selectedSport,
            teamKey: team.key,
            teamName: team.fullName,
            playerIds: playerSeasonStats.map { $0.playerId },
            lastRefreshed: Date(),
            knowledgeSourceId: source.id
        )

        attachments.append(attachment)
        saveAttachments()
        showingAttachSheet = false
    }

    func detachFromCharacter(_ attachment: SportsDataAttachment) {
        attachments.removeAll { $0.id == attachment.id }
        saveAttachments()
    }

    // MARK: - Refresh

    func refreshAttachment(_ attachment: SportsDataAttachment) async {
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            guard let apiKey = apiKeyManager.getAPIKey(for: .sportsDataIO) else {
                throw SportsDataError.invalidAPIKey
            }

            let p = SportsDataProviderFactory.makeProvider(sport: attachment.sport, apiKey: apiKey)
            let season = currentSeason?.apiSeason ?? "\(Calendar.current.component(.year, from: Date()))"

            // Fetch latest data
            let freshPlayers = try await p.fetchPlayers(teamKey: attachment.teamKey)
            let freshStats = try await p.fetchPlayerSeasonStats(season: season, teamKey: attachment.teamKey)
            let freshSchedule = try await p.fetchTeamSchedule(season: season, teamKey: attachment.teamKey)

            let team = SportsTeam(
                id: 0, key: attachment.teamKey, school: "", name: attachment.teamName,
                conference: nil, logoURL: nil
            )

            var entries: [KnowledgeEntry] = []
            entries += SportsDataKnowledgeMapper.mapRoster(freshPlayers, team: team)
            for stat in freshStats {
                let player = freshPlayers.first { $0.id == stat.playerId }
                entries += SportsDataKnowledgeMapper.mapPlayerStats(stat, player: player, sport: attachment.sport)
            }
            entries += SportsDataKnowledgeMapper.mapSchedule(freshSchedule, teamKey: attachment.teamKey, teamName: attachment.teamName)

            // Update knowledge file
            let content = entries.compactMap { entry -> String? in
                guard let data = try? JSONEncoder().encode(entry),
                      let json = String(data: data, encoding: .utf8) else { return nil }
                return json
            }.joined(separator: "\n")

            let fileName = "sports_\(attachment.sport.rawValue)_\(attachment.teamKey)_refresh.jsonl"
            _ = try await repository.createKnowledgeFile(
                for: character,
                fileName: fileName,
                content: content
            )

            // Update attachment timestamp
            if let idx = attachments.firstIndex(where: { $0.id == attachment.id }) {
                attachments[idx].lastRefreshed = Date()
                saveAttachments()
            }
        } catch {
            self.error = "Refresh failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Persistence (UserDefaults)

    private func loadAttachments() {
        guard let data = UserDefaults.standard.data(forKey: attachmentsKey),
              let decoded = try? JSONDecoder().decode([SportsDataAttachment].self, from: data) else {
            return
        }
        attachments = decoded
    }

    private func saveAttachments() {
        guard let data = try? JSONEncoder().encode(attachments) else { return }
        UserDefaults.standard.set(data, forKey: attachmentsKey)
    }

    // MARK: - Computed

    var hasAPIKey: Bool {
        apiKeyManager.hasAPIKey(for: .sportsDataIO)
    }
}
