import SwiftUI

// MARK: - Mode Enum
enum PromptTestingMode {
    case edit
    case chat
}

// MARK: - Section Enum
enum PromptTestingSection: String, CaseIterable {
    case variants = "Variant Testing"
    case systemPrompts = "System Prompts"
}

struct PromptTestingView: View {
    let character: Character

    @State private var viewModel: PromptTestingViewModel
    @State private var systemPromptEditorViewModel: SystemPromptEditorViewModel?
    @State private var userInput: String = ""
    @State private var mode: PromptTestingMode = .edit
    @State private var selectedSection: PromptTestingSection = .variants
    @State private var systemPromptDiffs: [Int: DiffResult] = [:]
    @State private var responseDiffs: [Int: DiffResult] = [:]

    init(character: Character, apiKeyManager: APIKeyManager) {
        self.character = character
        self._viewModel = State(initialValue: PromptTestingViewModel(character: character, apiKeyManager: apiKeyManager))

        // Initialize system prompt editor
        self._systemPromptEditorViewModel = State(initialValue: SystemPromptEditorViewModel())
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header with section toggle
            headerView

            Divider()

            // Content based on selected section
            if selectedSection == .variants {
                variantTestingContent
            } else {
                if let editorViewModel = systemPromptEditorViewModel {
                    SystemPromptEditorView(viewModel: editorViewModel)
                } else {
                    Text("Loading...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .onChange(of: viewModel.currentTest.variants.count) {
            updateSystemPromptDiffs()
        }
    }

    // MARK: - Variant Testing Content
    private var variantTestingContent: some View {
        VStack(spacing: 0) {
            // Mode toggle for variants
            HStack {
                Spacer()

                Picker("", selection: $mode) {
                    Label("Edit", systemImage: "pencil")
                        .tag(PromptTestingMode.edit)
                    Label("Chat", systemImage: "bubble.left.and.bubble.right")
                        .tag(PromptTestingMode.chat)
                }
                .pickerStyle(.segmented)
                .frame(width: 180)

                Spacer()

                Button {
                    viewModel.resetTest(for: character)
                    systemPromptDiffs = [:]
                    responseDiffs = [:]
                } label: {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))

            // Variants area
            ScrollView(.horizontal, showsIndicators: true) {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(Array(viewModel.currentTest.variants.enumerated()), id: \.element.id) { index, variant in
                        VariantColumn(
                            variant: variant,
                            variantIndex: index,
                            mode: mode,
                            systemPromptDiff: index > 0 ? systemPromptDiffs[index] : nil,
                            responseDiff: index > 0 ? responseDiffs[index] : nil,
                            onSystemPromptChange: { newPrompt in
                                viewModel.updateVariantSystemPrompt(index, systemPrompt: newPrompt)
                                updateSystemPromptDiffs()
                            },
                            onLabelChange: { viewModel.updateVariantLabel(index, label: $0) },
                            onRemove: index > 0 ? { viewModel.removeVariant(at: index) } : nil
                        )
                        .frame(width: 400)
                    }

                    // Add Variant button
                    if viewModel.currentTest.canAddVariant {
                        addVariantButton
                    }
                }
                .padding(16)
            }
            .frame(maxHeight: .infinity)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))

            // Input area (only in chat mode)
            if mode == .chat {
                Divider()
                inputArea
            }
        }
    }

    // MARK: - Header View
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Prompt Testing")
                    .font(.headline)

                Text(selectedSection == .variants ? "Compare system prompt variations" : "Edit ASP, CSP, RSP templates")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Section toggle
            Picker("", selection: $selectedSection) {
                ForEach(PromptTestingSection.allCases, id: \.self) { section in
                    Text(section.rawValue).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 280)
        }
        .padding()
        .background(.regularMaterial)
    }

    // MARK: - Add Variant Button
    private var addVariantButton: some View {
        Button {
            viewModel.addVariant()
        } label: {
            VStack(spacing: 12) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.blue)

                Text("Add Variant")
                    .font(.headline)

                Text(viewModel.currentTest.nextVariantLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 400)
            .frame(maxHeight: .infinity)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8]))
                    .foregroundStyle(.tertiary)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Input Area
    private var inputArea: some View {
        HStack(spacing: 12) {
            TextField("Type a message to test all variants...", text: $userInput)
                .textFieldStyle(.plain)
                .padding(10)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(.tertiary.opacity(0.5), lineWidth: 0.5)
                )
                .disabled(viewModel.isExecuting)
                .onSubmit {
                    if !userInput.isEmpty && !viewModel.isExecuting {
                        sendMessage()
                    }
                }

            Button {
                sendMessage()
            } label: {
                if viewModel.isExecuting {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 24, height: 24)
                } else {
                    Image(systemName: "paperplane.fill")
                        .symbolRenderingMode(.hierarchical)
                        .font(.system(size: 24))
                        .foregroundStyle(userInput.isEmpty || viewModel.isExecuting ? .gray : .blue)
                }
            }
            .buttonStyle(.plain)
            .disabled(userInput.isEmpty || viewModel.isExecuting)
        }
        .padding()
        .background(.bar)
    }

    // MARK: - Actions
    private func sendMessage() {
        let message = userInput
        userInput = ""

        Task {
            await viewModel.sendMessage(message)

            // Update response diffs after execution
            for index in 1..<viewModel.currentTest.variants.count {
                responseDiffs[index] = await viewModel.getDiff(forVariantIndex: index)
            }
        }
    }

    private func updateSystemPromptDiffs() {
        Task {
            for index in 1..<viewModel.currentTest.variants.count {
                systemPromptDiffs[index] = await viewModel.getSystemPromptDiff(forVariantIndex: index)
            }
        }
    }
}

