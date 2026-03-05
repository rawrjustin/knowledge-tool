import SwiftUI

/// View for generating and managing dialog examples for a character
struct DialogExamplesView: View {
    let character: Character
    let repository: CombinedCharacterRepository
    let apiKeyManager: APIKeyManager

    @State private var viewModel: DialogExampleViewModel

    @State private var showingExportSheet = false
    @State private var exportContent: String = ""
    @State private var copiedAll = false
    @State private var showingAddDialog = false
    @State private var newDialogCategory: String = ""
    @State private var newDialogText: String = ""

    init(character: Character, repository: CombinedCharacterRepository, apiKeyManager: APIKeyManager) {
        self.character = character
        self.repository = repository
        self.apiKeyManager = apiKeyManager
        self._viewModel = State(initialValue: DialogExampleViewModel(
            character: character,
            apiKeyManager: apiKeyManager,
            repository: repository
        ))
    }

    var body: some View {
        HSplitView {
            // Left panel: Configuration
            configurationPanel
                .frame(minWidth: 280, idealWidth: 320, maxWidth: 400)

            // Right panel: Generated examples
            examplesPanel
                .frame(minWidth: 400)
        }
        .sheet(isPresented: $showingExportSheet) {
            ExportDialogSheet(content: $exportContent)
        }
        .sheet(isPresented: $showingAddDialog) {
            AddDialogSheet(
                categories: DialogCategories.all,
                selectedCategory: $newDialogCategory,
                dialogText: $newDialogText,
                onAdd: {
                    if !newDialogText.isEmpty && !newDialogCategory.isEmpty {
                        viewModel.addExample(categoryId: newDialogCategory, dialog: newDialogText)
                    }
                    showingAddDialog = false
                    newDialogText = ""
                },
                onCancel: {
                    showingAddDialog = false
                    newDialogText = ""
                }
            )
        }
        .alert("Error", isPresented: .constant(viewModel.error != nil)) {
            Button("OK") {
                viewModel.error = nil
            }
        } message: {
            Text(viewModel.error ?? "")
        }
    }

    // MARK: - Configuration Panel

    private var configurationPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
                // Header
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                    Text("Dialog Examples")
                        .font(.title2.bold())

                    Text("Generate characteristic dialog examples that teach an LLM how \(character.name) talks")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Divider()

                // Progress indicator
                if viewModel.isGenerating {
                    HStack(spacing: DesignSystem.Spacing.sm) {
                        ProgressView()
                            .controlSize(.small)
                        Text(viewModel.progressMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(DesignSystem.Spacing.sm)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.accentColor.opacity(0.1))
                    .cornerRadius(DesignSystem.CornerRadius.small)
                }

                // Category Selection
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                    HStack {
                        Text("CATEGORIES")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        Spacer()

                        Button("All") {
                            viewModel.selectAllCategories()
                        }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(.blue)

                        Text("/")
                            .foregroundStyle(.tertiary)

                        Button("None") {
                            viewModel.deselectAllCategories()
                        }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(.blue)
                    }

                    ForEach(DialogCategories.all) { category in
                        CategorySelectionRow(
                            category: category,
                            isSelected: viewModel.selectedCategoryIds.contains(category.id),
                            existingCount: viewModel.examplesByCategory[category.id]?.count ?? 0,
                            onToggle: {
                                viewModel.toggleCategory(category.id)
                            }
                        )
                    }
                }

                Divider()

                // Generation Options
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                    Text("GENERATION OPTIONS")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Toggle(isOn: $viewModel.useTranscripts) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Extract from transcripts")
                                .font(.subheadline)
                            Text("Use video transcripts if available")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .toggleStyle(.switch)

                    Toggle(isOn: $viewModel.researchQuotes) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Research real quotes")
                                .font(.subheadline)
                            Text("Search for actual quotes (for real people)")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .toggleStyle(.switch)

