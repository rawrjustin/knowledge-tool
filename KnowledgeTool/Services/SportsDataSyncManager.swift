import Foundation

/// Manages background refresh of sports data attachments.
/// Follows the same Timer-based pattern as SyncManager.
@MainActor
@Observable
final class SportsDataSyncManager {
    // MARK: - State

    private(set) var isRefreshing = false
    private(set) var lastRefreshDate: Date?
    private(set) var refreshError: String?

    // MARK: - Dependencies

    private let apiKeyManager: APIKeyManager
    private let repository: CombinedCharacterRepository
    private var refreshTimer: Timer?

    // MARK: - Default Interval

    /// Default refresh interval: 60 minutes
    private let defaultInterval: TimeInterval = 60 * 60

    // MARK: - Init

    init(apiKeyManager: APIKeyManager, repository: CombinedCharacterRepository) {
        self.apiKeyManager = apiKeyManager
        self.repository = repository
    }

    // MARK: - Periodic Refresh

    func startPeriodicRefresh() {
        stopPeriodicRefresh()

        guard apiKeyManager.hasAPIKey(for: .sportsDataIO) else {
            NSLog("[SportsDataSync] Not starting - no API key configured")
            return
        }

        NSLog("[SportsDataSync] Starting periodic refresh every %.0f seconds", defaultInterval)

        refreshTimer = Timer.scheduledTimer(withTimeInterval: defaultInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.refreshAllAttachments()
            }
        }
    }

    func stopPeriodicRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    // MARK: - Refresh All

    func refreshAllAttachments() async {
        guard !isRefreshing else { return }
        guard let apiKey = apiKeyManager.getAPIKey(for: .sportsDataIO) else { return }

        isRefreshing = true
        refreshError = nil
        defer {
            isRefreshing = false
            lastRefreshDate = Date()
        }

        // Find all characters with sports data attachments
        do {
            let characters = try await repository.loadAllCharacters()

            for character in characters {
                let key = "sportsdata_attachments_\(character.id.uuidString)"
                guard let data = UserDefaults.standard.data(forKey: key),
                      var attachments = try? JSONDecoder().decode([SportsDataAttachment].self, from: data) else {
                    continue
                }

                var updated = false
                for (index, attachment) in attachments.enumerated() {
                    guard attachment.isAutoRefreshEnabled else { continue }

                    // Check if enough time has passed
                    if let lastRefresh = attachment.lastRefreshed {
                        let intervalSeconds = TimeInterval(attachment.refreshIntervalMinutes * 60)
                        guard Date().timeIntervalSince(lastRefresh) >= intervalSeconds else { continue }
                    }

                    NSLog("[SportsDataSync] Refreshing %@ for character %@", attachment.teamName, character.name)

                    let provider = SportsDataProviderFactory.makeProvider(
                        sport: attachment.sport, apiKey: apiKey
                    )

                    let season = "\(Calendar.current.component(.year, from: Date()))"
                    let freshPlayers = try await provider.fetchPlayers(teamKey: attachment.teamKey)
                    let freshStats = try await provider.fetchPlayerSeasonStats(season: season, teamKey: attachment.teamKey)
                    let freshSchedule = try await provider.fetchTeamSchedule(season: season, teamKey: attachment.teamKey)

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

                    // Save updated knowledge
                    let content = entries.compactMap { entry -> String? in
                        guard let data = try? JSONEncoder().encode(entry),
                              let json = String(data: data, encoding: .utf8) else { return nil }
                        return json
                    }.joined(separator: "\n")

                    let fileName = "sports_\(attachment.sport.rawValue)_\(attachment.teamKey)_auto.jsonl"
                    _ = try await repository.createKnowledgeFile(
                        for: character,
                        fileName: fileName,
                        content: content
                    )

                    attachments[index].lastRefreshed = Date()
                    updated = true
                }

                if updated {
                    if let encoded = try? JSONEncoder().encode(attachments) {
                        UserDefaults.standard.set(encoded, forKey: key)
                    }
                }
            }
        } catch {
            refreshError = error.localizedDescription
            NSLog("[SportsDataSync] Refresh failed: %@", error.localizedDescription)
        }
    }

    /// Manual refresh for a specific character
    func refreshNow(for character: Character) async {
        guard let apiKey = apiKeyManager.getAPIKey(for: .sportsDataIO) else { return }

        let key = "sportsdata_attachments_\(character.id.uuidString)"
        guard let data = UserDefaults.standard.data(forKey: key),
              var attachments = try? JSONDecoder().decode([SportsDataAttachment].self, from: data) else {
            return
        }

        isRefreshing = true
        defer { isRefreshing = false }

        for (index, attachment) in attachments.enumerated() {
            let provider = SportsDataProviderFactory.makeProvider(
                sport: attachment.sport, apiKey: apiKey
            )

            do {
                let season = "\(Calendar.current.component(.year, from: Date()))"
                let freshPlayers = try await provider.fetchPlayers(teamKey: attachment.teamKey)
                let freshStats = try await provider.fetchPlayerSeasonStats(season: season, teamKey: attachment.teamKey)
                let freshSchedule = try await provider.fetchTeamSchedule(season: season, teamKey: attachment.teamKey)

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

                let content = entries.compactMap { entry -> String? in
                    guard let d = try? JSONEncoder().encode(entry),
                          let json = String(data: d, encoding: .utf8) else { return nil }
                    return json
                }.joined(separator: "\n")

                let fileName = "sports_\(attachment.sport.rawValue)_\(attachment.teamKey)_manual.jsonl"
                _ = try await repository.createKnowledgeFile(
                    for: character,
                    fileName: fileName,
                    content: content
                )

                attachments[index].lastRefreshed = Date()
            } catch {
                NSLog("[SportsDataSync] Failed to refresh %@: %@", attachment.teamName, error.localizedDescription)
            }
        }

        if let encoded = try? JSONEncoder().encode(attachments) {
            UserDefaults.standard.set(encoded, forKey: key)
        }

        lastRefreshDate = Date()
    }
}
