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

            // 4-column horizontal layout
            ScrollView(.horizontal, showsIndicators: true) {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(Array(viewModel.currentTest.variants.enumerated()), id: \.element.id) { index, variant in
                        ChatVariantColumn(
                            variant: variant,
                            variantIndex: index,
                            diffResult: index > 0 ? diffResults[index] : nil,
                            onSystemPromptChange: { viewModel.updateVariantSystemPrompt(index, systemPrompt: $0) },
                            onLabelChange: { viewModel.updateVariantLabel(index, label: $0) }
                        )
                        .frame(width: 400)
                    }
                }
                .padding(16)
            }
            .frame(maxHeight: .infinity)

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

// MARK: - Chat Variant Column
struct ChatVariantColumn: View {
    let variant: ChatVariant
    let variantIndex: Int
    let diffResult: DiffResult?
    let onSystemPromptChange: (String) -> Void
    let onLabelChange: (String) -> Void

    @State private var mode: Mode = .chat // Default to chat mode

    enum Mode {
        case edit
        case chat
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                HStack {
                    TextField("Variant Label", text: Binding(
                        get: { variant.label },
                        set: { onLabelChange($0) }
                    ))
                    .textFieldStyle(.plain)
                    .font(.headline.bold())

                    Spacer()

                    // Mode toggle
                    Picker("", selection: $mode) {
                        Text("Edit").tag(Mode.edit)
                        Text("Chat").tag(Mode.chat)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 120)
                }

                if let error = variant.error {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.caption)

                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .lineLimit(2)
                    }
                }
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // Content based on mode
            if mode == .edit {
                // Edit mode - show system prompt editor
                VStack(spacing: 0) {
                    HStack {
                        Text("System Prompt")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(variant.systemPrompt.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count) words")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(8)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))

                    TextEditor(text: Binding(
                        get: { variant.systemPrompt },
                        set: { onSystemPromptChange($0) }
                    ))
                    .font(.system(.caption, design: .monospaced))
                    .padding(8)
                    .frame(maxHeight: .infinity)
                }
            } else {
                // Chat mode - show messages
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(variant.messages.filter { $0.role != .system }) { message in
                            MessageBubble(message: message)
                        }

                        // Diff highlighting for latest assistant message
                        if let diff = diffResult, variantIndex > 0 {
                            DiffView(diffResult: diff)
                                .padding(.top, 8)
                        }

                        // Loading indicator
                        if variant.isExecuting {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Generating...")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding()
                        }
                    }
                    .padding(12)
                }
                .frame(maxHeight: .infinity)
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }
}
