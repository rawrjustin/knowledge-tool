import SwiftUI

struct PersonaTestReportView: View {
    let evaluation: PersonaTestEvaluation
    let conversation: [ConversationTurn]
    let testGoal: String
    let characterName: String
    let onRunAgain: () -> Void
    let onNewTest: () -> Void

    @State private var showConversation = false

    var body: some View {
        VStack(spacing: DesignSystem.Spacing.xl) {
            // Score cards
            scoreCardsSection

            // Summary
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                Text("Summary")
                    .font(.headline)
                Text(evaluation.summary)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle()

            // Strengths
            if !evaluation.strengths.isEmpty {
                detailSection(title: "Strengths", icon: "checkmark.circle.fill", color: DesignSystem.Colors.success, items: evaluation.strengths)
            }

            // Weaknesses
            if !evaluation.weaknesses.isEmpty {
                detailSection(title: "Weaknesses", icon: "xmark.circle.fill", color: DesignSystem.Colors.error, items: evaluation.weaknesses)
            }

            // Recommendations
            if !evaluation.recommendations.isEmpty {
                detailSection(title: "Recommendations", icon: "lightbulb.fill", color: DesignSystem.Colors.info, items: evaluation.recommendations)
            }

            // Full conversation toggle
            DisclosureGroup("Full Conversation (\(conversation.count) turns)", isExpanded: $showConversation) {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                    ForEach(conversation) { turn in
                        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                            Text("Turn \(turn.turnNumber)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)

                            HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
                                Text("User:")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 50, alignment: .leading)
                                Text(turn.userMessage)
                                    .font(.callout)
                            }

                            HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
                                Text("\(characterName):")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 50, alignment: .leading)
                                Text(turn.personaResponse)
                                    .font(.callout)
                            }
                        }
                        .padding(DesignSystem.Spacing.sm)
                        .subtleCardStyle()

                        if turn.turnNumber < conversation.count {
                            Divider()
                        }
                    }
                }
                .padding(.top, DesignSystem.Spacing.sm)
            }
            .cardStyle()

            // Actions
            HStack(spacing: DesignSystem.Spacing.md) {
                Button {
                    onRunAgain()
                } label: {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text("Run Again")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(ModernPrimaryButtonStyle())

                Button {
                    onNewTest()
                } label: {
                    HStack {
                        Image(systemName: "plus")
                        Text("New Test")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(ModernSecondaryButtonStyle())
            }
        }
    }

    // MARK: - Score Cards

    @ViewBuilder
    private var scoreCardsSection: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: DesignSystem.Spacing.md) {
            scoreCard(label: "Overall", score: evaluation.overallScore, isLarge: true)
            scoreCard(label: "Goal", score: evaluation.goalAchievement)
            scoreCard(label: "Character", score: evaluation.characterConsistency)
            scoreCard(label: "Quality", score: evaluation.conversationQuality)
        }
    }

    @ViewBuilder
    private func scoreCard(label: String, score: Int, isLarge: Bool = false) -> some View {
        VStack(spacing: DesignSystem.Spacing.xs) {
            Text("\(score)")
                .font(isLarge ? .system(size: 36, weight: .bold, design: .rounded) : .system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(scoreColor(score))

            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)

            // Score bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.primary.opacity(0.08))
                        .frame(height: 4)

                    RoundedRectangle(cornerRadius: 2)
                        .fill(scoreColor(score))
                        .frame(width: geo.size.width * CGFloat(score) / 10.0, height: 4)
                }
            }
            .frame(height: 4)
        }
        .padding(DesignSystem.Spacing.md)
        .cardStyle()
    }

    private func scoreColor(_ score: Int) -> Color {
        switch score {
        case 1...3: return DesignSystem.Colors.error
        case 4...6: return DesignSystem.Colors.warning
        default: return DesignSystem.Colors.success
        }
    }

    // MARK: - Detail Section

    @ViewBuilder
    private func detailSection(title: String, icon: String, color: Color, items: [String]) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                ForEach(items, id: \.self) { item in
                    HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
                        Circle()
                            .fill(color)
                            .frame(width: 6, height: 6)
                            .padding(.top, 6)
                        Text(item)
                            .font(.body)
                    }
                }
            }
            .padding(.top, DesignSystem.Spacing.sm)
        } label: {
            HStack(spacing: DesignSystem.Spacing.sm) {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Text(title)
                    .font(.headline)
            }
        }
        .cardStyle()
    }
}