// MARK: - Variant Column
struct VariantColumn: View {
    let variant: ChatVariant
    let variantIndex: Int
    let mode: PromptTestingMode
    let systemPromptDiff: DiffResult?
    let responseDiff: DiffResult?
    let onSystemPromptChange: (String) -> Void
    let onLabelChange: (String) -> Void
    let onRemove: (() -> Void)?

    @State private var showingDiffPopover = false
    @State private var localSystemPrompt: String = ""
    @State private var localLabel: String = ""
    @State private var isInitialized = false

    // Check if there are actual changes in the diff
    private var hasChanges: Bool {
        guard let diff = systemPromptDiff else { return false }
        return diff.segments.contains { $0.type != .unchanged }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                HStack {
                    TextField("Label", text: $localLabel)
                        .textFieldStyle(.plain)
                        .font(.headline)
                        .onChange(of: localLabel) { _, newValue in
                            if isInitialized {
                                onLabelChange(newValue)
                            }
                        }

                    Spacer()

                    // Show diff button for variants B, C, D in edit mode
                    if mode == .edit && variantIndex > 0 && hasChanges {
                        Button {
                            showingDiffPopover.toggle()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.left.arrow.right")
                                Text("Changes")
                            }
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.blue.opacity(0.1))
                            .foregroundStyle(.blue)
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: $showingDiffPopover, arrowEdge: .bottom) {
                            if let diff = systemPromptDiff {
                                SystemPromptDiffPopover(diffResult: diff)
                            }
                        }
                    }

                    if let onRemove = onRemove {
                        Button {
                            onRemove()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Remove variant")
                    }
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
            .background(.regularMaterial)

            Divider()

            // Content based on mode
            if mode == .edit {
                editModeContent
            } else {
                chatModeContent
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(.tertiary.opacity(0.3), lineWidth: 0.5)
        )
        .onAppear {
            // Initialize local state from variant
            localSystemPrompt = variant.systemPrompt
            localLabel = variant.label
            // Use Task to set initialized flag after the view has fully appeared
            Task { @MainActor in
                isInitialized = true
            }
        }
        .onChange(of: variant.id) {
            // When variant changes (e.g., reset), sync local state
            localSystemPrompt = variant.systemPrompt
            localLabel = variant.label
        }
    }