                    HStack {
                        Text("Target examples:")
                            .font(.subheadline)
                        Spacer()
                        Picker("", selection: $viewModel.targetExamples) {
                            Text("30").tag(30)
                            Text("50").tag(50)
                            Text("75").tag(75)
                            Text("100").tag(100)
                        }
                        .labelsHidden()
                        .frame(width: 80)
                    }
                }

                Divider()

                // Style Guidance (optional)
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                    Text("STYLE GUIDANCE (OPTIONAL)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    TextField("Tone (e.g., casual, formal, energetic)", text: $viewModel.toneGuidance)
                        .polishedInput()
                        .font(.subheadline)

                    TextField("Style notes", text: $viewModel.styleNotes)
                        .polishedInput()
                        .font(.subheadline)
                }

                Spacer(minLength: DesignSystem.Spacing.lg)

                // Generate Button
                Button {
                    Task {
                        await viewModel.generate()
                    }
                } label: {
                    HStack {
                        if viewModel.isGenerating {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "sparkles")
                        }
                        Text(viewModel.isGenerating ? "Generating..." : "Generate Examples")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DesignSystem.Spacing.sm)
                }
                .buttonStyle(.modernPrimary)
                .disabled(viewModel.isGenerating || viewModel.selectedCategoryIds.isEmpty)
            }
            .padding(DesignSystem.Spacing.lg)
        }
        .background(.regularMaterial)
    }

    // MARK: - Examples Panel

    private var examplesPanel: some View {
        VStack(spacing: 0) {
            // Stats header
            HStack {
                Text("Total: \(viewModel.totalCount) examples")
                    .font(.headline)

                Spacer()

                // Source legend
                HStack(spacing: DesignSystem.Spacing.md) {
                    SourceLegendItem(color: .orange, label: "AI")
                    SourceLegendItem(color: .blue, label: "Researched")
                    SourceLegendItem(color: .purple, label: "Transcript")
                    SourceLegendItem(color: .green, label: "User")
                }
                .font(.caption)

                Spacer()

                if viewModel.hasExamples {
                    Button {
                        copyToPasteboard(viewModel.exportPlainText())
                        copiedAll = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            copiedAll = false
                        }
                    } label: {
                        Label(copiedAll ? "Copied" : "Copy All", systemImage: copiedAll ? "checkmark" : "doc.on.doc")
                    }
                    .buttonStyle(.modernSecondary)

                    Button {
                        exportContent = viewModel.exportPlainText()
                        showingExportSheet = true
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.modernSecondary)

                    Button(role: .destructive) {
                        viewModel.deleteAllExamples()
                    } label: {
                        Label("Clear All", systemImage: "trash")
                    }
                    .buttonStyle(.modernSecondary)
                }

                Button {
                    newDialogCategory = DialogCategories.all.first?.id ?? ""
                    showingAddDialog = true
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .buttonStyle(.modernSecondary)
            }
            .padding(DesignSystem.Spacing.md)
            .background(.regularMaterial)

            Divider()

            if viewModel.allExamples.isEmpty {
                emptyState
            } else {
                examplesList
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            Image(systemName: "text.bubble")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)

            Text("No Dialog Examples")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text("Select categories and click Generate to create dialog examples for \(character.name)")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var examplesList: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                ForEach(DialogCategories.all) { category in
                    let examples = viewModel.examplesByCategory[category.id] ?? []
                    if !examples.isEmpty {
                        Section {
                            VStack(spacing: 1) {
                                ForEach(examples) { example in
                                    CompactDialogRow(
                                        example: example,
                                        isEditing: viewModel.editingExample?.id == example.id,
                                        editedText: $viewModel.editedDialogText,
                                        onEdit: {
                                            viewModel.startEditing(example)
                                        },
                                        onSaveEdit: {
                                            viewModel.saveEditedExample()
                                        },
                                        onCancelEdit: {
                                            viewModel.cancelEditing()
                                        },
                                        onRegenerate: {
                                            Task {
                                                await viewModel.regenerateExample(example)
                                            }
                                        },
                                        onDelete: {
                                            viewModel.deleteExample(example)
                                        }
                                    )
                                }
                            }
                            .background(.regularMaterial)
                            .cornerRadius(DesignSystem.CornerRadius.medium)
                        } header: {
                            CategorySectionHeader(
                                category: category,
                                count: examples.count,
                                onAdd: {
                                    newDialogCategory = category.id
                                    showingAddDialog = true
                                }
                            )
                        }
                    }
                }
            }
            .padding(DesignSystem.Spacing.md)
        }
    }
}

// MARK: - Source Legend Item

struct SourceLegendItem: View {
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 3, height: 12)
            Text(label)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Category Selection Row

