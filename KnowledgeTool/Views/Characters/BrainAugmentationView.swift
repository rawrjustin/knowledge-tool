import SwiftUI

struct BrainAugmentationView: View {
    @State private var viewModel: AugmentationViewModel
    let onComplete: (Character) -> Void
    let onCancel: () -> Void

    init(
        character: Character,
        repository: CombinedCharacterRepository,
        apiKeyManager: APIKeyManager,
        onComplete: @escaping (Character) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self._viewModel = State(initialValue: AugmentationViewModel(
            character: character,
            repository: repository,
            apiKeyManager: apiKeyManager
        ))
        self.onComplete = onComplete
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header

            Divider()

            if viewModel.hasResults {
                // Results view
                resultsView
            } else {
                // Input view
                inputView
            }
        }
        .frame(minWidth: 700, minHeight: 600)
        .sheet(isPresented: $viewModel.showingPreview) {
            PreviewSheet(
                originalContent: "",
                previewContent: viewModel.previewContent,
                onDismiss: { viewModel.showingPreview = false }
            )
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxs) {
                Text("Augment Brain")
                    .font(.title3.weight(.semibold))

                if viewModel.hasResults {
                    Text("\(viewModel.selectedAugmentationsCount) persona updates, \(viewModel.selectedRAGEntriesCount) knowledge entries")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Add source content to enhance the persona")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Actions
            HStack(spacing: DesignSystem.Spacing.sm) {
                if viewModel.hasResults {
                    Button("Start Over") {
                        viewModel.reset()
                    }
                    .buttonStyle(.bordered)

                    Button {
                        viewModel.showPreview()
                    } label: {
                        Label("Preview", systemImage: "eye")
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.selectedAugmentationsCount == 0)

                    Button {
                        Task {
                            if let updatedCharacter = await viewModel.applyChanges() {
                                onComplete(updatedCharacter)
                            }
                        }
                    } label: {
                        Label("Apply Changes", systemImage: "checkmark.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.selectedAugmentationsCount == 0 && viewModel.selectedRAGEntriesCount == 0)
                } else {
                    Button("Cancel") {
                        onCancel()
                    }
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.cancelAction)
                }
            }
        }
        .padding(DesignSystem.Spacing.lg)
    }

    // MARK: - Input View

    private var inputView: some View {
        VStack(spacing: DesignSystem.Spacing.xl) {
            // Source type selector
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                Text("Source Type")
                    .font(.headline)

                Picker("Source Type", selection: $viewModel.sourceType) {
                    ForEach(AugmentationSourceType.allCases, id: \.self) { type in
                        Label(type.displayName, systemImage: type.icon)
                            .tag(type)
                    }
                }
                .pickerStyle(.segmented)
            }
            .padding(.horizontal, DesignSystem.Spacing.lg)
            .padding(.top, DesignSystem.Spacing.lg)

            // Source label (for text input)
            if viewModel.sourceType == .text {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                    Text("Source Label")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)

                    TextField("e.g., Interview 2024, Podcast Episode, Article", text: $viewModel.sourceLabel)
                        .textFieldStyle(.roundedBorder)
                }
                .padding(.horizontal, DesignSystem.Spacing.lg)
            }

            // Input field
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                HStack {
                    Text(viewModel.sourceType == .text ? "Content" : "URL")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)

                    Spacer()

