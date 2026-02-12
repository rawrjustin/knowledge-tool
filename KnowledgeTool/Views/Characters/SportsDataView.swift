import SwiftUI

// MARK: - Sports Data View

struct SportsDataView: View {
    let character: Character
    let repository: CombinedCharacterRepository
    let apiKeyManager: APIKeyManager

    @State private var viewModel: SportsDataViewModel?

    var body: some View {
        Group {
            if let vm = viewModel {
                if !vm.hasAPIKey {
                    noAPIKeyView
                } else {
                    mainContent(vm: vm)
                }
            } else {
                ProgressView()
            }
        }
        .onAppear {
            if viewModel == nil {
                viewModel = SportsDataViewModel(
                    character: character,
                    repository: repository,
                    apiKeyManager: apiKeyManager
                )
            }
        }
    }

    // MARK: - No API Key

    private var noAPIKeyView: some View {
        EmptyStateView(
            icon: "sportscourt.fill",
            title: "Sports Data Not Configured",
            message: "Add your SportsData.io API key in Settings to browse teams, players, and stats.",
            actionLabel: "Open Settings",
            action: {
                NotificationCenter.default.post(name: .openSettings, object: nil)
            }
        )
    }

    // MARK: - Main Content

    @ViewBuilder
    private func mainContent(vm: SportsDataViewModel) -> some View {
        VStack(spacing: 0) {
            // Sport picker + search bar
            sportPickerBar(vm: vm)

            Divider()

            // Split: browser on left, detail on right
            HSplitView {
                conferenceBrowser(vm: vm)
                    .frame(minWidth: 220, idealWidth: 260, maxWidth: 320)

                teamDetailPanel(vm: vm)
                    .frame(minWidth: 400)
            }
        }
        .task {
            if vm.conferences.isEmpty {
                await vm.loadConferences()
            }
        }
        .sheet(isPresented: Binding(
            get: { vm.showingAttachSheet },
            set: { vm.showingAttachSheet = $0 }
        )) {
            attachSheet(vm: vm)
        }
    }

    // MARK: - Sport Picker Bar