struct CategorySelectionRow: View {
    let category: DialogCategory
    let isSelected: Bool
    let existingCount: Int
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: DesignSystem.Spacing.sm) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? .blue : .secondary)

                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(category.name)
                            .font(.subheadline)
                            .foregroundStyle(.primary)

                        Text("(\(category.suggestedCount))")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }

                    Text(category.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if existingCount > 0 {
                    Text("\(existingCount)")
                        .font(.caption.monospacedDigit())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.2))
                        .foregroundStyle(.green)
                        .cornerRadius(4)
                }
            }
            .padding(.vertical, DesignSystem.Spacing.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Category Section Header

struct CategorySectionHeader: View {
    let category: DialogCategory
    let count: Int
    let onAdd: () -> Void

    var body: some View {
        HStack {
            Text(category.name.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text("\(count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)

            Spacer()

            Button(action: onAdd) {
                Image(systemName: "plus.circle")
                    .font(.caption)
                    .foregroundStyle(.blue)
            }
            .buttonStyle(.plain)
            .help("Add example to \(category.name)")
        }
        .padding(.vertical, DesignSystem.Spacing.sm)
        .padding(.horizontal, DesignSystem.Spacing.sm)
        .background(.regularMaterial)
    }
}

// MARK: - Compact Dialog Row

struct CompactDialogRow: View {
    let example: DialogExample
    let isEditing: Bool
    @Binding var editedText: String
    let onEdit: () -> Void
    let onSaveEdit: () -> Void
    let onCancelEdit: () -> Void
    let onRegenerate: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 0) {
            // Color-coded source indicator bar
            RoundedRectangle(cornerRadius: 2)
                .fill(sourceColor)
                .frame(width: 4)
                .help(example.source.displayName)

            if isEditing {
                // Edit mode
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                    TextEditor(text: $editedText)
                        .font(.body)
                        .frame(minHeight: 50, maxHeight: 100)
                        .scrollContentBackground(.hidden)
                        .background(Color(nsColor: .textBackgroundColor))
                        .cornerRadius(DesignSystem.CornerRadius.small)

                    HStack {
                        Spacer()
                        Button("Cancel", action: onCancelEdit)
                            .buttonStyle(.modernSecondary)
                            .controlSize(.small)

                        Button("Save", action: onSaveEdit)
                            .buttonStyle(.modernPrimary)
                            .controlSize(.small)
                    }
                }
                .padding(DesignSystem.Spacing.sm)
            } else {
                // Display mode
                HStack(spacing: DesignSystem.Spacing.sm) {
                    Text(example.dialog)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .lineLimit(3)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contextMenu {
                            Button {
                                copyToPasteboard(example.dialog)
                            } label: {
                                Label("Copy", systemImage: "doc.on.doc")
                            }
                        }

                    // Action buttons on hover
                    if isHovered {
                        HStack(spacing: DesignSystem.Spacing.xs) {
                            Button {
                                copyToPasteboard(example.dialog)
                            } label: {
                                Image(systemName: "doc.on.doc")
                                    .font(.caption)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .help("Copy")

                            Button(action: onEdit) {
                                Image(systemName: "pencil")
                                    .font(.caption)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .help("Edit")

                            Button(action: onRegenerate) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.caption)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .help("Regenerate")

                            Button(action: onDelete) {
                                Image(systemName: "xmark")
                                    .font(.caption)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.red.opacity(0.8))
                            .help("Delete")
                        }
                        .padding(.leading, DesignSystem.Spacing.xs)
                    }
                }
                .padding(.horizontal, DesignSystem.Spacing.sm)
                .padding(.vertical, DesignSystem.Spacing.sm)
            }
        }
        .background(isHovered && !isEditing ? Color.primary.opacity(0.03) : Color.clear)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private var sourceColor: Color {
        switch example.source {
        case .generated: return .orange
        case .researched: return .blue
        case .transcript: return .purple
        case .userCreated: return .green
        }
    }
}

// MARK: - Add Dialog Sheet

struct AddDialogSheet: View {
    let categories: [DialogCategory]
    @Binding var selectedCategory: String
    @Binding var dialogText: String
    let onAdd: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            Text("Add Dialog Example")
                .font(.headline)

            Picker("Category", selection: $selectedCategory) {
                ForEach(categories) { category in
                    Text(category.name).tag(category.id)
                }
            }
            .labelsHidden()

            TextEditor(text: $dialogText)
                .font(.body)
                .frame(height: 100)
                .scrollContentBackground(.hidden)
                .background(Color(nsColor: .textBackgroundColor))
                .cornerRadius(DesignSystem.CornerRadius.small)
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )

            HStack {
                Button("Cancel", action: onCancel)
                    .buttonStyle(.modernSecondary)

                Button("Add", action: onAdd)
                    .buttonStyle(.modernPrimary)
                    .disabled(dialogText.isEmpty)
            }
        }
        .padding(DesignSystem.Spacing.xl)
        .frame(width: 400)
    }
}

// MARK: - Export Dialog Sheet

struct ExportDialogSheet: View {
    @Binding var content: String
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            HStack {
                Text("Export Dialog Examples")
                    .font(.headline)
                Spacer()
                Button("Done") {
                    dismiss()
                }
            }

            TextEditor(text: Binding<String>(
                get: { content },
                set: { _ in }
            ))
            .font(.body)
            .textSelection(.enabled)
            .scrollContentBackground(.hidden)
            .padding(DesignSystem.Spacing.md)
            .background(Color(nsColor: .textBackgroundColor))
            .cornerRadius(DesignSystem.CornerRadius.small)

            HStack {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(content, forType: .string)
                    copied = true

                    // Reset after delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        copied = false
                    }
                } label: {
                    HStack {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        Text(copied ? "Copied!" : "Copy to Clipboard")
                    }
                }
                .buttonStyle(.modernPrimary)

                Spacer()
            }
        }
        .padding(DesignSystem.Spacing.xl)
        .frame(width: 600, height: 500)
    }
}

// MARK: - Pasteboard Helpers

private func copyToPasteboard(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
}