                    if let validation = viewModel.inputValidationMessage {
                        Text(validation)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                if viewModel.sourceType == .text {
                    TextEditor(text: $viewModel.sourceInput)
                        .font(.body)
                        .scrollContentBackground(.hidden)
                        .background(Color(nsColor: .textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
                        .overlay(
                            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                        )
                        .frame(minHeight: 200)
                        .overlay(alignment: .topLeading) {
                            if viewModel.sourceInput.isEmpty {
                                Text(viewModel.inputPlaceholder)
                                    .font(.body)
                                    .foregroundStyle(.tertiary)
                                    .padding(8)
                                    .allowsHitTesting(false)
                            }
                        }
                } else {
                    TextField(viewModel.inputPlaceholder, text: $viewModel.sourceInput)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                }
            }
            .padding(.horizontal, DesignSystem.Spacing.lg)

            // Error display
            if let error = viewModel.error {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                    Spacer()
                    Button("Dismiss") {
                        viewModel.error = nil
                    }
                    .font(.caption)
                }
                .padding(DesignSystem.Spacing.md)
                .background(Color.red.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
                .padding(.horizontal, DesignSystem.Spacing.lg)
            }

            // Progress
            if viewModel.isProcessing {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text(viewModel.progressMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(DesignSystem.Spacing.md)
            }

            Spacer()

            // Process button
            HStack {
                Spacer()

                Button {
                    Task {
                        await viewModel.processSource()
                    }
                } label: {
                    HStack {
                        Image(systemName: "sparkles")
                        Text("Analyze & Extract")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!viewModel.canSubmit || viewModel.isProcessing)
            }
            .padding(DesignSystem.Spacing.lg)
        }
    }

    // MARK: - Results View

    private var resultsView: some View {
        HSplitView {
            // Left: Augmentation list
            augmentationList
                .frame(minWidth: 350)

            // Right: Details/Preview
            detailsPanel
        }
    }

    private var augmentationList: some View {
        VStack(spacing: 0) {
            // Summary header
            if let result = viewModel.analysisResult {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                    HStack {
                        Image(systemName: result.sourceType.icon)
                            .foregroundStyle(.blue)
                        Text(result.sourceTitle)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                    }

                    Text(result.sourceSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)

                    Divider()

                    // Selection controls
                    HStack {
                        Text("Persona Updates")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        Spacer()

                        Button("Select All") {
                            viewModel.selectAllAugmentations()
                        }
                        .font(.caption)
                        .buttonStyle(.borderless)

                        Button("Deselect All") {
                            viewModel.deselectAllAugmentations()
                        }
                        .font(.caption)
                        .buttonStyle(.borderless)
                    }
                }
                .padding(DesignSystem.Spacing.md)
                .background(Color(nsColor: .controlBackgroundColor))
            }

            Divider()

            // Augmentation items
            if viewModel.augmentations.isEmpty {
                VStack(spacing: DesignSystem.Spacing.md) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)
                    Text("No persona-relevant content found")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("The source content didn't contain information suitable for direct persona augmentation.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                List {
                    ForEach(viewModel.augmentations) { augmentation in
                        AugmentationRow(
                            augmentation: augmentation,
                            onToggle: { viewModel.toggleAugmentation(augmentation) }
                        )
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }

            // RAG entries summary
            if let result = viewModel.analysisResult, !result.ragEntries.isEmpty {
                Divider()

                HStack {
                    Image(systemName: "brain.head.profile")
                        .foregroundStyle(.purple)
                    Text("\(result.ragEntries.count) knowledge entries")
                        .font(.caption)
                    Text("will be added to RAG")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(DesignSystem.Spacing.md)
                .background(Color.purple.opacity(0.05))
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var detailsPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Preview Changes")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(DesignSystem.Spacing.md)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // Selected augmentations preview
            if viewModel.selectedAugmentationsCount > 0 {
                ScrollView {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
                        ForEach(viewModel.augmentations.filter { $0.isSelected }) { augmentation in
                            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                                HStack {
                                    Text(augmentation.section)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.blue)

                                    Spacer()

                                    Text("\(Int(augmentation.confidence * 100))% confidence")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }

                                Text(augmentation.suggestedAddition)
                                    .font(.callout)
                                    .textSelection(.enabled)

                                Text("Source: \"\(augmentation.sourceExcerpt.prefix(100))...\"")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                    .italic()
                            }
                            .padding(DesignSystem.Spacing.md)
                            .background(Color(nsColor: .textBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
                        }
                    }
                    .padding(DesignSystem.Spacing.md)
                }
            } else {
                VStack(spacing: DesignSystem.Spacing.md) {
                    Image(systemName: "square.dashed")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)
                    Text("Select items to preview")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
}

// MARK: - Augmentation Row

struct AugmentationRow: View {
    let augmentation: PersonaAugmentation
    let onToggle: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
            // Checkbox
            Button {
                onToggle()
            } label: {
                Image(systemName: augmentation.isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(augmentation.isSelected ? .blue : .secondary)
                    .font(.title3)
            }
            .buttonStyle(.plain)

            // Content
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                HStack {
                    Text(augmentation.section)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.blue)

                    Spacer()

                    // Confidence indicator
                    ConfidenceIndicator(confidence: augmentation.confidence)
                }

                Text(augmentation.suggestedAddition)
                    .font(.callout)
                    .lineLimit(3)
                    .foregroundStyle(augmentation.isSelected ? .primary : .secondary)

                Text(augmentation.rationale)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, DesignSystem.Spacing.xs)
        .contentShape(Rectangle())
        .onTapGesture {
            onToggle()
        }
    }
}

// MARK: - Confidence Indicator

struct ConfidenceIndicator: View {
    let confidence: Double

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(index < confidenceLevel ? color : Color.gray.opacity(0.3))
                    .frame(width: 6, height: 6)
            }
        }
        .help("\(Int(confidence * 100))% confidence")
    }

    private var confidenceLevel: Int {
        if confidence >= 0.85 { return 3 }
        if confidence >= 0.7 { return 2 }
        return 1
    }

    private var color: Color {
        if confidence >= 0.85 { return .green }
        if confidence >= 0.7 { return .orange }
        return .red
    }
}

// MARK: - Preview Sheet

struct PreviewSheet: View {
    let originalContent: String
    let previewContent: String
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Preview Updated Persona")
                    .font(.title3.weight(.semibold))

                Spacer()

                Button("Done") {
                    onDismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding(DesignSystem.Spacing.lg)
            .background(.regularMaterial)

            Divider()

            // Content
            ScrollView {
                Text(previewContent)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(DesignSystem.Spacing.lg)
            }
            .background(Color(nsColor: .textBackgroundColor))
        }
        .frame(width: 700, height: 600)
    }
}