    private func sportPickerBar(vm: SportsDataViewModel) -> some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            // Sport segmented control
            Picker("Sport", selection: Binding(
                get: { vm.selectedSport },
                set: { newSport in
                    vm.selectedSport = newSport
                    vm.onSportChanged()
                    Task { await vm.loadConferences() }
                }
            )) {
                ForEach(Sport.allCases) { sport in
                    Label(sport.shortName, systemImage: sport.icon)
                        .tag(sport)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 300)

            Spacer()

            // Search
            HStack(spacing: DesignSystem.Spacing.sm) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search teams...", text: Binding(
                    get: { vm.searchQuery },
                    set: { vm.searchQuery = $0 }
                ))
                .textFieldStyle(.plain)
                if !vm.searchQuery.isEmpty {
                    Button {
                        vm.searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, DesignSystem.Spacing.md)
            .padding(.vertical, DesignSystem.Spacing.sm)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
            .frame(maxWidth: 250)
        }
        .padding(.horizontal, DesignSystem.Spacing.lg)
        .padding(.vertical, DesignSystem.Spacing.md)
    }

    // MARK: - Conference Browser (Left Panel)

    private func conferenceBrowser(vm: SportsDataViewModel) -> some View {
        VStack(spacing: 0) {
            if vm.isLoadingConferences {
                VStack {
                    Spacer()
                    ProgressView("Loading conferences...")
                    Spacer()
                }
            } else if vm.filteredConferences.isEmpty {
                VStack(spacing: DesignSystem.Spacing.md) {
                    Spacer()
                    Image(systemName: "sportscourt")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)
                    Text(vm.searchQuery.isEmpty ? "No conferences found" : "No results")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            } else {
                List(selection: Binding(
                    get: { vm.selectedTeam?.key },
                    set: { key in
                        if let key, let team = vm.filteredConferences.flatMap(\.teams).first(where: { $0.key == key }) {
                            vm.selectTeam(team)
                        }
                    }
                )) {
                    // Attached teams section
                    if !vm.attachments.isEmpty {
                        Section("Attached") {
                            ForEach(vm.attachments) { attachment in
                                attachedTeamRow(attachment: attachment, vm: vm)
                            }
                        }
                    }

                    // Conference/team hierarchy
                    ForEach(vm.filteredConferences) { conference in
                        Section(conference.name) {
                            ForEach(conference.teams) { team in
                                teamRow(team: team, vm: vm)
                                    .tag(team.key)
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
            }

            if let error = vm.error {
                HStack(spacing: DesignSystem.Spacing.xs) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .padding(DesignSystem.Spacing.sm)
                .background(Color.orange.opacity(0.1))
            }
        }
    }

    private func teamRow(team: SportsTeam, vm: SportsDataViewModel) -> some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(team.school)
                    .font(.subheadline.weight(.medium))
                Text(team.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let rank = team.apRank, rank > 0 {
                Text("#\(rank)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.orange)
            }

            if let record = team.record {
                Text(record)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func attachedTeamRow(attachment: SportsDataAttachment, vm: SportsDataViewModel) -> some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.caption)

            VStack(alignment: .leading, spacing: 2) {
                Text(attachment.teamName)
                    .font(.subheadline.weight(.medium))
                if let last = attachment.lastRefreshed {
                    Text(last, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            Button {
                Task { await vm.refreshAttachment(attachment) }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .help("Refresh data")
        }
    }

    // MARK: - Team Detail Panel (Right Panel)

    @ViewBuilder
    private func teamDetailPanel(vm: SportsDataViewModel) -> some View {
        if let team = vm.selectedTeam {
            ScrollView {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
                    // Team Header
                    teamHeader(team: team, vm: vm)

                    Divider()

                    // Tab bar
                    Picker("Tab", selection: Binding(
                        get: { vm.selectedTeamTab },
                        set: { newTab in
                            vm.selectedTeamTab = newTab
                            vm.onTeamTabChanged()
                        }
                    )) {
                        ForEach(SportsDataViewModel.TeamTab.allCases, id: \.self) { tab in
                            Text(tab.rawValue).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 300)

                    // Tab content
                    switch vm.selectedTeamTab {
                    case .roster:
                        rosterTab(vm: vm)
                    case .stats:
                        statsTab(vm: vm)
                    case .schedule:
                        scheduleTab(vm: vm)
                    }

                    Divider()

                    // Attachment controls
                    attachmentControls(team: team, vm: vm)
                }
                .padding(DesignSystem.Spacing.xl)
            }
        } else {
            VStack(spacing: DesignSystem.Spacing.lg) {
                Image(systemName: "sportscourt")
                    .font(.system(size: 48))
                    .foregroundStyle(.tertiary)
                Text("Select a team to view details")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text("Browse conferences on the left or use the search bar")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func teamHeader(team: SportsTeam, vm: SportsDataViewModel) -> some View {
        HStack(spacing: DesignSystem.Spacing.lg) {
            // Team color indicator
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small)
                .fill(teamColor(team))
                .frame(width: 6, height: 50)

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                HStack {
                    Text(team.fullName)
                        .font(.title2.weight(.bold))
                        .textSelection(.enabled)

                    if let rank = team.apRank, rank > 0 {
                        StatusBadge(text: "#\(rank) AP", status: .warning, showIcon: false)
                    }
                }

                HStack(spacing: DesignSystem.Spacing.md) {
                    if let record = team.record {
                        Label(record, systemImage: "chart.bar.fill")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    if let stadium = team.stadium {
                        Label(stadium.name, systemImage: "building.2")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    if let conf = team.conference {
                        Label(conf, systemImage: "rectangle.3.group")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .textSelection(.enabled)
            }

            Spacer()
        }
    }

    // MARK: - Roster Tab

    @ViewBuilder
    private func rosterTab(vm: SportsDataViewModel) -> some View {
        if vm.isLoadingTeam {
            HStack {
                Spacer()
                ProgressView("Loading roster...")
                Spacer()
            }
            .padding(DesignSystem.Spacing.xl)
        } else if vm.players.isEmpty {
            Text("No players found")
                .foregroundStyle(.secondary)
                .padding()
        } else {
            LazyVGrid(columns: [
                GridItem(.flexible(), alignment: .leading),
                GridItem(.fixed(40), alignment: .center),
                GridItem(.fixed(60), alignment: .center),
                GridItem(.fixed(60), alignment: .center),
                GridItem(.fixed(80), alignment: .center),
                GridItem(.flexible(), alignment: .leading)
            ], spacing: DesignSystem.Spacing.sm) {
                // Header
                Group {
                    Text("Player").font(.caption.weight(.semibold))
                    Text("#").font(.caption.weight(.semibold))
                    Text("Pos").font(.caption.weight(.semibold))
                    Text("Ht").font(.caption.weight(.semibold))
                    Text("Class").font(.caption.weight(.semibold))
                    Text("Hometown").font(.caption.weight(.semibold))
                }
                .foregroundStyle(.secondary)

                Divider(); Divider(); Divider(); Divider(); Divider(); Divider()

                ForEach(vm.players) { player in
                    Text(player.fullName)
                        .font(.subheadline.weight(.medium))
                        .textSelection(.enabled)
                    Text(player.jersey != nil ? "\(player.jersey!)" : "-")
                        .font(.subheadline)
                        .textSelection(.enabled)
                    Text(player.position ?? "-")
                        .font(.subheadline)
                        .textSelection(.enabled)
                    Text(player.heightDisplay ?? "-")
                        .font(.subheadline)
                        .textSelection(.enabled)
                    Text(player.playerClass ?? "-")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    Text(player.hometown ?? "-")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .textSelection(.enabled)
                }
            }
        }
    }

    // MARK: - Stats Tab

    @ViewBuilder
    private func statsTab(vm: SportsDataViewModel) -> some View {
        if vm.isLoadingStats {
            HStack {
                Spacer()
                ProgressView("Loading stats...")
                Spacer()
            }
            .padding(DesignSystem.Spacing.xl)
        } else if vm.playerSeasonStats.isEmpty {
            VStack(spacing: DesignSystem.Spacing.md) {
                Text("No stats available yet")
                    .foregroundStyle(.secondary)
                Button("Load Stats") {
                    if let team = vm.selectedTeam {
                        Task { await vm.loadPlayerStats(teamKey: team.key) }
                    }
                }
                .buttonStyle(.bordered)
            }
            .padding()
        } else {
            ScrollView(.horizontal) {
                statsTable(stats: vm.playerSeasonStats)
            }
        }
    }

    private func statsTable(stats: [SportsPlayerStats]) -> some View {
        LazyVGrid(columns: [
            GridItem(.fixed(150), alignment: .leading),
            GridItem(.fixed(40), alignment: .center),
            GridItem(.fixed(50), alignment: .trailing),
            GridItem(.fixed(50), alignment: .trailing),
            GridItem(.fixed(50), alignment: .trailing),
            GridItem(.fixed(50), alignment: .trailing),
            GridItem(.fixed(50), alignment: .trailing),
            GridItem(.fixed(50), alignment: .trailing),
            GridItem(.fixed(55), alignment: .trailing)
        ], spacing: DesignSystem.Spacing.xs) {
            // Header
            Group {
                Text("Player").font(.caption.weight(.semibold))
                Text("GP").font(.caption.weight(.semibold))
                Text("PPG").font(.caption.weight(.semibold))
                Text("RPG").font(.caption.weight(.semibold))
                Text("APG").font(.caption.weight(.semibold))
                Text("SPG").font(.caption.weight(.semibold))
                Text("BPG").font(.caption.weight(.semibold))
                Text("FG%").font(.caption.weight(.semibold))
                Text("3PT%").font(.caption.weight(.semibold))
            }
            .foregroundStyle(.secondary)

            ForEach(stats) { stat in
                Text(stat.playerName)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                    .textSelection(.enabled)
                Text("\(stat.games)")
                    .font(.subheadline)
                    .textSelection(.enabled)
                Text(formatStat(stat.points))
                    .font(.subheadline)
                    .textSelection(.enabled)
                Text(formatStat(stat.rebounds))
                    .font(.subheadline)
                    .textSelection(.enabled)
                Text(formatStat(stat.assists))
                    .font(.subheadline)
                    .textSelection(.enabled)
                Text(formatStat(stat.steals))
                    .font(.subheadline)
                    .textSelection(.enabled)
                Text(formatStat(stat.blocks))
                    .font(.subheadline)
                    .textSelection(.enabled)
                Text(formatPct(stat.fieldGoalPercentage))
                    .font(.subheadline)
                    .textSelection(.enabled)
                Text(formatPct(stat.threePointPercentage))
                    .font(.subheadline)
                    .textSelection(.enabled)
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.sm)
    }

    // MARK: - Schedule Tab

    @ViewBuilder
    private func scheduleTab(vm: SportsDataViewModel) -> some View {
        if vm.isLoadingSchedule {
            HStack {
                Spacer()
                ProgressView("Loading schedule...")
                Spacer()
            }
            .padding(DesignSystem.Spacing.xl)
        } else if vm.recentGames.isEmpty {
            VStack(spacing: DesignSystem.Spacing.md) {
                Text("No schedule data available")
                    .foregroundStyle(.secondary)
                Button("Load Schedule") {
                    if let team = vm.selectedTeam {
                        Task { await vm.loadTeamSchedule(teamKey: team.key) }
                    }
                }
                .buttonStyle(.bordered)
            }
            .padding()
        } else {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                ForEach(vm.recentGames) { game in
                    gameRow(game: game, teamKey: vm.selectedTeam?.key ?? "")
                }
            }
        }
    }

    private func gameRow(game: SportsGame, teamKey: String) -> some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            // Date
            if let dt = game.dateTime {
                Text(dt, format: .dateTime.month(.abbreviated).day())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 50)
                    .textSelection(.enabled)
            }

            // Status indicator
            if game.isCompleted {
                let isHome = game.homeTeamKey == teamKey
                let teamScore = isHome ? game.homeScore : game.awayScore
                let oppScore = isHome ? game.awayScore : game.homeScore
                let won = (teamScore ?? 0) > (oppScore ?? 0)

                Circle()
                    .fill(won ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
            } else {
                Circle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 8, height: 8)
            }

            // Opponent
            let isHome = game.homeTeamKey == teamKey
            Text(isHome ? "vs \(game.awayTeamName)" : "at \(game.homeTeamName)")
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)

            // Score
            if let hs = game.homeScore, let as_ = game.awayScore {
                Text("\(isHome ? hs : as_) - \(isHome ? as_ : hs)")
                    .font(.subheadline.weight(.medium))
                    .monospacedDigit()
                    .textSelection(.enabled)
            } else {
                Text(game.status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            // Channel
            if let channel = game.channel {
                Text(channel)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(width: 50)
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, DesignSystem.Spacing.xs)
    }

    // MARK: - Attachment Controls

    private func attachmentControls(team: SportsTeam, vm: SportsDataViewModel) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            HStack {
                Label("Attach to Character", systemImage: "paperclip")
                    .font(.headline)
                Spacer()
            }

            let existingAttachment = vm.attachments.first { $0.teamKey == team.key && $0.sport == vm.selectedSport }

            if let attachment = existingAttachment {
                // Already attached
                HStack(spacing: DesignSystem.Spacing.md) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Attached to \(character.name)")
                            .font(.subheadline.weight(.medium))
                        if let last = attachment.lastRefreshed {
                            Text("Last pulled: \(last.formatted(.dateTime.month(.abbreviated).day().hour().minute()))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    Button {
                        Task { await vm.refreshAttachment(attachment) }
                    } label: {
                        Label("Refresh Now", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .disabled(vm.isRefreshing)

                    Button(role: .destructive) {
                        vm.detachFromCharacter(attachment)
                    } label: {
                        Label("Detach", systemImage: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                }
                .padding(DesignSystem.Spacing.md)
                .background(Color.green.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
            } else {
                // Not attached - show attach button
                HStack(spacing: DesignSystem.Spacing.md) {
                    Button {
                        // Load all data first if needed
                        Task {
                            if vm.playerSeasonStats.isEmpty {
                                await vm.loadPlayerStats(teamKey: team.key)
                            }
                            if vm.recentGames.isEmpty {
                                await vm.loadTeamSchedule(teamKey: team.key)
                            }
                            vm.prepareAttachment()
                        }
                    } label: {
                        Label("Attach \(team.fullName) to \(character.name)", systemImage: "paperclip")
                    }
                    .buttonStyle(.borderedProminent)

                    HelperText(
                        text: "Adds roster, stats, and schedule as knowledge entries",
                        icon: "info.circle"
                    )
                }
            }
        }
    }

    // MARK: - Attach Sheet

    private func attachSheet(vm: SportsDataViewModel) -> some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Preview Knowledge Entries")
                    .font(.headline)
                Spacer()
                Button("Cancel") {
                    vm.showingAttachSheet = false
                }
                .buttonStyle(.borderless)
            }
            .padding(DesignSystem.Spacing.lg)
            .background(.regularMaterial)

            Divider()

            // Preview entries
            ScrollView {
                LazyVStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                    ForEach(vm.attachPreviewEntries) { entry in
                        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                            Text(entry.section)
                                .font(.subheadline.weight(.semibold))
                                .textSelection(.enabled)
                            Text(entry.content)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                                .textSelection(.enabled)
                        }
                        .padding(DesignSystem.Spacing.md)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
                    }
                }
                .padding(DesignSystem.Spacing.lg)
            }

            Divider()

            // Footer
            HStack {
                Text("\(vm.attachPreviewEntries.count) knowledge entries")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    Task { await vm.attachToCharacter() }
                } label: {
                    Label("Attach to \(character.name)", systemImage: "paperclip")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(DesignSystem.Spacing.lg)
        }
        .frame(width: 500, height: 500)
    }

    // MARK: - Helpers

    private func teamColor(_ team: SportsTeam) -> Color {
        if let hex = team.primaryColor, !hex.isEmpty {
            return Color(hex: hex)
        }
        return .accentColor
    }

    private func formatStat(_ value: Double?) -> String {
        guard let v = value else { return "-" }
        return String(format: "%.1f", v)
    }

    private func formatPct(_ value: Double?) -> String {
        guard let v = value else { return "-" }
        return String(format: "%.1f", v * 100)
    }
}

// MARK: - Color Hex Extension

private extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: Double
        switch hex.count {
        case 6:
            r = Double((int >> 16) & 0xFF) / 255.0
            g = Double((int >> 8) & 0xFF) / 255.0
            b = Double(int & 0xFF) / 255.0
        default:
            r = 0.5; g = 0.5; b = 0.5
        }
        self.init(red: r, green: g, blue: b)
    }
}