    // MARK: - Edit Mode Content
    private var editModeContent: some View {
        VStack(spacing: 0) {
            // System prompt header
            HStack {
                Text("System Prompt")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(localSystemPrompt.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count) words")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(8)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))

            // System prompt editor - full height
            TextEditor(text: $localSystemPrompt)
                .font(.system(.caption, design: .monospaced))
                .scrollContentBackground(.hidden)
                .background(Color(nsColor: .textBackgroundColor))
                .padding(8)
                .frame(maxHeight: .infinity)
                .onChange(of: localSystemPrompt) { _, newValue in
                    if isInitialized {
                        onSystemPromptChange(newValue)
                    }
                }
        }
    }

    // MARK: - Chat Mode Content
    private var chatModeContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(variant.messages.filter { $0.role != .system }) { message in
                    MessageBubble(message: message)
                }

                // Response diff highlighting for variants B, C, D
                if let diff = responseDiff, variantIndex > 0 {
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
        .background(Color(nsColor: .textBackgroundColor))
    }
}

// MARK: - System Prompt Diff Popover
struct SystemPromptDiffPopover: View {
    let diffResult: DiffResult

    private var changedSegments: [DiffSegment] {
        diffResult.segments.filter { $0.type != .unchanged }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "arrow.left.arrow.right")
                    .foregroundStyle(.blue)

                Text("Changes from Variant A")
                    .font(.headline)

                Spacer()

                // Summary badges
                HStack(spacing: 8) {
                    let added = diffResult.segments.filter { $0.type == .added }.count
                    let removed = diffResult.segments.filter { $0.type == .removed }.count

                    if added > 0 {
                        Label("\(added)", systemImage: "plus")
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.2))
                            .foregroundStyle(.green)
                            .cornerRadius(4)
                    }

                    if removed > 0 {
                        Label("\(removed)", systemImage: "minus")
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.red.opacity(0.2))
                            .foregroundStyle(.red)
                            .cornerRadius(4)
                    }
                }
            }
            .padding(.bottom, 4)

            Divider()

            // Diff content
            if changedSegments.isEmpty {
                Text("No changes")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(changedSegments) { segment in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: iconForType(segment.type))
                                    .font(.caption)
                                    .foregroundStyle(colorForType(segment.type))
                                    .frame(width: 16)

                                Text(segment.text)
                                    .font(.system(.body, design: .monospaced))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(backgroundColorForType(segment.type))
                                    .cornerRadius(4)
                            }
                        }
                    }
                }
                .frame(maxHeight: 300)
            }
        }
        .padding()
        .frame(width: 450)
    }

    private func iconForType(_ type: DiffType) -> String {
        switch type {
        case .added: return "plus.circle.fill"
        case .removed: return "minus.circle.fill"
        case .modified: return "arrow.left.arrow.right.circle.fill"
        case .unchanged: return ""
        }
    }

    private func colorForType(_ type: DiffType) -> Color {
        switch type {
        case .added: return .green
        case .removed: return .red
        case .modified: return .orange
        case .unchanged: return .clear
        }
    }

    private func backgroundColorForType(_ type: DiffType) -> Color {
        switch type {
        case .added: return .green.opacity(0.1)
        case .removed: return .red.opacity(0.1)
        case .modified: return .orange.opacity(0.1)
        case .unchanged: return .clear
        }
    }
}

#Preview {
    PromptTestingView(
        character: Character(
            name: "Test",
            directoryPath: "",
            personaFileName: "",
            markdownContent: "You are a helpful assistant.",
            knowledgeFiles: [],
            sha: "",
            systemPromptType: .conversational,
            lastModified: Date(),
            isLocalOnly: true
        ),
        apiKeyManager: APIKeyManager()
    )
    .frame(width: 900, height: 700)
}
