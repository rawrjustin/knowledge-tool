import SwiftUI

// MARK: - Dashboard Tab

enum DashboardTab: String, CaseIterable {
    case persona = "Persona"
    case knowledge = "Knowledge"
    case dialogExamples = "Dialog Examples"
    case scenarios = "Scenarios"

    var icon: String {
        switch self {
        case .persona: return "person.text.rectangle"
        case .knowledge: return "brain.head.profile"
        case .dialogExamples: return "text.bubble.fill"
        case .scenarios: return "theatermasks.fill"
        }
    }

    var description: String {
        switch self {
        case .persona: return "Identity, personality, and traits"
        case .knowledge: return "Sources and memories"
        case .dialogExamples: return "Sample conversations"
        case .scenarios: return "Roleplay situations"
        }
    }
}

// MARK: - Character Dashboard View

/// Unified dashboard showing all aspects of a character in one place
struct CharacterDashboardView: View {
    let character: Character
    let repository: CombinedCharacterRepository
    let apiKeyManager: APIKeyManager
    let onCharacterUpdated: (Character) -> Void

    @Environment(SyncManager.self) private var syncManager
    @State private var selectedTab: DashboardTab = .persona
    @State private var showingAugmentSheet = false
    @State private var showingEditSheet = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            dashboardHeader

            Divider()

            // Tab bar
            tabBar

            Divider()

            // Content
            tabContent
        }
        .sheet(isPresented: $showingAugmentSheet) {
            BrainAugmentationView(
                character: character,
                repository: repository,
                apiKeyManager: apiKeyManager,
                onComplete: { updated in
                    showingAugmentSheet = false
                    onCharacterUpdated(updated)
                },
                onCancel: { showingAugmentSheet = false }
            )
        }
    }

    // MARK: - Header

    private var dashboardHeader: some View {
        HStack(alignment: .center, spacing: DesignSystem.Spacing.lg) {
            // Character avatar and name
            HStack(spacing: DesignSystem.Spacing.md) {
                CharacterAvatar(name: character.name, size: 48)

                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxs) {
                    Text(character.name)
                        .font(.title2.weight(.semibold))

                    HStack(spacing: DesignSystem.Spacing.sm) {
                        // Version badge
                        Text(character.versionDisplay)
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.purple.opacity(0.15))
                            .foregroundStyle(.purple)
                            .clipShape(Capsule())

                        // System prompt type
                        Text(character.systemPromptType.rawValue)
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.15))
                            .foregroundStyle(.blue)
                            .clipShape(Capsule())

                        // Cloud sync status
                        if syncManager.canSync {
                            SyncStatusIndicator()
                        }

                        // Last modified
                        Text(character.lastModified.formatted(.relative(presentation: .named)))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            // Quick stats
            HStack(spacing: DesignSystem.Spacing.xl) {
                QuickStat(
                    icon: "doc.text",
                    value: "\(wordCount(character.markdownContent))",
                    label: "Words"
                )

                QuickStat(
                    icon: "folder",
                    value: "\(character.knowledgeSources.count)",
                    label: "Sources"
                )

                QuickStat(
                    icon: "brain",
                    value: "\(character.totalKnowledgeEntries)",
                    label: "Memories"
                )
            }

            // Actions
            HStack(spacing: DesignSystem.Spacing.sm) {
                Button {
                    showingAugmentSheet = true
                } label: {
                    Label("Augment", systemImage: "sparkles")
                }
                .buttonStyle(.bordered)
                .help("Add source content to enhance this persona")

                Button {
                    showingEditSheet = true
                } label: {
                    Label("Edit", systemImage: "square.and.pencil")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(DesignSystem.Spacing.lg)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(DashboardTab.allCases, id: \.self) { tab in
                DashboardTabButton(
                    tab: tab,
                    isSelected: selectedTab == tab,
                    badge: badgeFor(tab)
                ) {
                    withAnimation(DesignSystem.Animation.quick) {
                        selectedTab = tab
                    }
                }
            }

            Spacer()
        }
        .padding(.horizontal, DesignSystem.Spacing.lg)
        .padding(.vertical, DesignSystem.Spacing.sm)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }

    private func badgeFor(_ tab: DashboardTab) -> String? {
        switch tab {
        case .persona:
            return nil
        case .knowledge:
            let count = character.knowledgeSources.count
            return count > 0 ? "\(count)" : nil
        case .dialogExamples:
            let count = dialogExamplesCount
            return count > 0 ? "\(count)" : nil
        case .scenarios:
            let count = scenariosCount
            return count > 0 ? "\(count)" : nil
        }
    }

    private var dialogExamplesCount: Int {
        // Count actual dialog examples from the knowledge file (JSONL = one entry per line)
        if let dialogFile = character.knowledgeFiles.first(where: { $0.fileName == "dialog_examples.jsonl" }) {
            return dialogFile.content.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count
        }
        return 0
    }

    private var scenariosCount: Int {
        // Count actual scenarios from the knowledge file (JSONL = one entry per line)
        if let scenarioFile = character.knowledgeFiles.first(where: { $0.fileName == "scenarios.jsonl" }) {
            return scenarioFile.content.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count
        }
        return 0
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .persona:
            PersonaTabView(
                character: character,
                onSectionSelected: { section in
                    // Could scroll to section or show knowledge for it
                }
            )

        case .knowledge:
            KnowledgeSourcesPanel(
                character: character,
                repository: repository,
                apiKeyManager: apiKeyManager,
                onSourceAdded: { onCharacterUpdated(character) },
                onCharacterUpdated: onCharacterUpdated
            )

        case .dialogExamples:
            DialogExamplesView(
                character: character,
                repository: repository,
                apiKeyManager: apiKeyManager
            )

        case .scenarios:
            ScenarioGeneratorView(
                character: character,
                repository: repository,
                apiKeyManager: apiKeyManager
            )
        }
    }

    private func wordCount(_ text: String) -> Int {
        text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count
    }
}

