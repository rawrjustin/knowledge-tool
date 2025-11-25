import SwiftUI

struct PromptTestingView: View {
    let character: Character
    @State private var viewModel: PromptTestingViewModel
    @State private var userInput: String = ""
    @State private var diffResults: [Int: DiffResult] = [:]

    init(character: Character, apiKeyManager: APIKeyManager) {
        self.character = character
        self._viewModel = State(initialValue: PromptTestingViewModel(character: character, apiKeyManager: apiKeyManager))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Prompt Testing")
                        .font(.title2.bold())

                    Text("Test different system prompt variations for \(character.name)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    viewModel.resetTest(for: character)
                    diffResults = [:]
                } label: {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.bordered)
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // 4-variant grid
            GeometryReader { geometry in
                let gridWidth = (geometry.size.width - 32 - 12) / 2 // 2 columns with padding and gap

                ScrollView {
                    VStack(spacing: 12) {
                        // Row 1: Variants A & B
                        HStack(spacing: 12) {
                            ChatVariantView(
                                variant: viewModel.currentTest.variants[0],
                                variantIndex: 0,
                                diffResult: nil, // Variant A is the baseline
                                onSystemPromptChange: { viewModel.updateVariantSystemPrompt(0, systemPrompt: $0) },
                                onLabelChange: { viewModel.updateVariantLabel(0, label: $0) }
                            )
                            .frame(width: gridWidth)

                            ChatVariantView(
                                variant: viewModel.currentTest.variants[1],
                                variantIndex: 1,
                                diffResult: diffResults[1],
                                onSystemPromptChange: { viewModel.updateVariantSystemPrompt(1, systemPrompt: $0) },
                                onLabelChange: { viewModel.updateVariantLabel(1, label: $0) }
                            )
                            .frame(width: gridWidth)
                        }

                        // Row 2: Variants C & D
                        HStack(spacing: 12) {
                            ChatVariantView(
                                variant: viewModel.currentTest.variants[2],
                                variantIndex: 2,
                                diffResult: diffResults[2],
                                onSystemPromptChange: { viewModel.updateVariantSystemPrompt(2, systemPrompt: $0) },
                                onLabelChange: { viewModel.updateVariantLabel(2, label: $0) }
                            )
                            .frame(width: gridWidth)

                            ChatVariantView(
                                variant: viewModel.currentTest.variants[3],
                                variantIndex: 3,
                                diffResult: diffResults[3],
                                onSystemPromptChange: { viewModel.updateVariantSystemPrompt(3, systemPrompt: $0) },
                                onLabelChange: { viewModel.updateVariantLabel(3, label: $0) }
                            )
                            .frame(width: gridWidth)
                        }
                    }
                    .padding(16)
                }
            }

            Divider()

            // Input area
            HStack(spacing: 12) {
                TextField("Type a message to test all variants...", text: $userInput, axis: .vertical)
                    .textFieldStyle(.plain)
                    .padding(12)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(8)
                    .lineLimit(1...3)
                    .disabled(viewModel.isExecuting)

                Button {
                    sendMessage()
                } label: {
                    if viewModel.isExecuting {
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(width: 24, height: 24)
                    } else {
                        Image(systemName: "paperplane.fill")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(userInput.isEmpty || viewModel.isExecuting)
                .keyboardShortcut(.return, modifiers: .command)
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))
        }
    }

    private func sendMessage() {
        let message = userInput
        userInput = ""

        Task {
            await viewModel.sendMessage(message)

            // Update diff results after execution
            for index in 1...3 {
                diffResults[index] = await viewModel.getDiff(forVariantIndex: index)
            }
        }
    }
}
