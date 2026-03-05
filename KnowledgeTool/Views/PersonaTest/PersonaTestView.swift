import SwiftUI

struct PersonaTestView: View {
    let character: Character
    let repository: CombinedCharacterRepository
    let apiKeyManager: APIKeyManager

    @State private var viewModel: PersonaTestViewModel

    init(character: Character, repository: CombinedCharacterRepository, apiKeyManager: APIKeyManager) {
        self.character = character
        self.repository = repository
        self.apiKeyManager = apiKeyManager
        self._viewModel = State(initialValue: PersonaTestViewModel(
            character: character,
            repository: repository,
            apiKeyManager: apiKeyManager
        ))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: DesignSystem.Spacing.xl) {
                // Header
                HStack {
                    SectionHeader(
                        title: "Persona Test",
                        icon: "checkmark.shield"
                    )
                    Spacer()
                    StatusBadge(text: character.name, status: .info)
                }

                switch viewModel.status {
                case .idle:
                    configForm

                case .running(let turn, let maxTurns):
                    runningView(turn: turn, maxTurns: maxTurns)

                case .evaluating:
                    evaluatingView

                case .complete:
                    if let evaluation = viewModel.evaluation {
                        PersonaTestReportView(
                            evaluation: evaluation,
                            conversation: viewModel.conversation,
                            testGoal: viewModel.testGoal,
                            characterName: character.name,
                            onRunAgain: { viewModel.runTest() },
                            onNewTest: { viewModel.resetTest() }
                        )
                    }

                case .error(let message):
                    errorView(message: message)
                }
            }
            .padding(DesignSystem.Spacing.xxl)
        }
        .task {
            await viewModel.loadPublishState()
        }
    }

    // MARK: - Config Form

    @ViewBuilder
    private var configForm: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            if !viewModel.isPublished {
                // Unpublished state
                VStack(spacing: DesignSystem.Spacing.md) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(DesignSystem.Colors.warning)

                    Text("Character Not Published")
                        .font(.headline)

                    Text("This character must be published to the Genies Chat API before running persona tests.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(DesignSystem.Spacing.xxl)
                .cardStyle()
            } else {
                // Test goal
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                    Text("Test Goal")
                        .font(.headline)

                    HelperText(
                        text: "Describe what you want to test — e.g., \"Does this persona handle emotional support for college stress well?\"",
                        icon: "lightbulb"
                    )

                    TextEditor(text: $viewModel.testGoal)
                        .font(.body)
                        .frame(minHeight: 80, maxHeight: 120)
                        .polishedInput()
                }
                .cardStyle()

                // Max turns
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                    HStack {
                        Text("Conversation Turns")
                            .font(.headline)

                        Spacer()

                        Stepper(
                            "\(viewModel.maxTurns)",
                            value: $viewModel.maxTurns,
                            in: 1...15
                        )
                        .frame(width: 120)
                    }

                    HelperText(
                        text: "Number of back-and-forth exchanges between the simulated user and the persona (1–15).",
                        icon: "arrow.triangle.2.circlepath"
                    )
                }
                .cardStyle()

                // Run button
                Button {
                    viewModel.runTest()
                } label: {
                    HStack {
                        Image(systemName: "play.fill")
                        Text("Run Test")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(ModernPrimaryButtonStyle())
                .disabled(viewModel.testGoal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    // MARK: - Running View

    @ViewBuilder
    private func runningView(turn: Int, maxTurns: Int) -> some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            // Progress
            HStack {
                Text("Turn \(turn) of \(maxTurns)")
                    .font(.headline)

                Spacer()

                Button("Cancel") {
                    viewModel.cancelTest()
                }
                .buttonStyle(ModernSecondaryButtonStyle())
            }

            ProgressView(value: Double(turn), total: Double(maxTurns))
                .tint(.accentColor)

            // Conversation turns
            conversationList

            // Typing indicator
            HStack {
                AnimatedTypingIndicator()
                Spacer()
            }
            .padding(.leading, DesignSystem.Spacing.sm)
        }
    }

    // MARK: - Evaluating View

    @ViewBuilder
    private var evaluatingView: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            conversationList

            InlineLoader(message: "Evaluating conversation...")
                .padding(.vertical, DesignSystem.Spacing.xl)
        }
    }

    // MARK: - Error View

    @ViewBuilder
    private func errorView(message: String) -> some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            if !viewModel.conversation.isEmpty {
                conversationList
            }

            VStack(spacing: DesignSystem.Spacing.md) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.largeTitle)
                    .foregroundStyle(DesignSystem.Colors.error)

                Text("Test Error")
                    .font(.headline)

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                HStack(spacing: DesignSystem.Spacing.md) {
                    Button("Retry") {
                        viewModel.runTest()
                    }
                    .buttonStyle(ModernPrimaryButtonStyle())

                    Button("Reset") {
                        viewModel.resetTest()
                    }
                    .buttonStyle(ModernSecondaryButtonStyle())
                }
            }
            .frame(maxWidth: .infinity)
            .padding(DesignSystem.Spacing.xxl)
            .cardStyle()
        }
    }

    // MARK: - Conversation List

    @ViewBuilder
    private var conversationList: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            ForEach(viewModel.conversation) { turn in
                // User message
                HStack {
                    Spacer()
                    VStack(alignment: .trailing, spacing: DesignSystem.Spacing.xxs) {
                        Text("Simulated User")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(turn.userMessage)
                            .font(.body)
                            .padding(DesignSystem.Spacing.md)
                            .background(Color.accentColor.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large))
                    }
                    .frame(maxWidth: 500, alignment: .trailing)
                }

                // Persona response
                HStack {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxs) {
                        Text(character.name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(turn.personaResponse)
                            .font(.body)
                            .padding(DesignSystem.Spacing.md)
                            .cardStyle()
                    }
                    .frame(maxWidth: 500, alignment: .leading)
                    Spacer()
                }
            }
        }
    }
}