// MARK: - Quick Stat

struct QuickStat: View {
    let icon: String
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: DesignSystem.Spacing.xxs) {
            HStack(spacing: DesignSystem.Spacing.xs) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.headline.monospacedDigit())
            }
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}

// MARK: - Dashboard Tab Button

struct DashboardTabButton: View {
    let tab: DashboardTab
    let isSelected: Bool
    let badge: String?
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: DesignSystem.Spacing.sm) {
                Image(systemName: tab.icon)
                    .font(.subheadline)

                Text(tab.rawValue)
                    .font(.subheadline.weight(isSelected ? .semibold : .regular))

                if let badge = badge {
                    Text(badge)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.2))
                        .foregroundStyle(isSelected ? .white : .secondary)
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, DesignSystem.Spacing.md)
            .padding(.vertical, DesignSystem.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                    .fill(isSelected ? Color.accentColor.opacity(0.1) : (isHovered ? Color.primary.opacity(0.05) : Color.clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                    .stroke(isSelected ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? .primary : .secondary)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Persona Tab View

struct PersonaTabView: View {
    let character: Character
    let onSectionSelected: (String) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
                // Parse sections from markdown
                ForEach(parsedSections, id: \.title) { section in
                    PersonaSectionCard(
                        section: section,
                        knowledgeSources: character.sectionsWithKnowledge[section.title] ?? [],
                        onTap: { onSectionSelected(section.title) }
                    )
                }
            }
            .padding(DesignSystem.Spacing.lg)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var parsedSections: [PersonaSection] {
        parseMarkdownSections(character.markdownContent)
    }

    private func parseMarkdownSections(_ markdown: String) -> [PersonaSection] {
        var sections: [PersonaSection] = []

        let pattern = "##\\s*([^\\n]+)\\n([\\s\\S]*?)(?=\\n##|\\z)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return sections
        }

        let nsString = markdown as NSString
        let matches = regex.matches(in: markdown, range: NSRange(location: 0, length: nsString.length))

        for match in matches {
            if match.numberOfRanges >= 3 {
                let titleRange = match.range(at: 1)
                let contentRange = match.range(at: 2)

                let title = nsString.substring(with: titleRange).trimmingCharacters(in: .whitespaces)
                let content = nsString.substring(with: contentRange).trimmingCharacters(in: .whitespacesAndNewlines)

                sections.append(PersonaSection(title: title, content: content))
            }
        }

        return sections
    }
}

struct PersonaSection {
    let title: String
    let content: String
}

// MARK: - Persona Section Card

struct PersonaSectionCard: View {
    let section: PersonaSection
    let knowledgeSources: [KnowledgeSource]
    let onTap: () -> Void

    @State private var isExpanded = false
    @State private var showingKnowledge = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            Button {
                withAnimation(DesignSystem.Animation.quick) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Text(section.title)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Spacer()

                    // Knowledge indicator
                    if !knowledgeSources.isEmpty {
                        Button {
                            showingKnowledge.toggle()
                        } label: {
                            HStack(spacing: DesignSystem.Spacing.xs) {
                                Image(systemName: "brain.head.profile")
                                    .font(.caption)
                                Text("\(knowledgeSources.count) sources")
                                    .font(.caption)
                            }
                            .padding(.horizontal, DesignSystem.Spacing.sm)
                            .padding(.vertical, DesignSystem.Spacing.xs)
                            .background(Color.purple.opacity(0.1))
                            .foregroundStyle(.purple)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(DesignSystem.Spacing.md)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Content (collapsible)
            if isExpanded {
                Divider()

                Text(section.content)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .padding(DesignSystem.Spacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Knowledge popover
            if showingKnowledge && !knowledgeSources.isEmpty {
                Divider()

                VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                    Text("Knowledge Sources")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    ForEach(knowledgeSources) { source in
                        HStack(spacing: DesignSystem.Spacing.sm) {
                            Image(systemName: source.sourceType.icon)
                                .font(.caption)
                                .foregroundStyle(.blue)

                            Text(source.title)
                                .font(.caption)
                                .lineLimit(1)

                            Spacer()

                            Text("\(source.entryCount) entries")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .padding(DesignSystem.Spacing.md)
                .background(Color.purple.opacity(0.05))
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
    }
}

