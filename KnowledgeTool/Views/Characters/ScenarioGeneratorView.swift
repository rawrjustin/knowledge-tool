import SwiftUI

/// View for generating and managing scenarios for a character
struct ScenarioGeneratorView: View {
    let character: Character
    @Bindable var viewModel: ScenarioViewModel

    @State private var showingAddSheet = false
    @State private var showingExportSheet = false
    @State private var exportContent: String = ""
    @State private var newTitle: String = ""
    @State private var newSituation: String = ""
    @State private var newObjective: String = ""

    var body: some View {
        HSplitView {
            // Left panel: Configuration
            configurationPanel
                .frame(minWidth: 280, idealWidth: 320, maxWidth: 400)

            // Right panel: Scenarios
            scenariosPanel
                .frame(minWidth: 400)
        }
        .sheet(isPresented: $showingAddSheet) {
            AddScenarioSheet(
                title: $newTitle,
                situation: $newSituation,
                objective: $newObjective,
                onAdd: {
                    if !newTitle.isEmpty && !newSituation.isEmpty && !newObjective.isEmpty {
                        viewModel.addScenario(
                            title: newTitle,
                            currentSituation: newSituation,
                            liveObjective: newObjective
                        )
                    }
                    showingAddSheet = false
                    newTitle = ""
                    newSituation = ""
                    newObjective = ""
                },
                onCancel: {
                    showingAddSheet = false
                    newTitle = ""
                    newSituation = ""
                    newObjective = ""
                }
            )
        }
        .sheet(isPresented: $showingExportSheet) {
            ExportScenarioSheet(content: exportContent)
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
                    Text("Scenarios")
                        .font(.title2.bold())

                    HStack(spacing: DesignSystem.Spacing.sm) {
                        Text("Generate scenarios for \(character.name)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Text(character.systemPromptType.shortDisplayName)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, DesignSystem.Spacing.sm)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.15))
                            .cornerRadius(DesignSystem.CornerRadius.small)
                    }
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

                // Theme Input
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                    Text("THEME")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    TextField("e.g., High Stakes, Emotional Moments, First Meetings", text: $viewModel.theme)
                        .textFieldStyle(.roundedBorder)
                        .font(.subheadline)

                    Text("Leave blank for general scenarios")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                Divider()

                // Generation Options
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                    Text("GENERATION OPTIONS")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    HStack {
                        Text("Number of scenarios:")
                            .font(.subheadline)
                        Spacer()
                        Picker("", selection: $viewModel.numberOfScenarios) {
                            Text("3").tag(3)
                            Text("5").tag(5)
                            Text("7").tag(7)
                            Text("10").tag(10)
                        }
                        .labelsHidden()
                        .frame(width: 80)
                    }

                    Toggle(isOn: $viewModel.includeDramaticStakes) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Include dramatic stakes")
                                .font(.subheadline)
                            Text("Add tension and urgency to scenarios")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .toggleStyle(.switch)
                }

                Divider()

                // Theme Suggestions
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                    Text("THEME SUGGESTIONS")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    FlowLayout(spacing: DesignSystem.Spacing.xs) {
                        ThemeSuggestionChip(text: "High Stakes") {
                            viewModel.theme = "High Stakes"
                        }
                        ThemeSuggestionChip(text: "Emotional") {
                            viewModel.theme = "Emotional Moments"
                        }
                        ThemeSuggestionChip(text: "Conflict") {
                            viewModel.theme = "Conflict and Confrontation"
                        }
                        ThemeSuggestionChip(text: "Romance") {
                            viewModel.theme = "Romantic Encounters"
                        }
                        ThemeSuggestionChip(text: "Mystery") {
                            viewModel.theme = "Mystery and Intrigue"
                        }
                        ThemeSuggestionChip(text: "Comedy") {
                            viewModel.theme = "Comedic Situations"
                        }
                    }
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
                            Image(systemName: "theatermasks")
                        }
                        Text(viewModel.isGenerating ? "Generating..." : "Generate Scenarios")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DesignSystem.Spacing.sm)
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isGenerating)

            }
            .padding(DesignSystem.Spacing.lg)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Scenarios Panel

    private var scenariosPanel: some View {
        VStack(spacing: 0) {
            // Stats header
            HStack {
                Text("Total: \(viewModel.totalCount) scenarios")
                    .font(.headline)

                if let active = viewModel.activeScenario {
                    Text("Active: \(active.title)")
                        .font(.caption)
                        .foregroundStyle(.green)
                        .padding(.horizontal, DesignSystem.Spacing.sm)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.15))
                        .cornerRadius(4)
                }

                Spacer()

                // Source legend
                HStack(spacing: DesignSystem.Spacing.md) {
                    SourceLegend(color: .orange, label: "AI")
                    SourceLegend(color: .green, label: "User")
                }
                .font(.caption)

                Spacer()

                if viewModel.hasScenarios {
                    Button {
                        exportContent = viewModel.exportPlainText()
                        showingExportSheet = true
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.bordered)

                    if viewModel.activeScenario != nil {
                        Button {
                            Task {
                                await viewModel.deactivateAll()
                            }
                        } label: {
                            Label("Deactivate", systemImage: "stop.circle")
                        }
                        .buttonStyle(.bordered)
                    }

                    Button(role: .destructive) {
                        viewModel.deleteAllScenarios()
                    } label: {
                        Label("Clear All", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                }

                Button {
                    showingAddSheet = true
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .buttonStyle(.bordered)
            }
            .padding(DesignSystem.Spacing.md)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            if viewModel.allScenarios.isEmpty {
                emptyState
            } else if !viewModel.allScenarios.isEmpty {
                scenariosList
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            Image(systemName: "theatermasks")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)

            Text("No Scenarios")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text("Enter a theme and click Generate to create scenarios for \(character.name)")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var scenariosList: some View {
        ScrollView {
            LazyVStack(spacing: DesignSystem.Spacing.md) {
                ForEach(viewModel.allScenarios) { scenario in
                    ScenarioCard(
                        scenario: scenario,
                        isEditing: viewModel.editingScenario?.id == scenario.id,
                        editedTitle: $viewModel.editedTitle,
                        editedSituation: $viewModel.editedSituation,
                        editedObjective: $viewModel.editedObjective,
                        onActivate: {
                            Task {
                                await viewModel.activateScenario(scenario)
                            }
                        },
                        onDeactivate: {
                            Task {
                                await viewModel.deactivateScenario(scenario)
                            }
                        },
                        onEdit: {
                            viewModel.startEditing(scenario)
                        },
                        onSaveEdit: {
                            viewModel.saveEditedScenario()
                        },
                        onCancelEdit: {
                            viewModel.cancelEditing()
                        },
                        onRegenerate: {
                            Task {
                                await viewModel.regenerateScenario(scenario)
                            }
                        },
                        onDelete: {
                            viewModel.deleteScenario(scenario)
                        },
                        onApply: {
                            Task {
                                await viewModel.applyScenario(scenario)
                            }
                        }
                    )
                }
            }
            .padding(DesignSystem.Spacing.md)
        }
    }
}

// MARK: - Theme Suggestion Chip

struct ThemeSuggestionChip: View {
    let text: String
    let onTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            Text(text)
                .font(.caption)
                .padding(.horizontal, DesignSystem.Spacing.sm)
                .padding(.vertical, DesignSystem.Spacing.xs)
                .background(isHovered ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1))
                .foregroundStyle(isHovered ? .primary : .secondary)
                .cornerRadius(DesignSystem.CornerRadius.small)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = flowLayout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = flowLayout(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func flowLayout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }

            positions.append(CGPoint(x: currentX, y: currentY))
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }

        let totalHeight = currentY + lineHeight
        return (CGSize(width: maxWidth, height: totalHeight), positions)
    }
}

// MARK: - Source Legend

struct SourceLegend: View {
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

// MARK: - Scenario Card

struct ScenarioCard: View {
    let scenario: Scenario
    let isEditing: Bool
    @Binding var editedTitle: String
    @Binding var editedSituation: String
    @Binding var editedObjective: String
    let onActivate: () -> Void
    let onDeactivate: () -> Void
    let onEdit: () -> Void
    let onSaveEdit: () -> Void
    let onCancelEdit: () -> Void
    let onRegenerate: () -> Void
    let onDelete: () -> Void
    let onApply: () -> Void

    @State private var isHovered = false
    @State private var isExpanded = true
    @State private var copyConfirmed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            headerRow
                .padding(DesignSystem.Spacing.md)

            // Content — always visible as preview, expandable for full text
            if isEditing {
                Divider()
                editingContent
                    .padding(DesignSystem.Spacing.md)
            } else {
                Divider()
                previewContent
                    .padding(DesignSystem.Spacing.md)
            }
        }
        .background(scenario.isActive ? Color.green.opacity(0.05) : Color(nsColor: .controlBackgroundColor))
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                .stroke(scenario.isActive ? Color.green.opacity(0.3) : Color.clear, lineWidth: 1)
        )
        .cornerRadius(DesignSystem.CornerRadius.medium)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            // Source indicator
            RoundedRectangle(cornerRadius: 2)
                .fill(sourceColor)
                .frame(width: 4, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                if isEditing {
                    TextField("Title", text: $editedTitle)
                        .font(.headline)
                        .textFieldStyle(.roundedBorder)
                } else {
                    Text(scenario.title)
                        .font(.headline)
                }

                HStack(spacing: DesignSystem.Spacing.sm) {
                    Text(scenario.theme)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if scenario.isActive {
                        Text("ACTIVE")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.green)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.green.opacity(0.15))
                            .cornerRadius(3)
                    }
                }
            }

            Spacer()

            // Action buttons
            if isEditing {
                Button("Cancel", action: onCancelEdit)
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                Button("Save", action: onSaveEdit)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            } else if isHovered {
                HStack(spacing: DesignSystem.Spacing.xs) {
                    Button {
                        if scenario.isActive {
                            onDeactivate()
                        } else {
                            onActivate()
                        }
                    } label: {
                        Image(systemName: scenario.isActive ? "stop.circle.fill" : "play.circle")
                            .font(.body)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(scenario.isActive ? .green : .secondary)
                    .help(scenario.isActive ? "Deactivate" : "Activate")

                    Button(action: onApply) {
                        Image(systemName: "arrow.down.doc")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.purple)
                    .help("Apply to Persona")

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
            }

            // Expand/collapse
            Button {
                withAnimation(DesignSystem.Animation.quick) {
                    isExpanded.toggle()
                }
            } label: {
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Preview Content

    private var previewContent: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            // Current Situation
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                Text("CURRENT SITUATION")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(scenario.currentSituation)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .lineLimit(isExpanded ? nil : 2)
                    .textSelection(.enabled)
            }

            // Live Objective
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                Text("LIVE OBJECTIVE")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)

                Text(scenario.liveObjective)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .lineLimit(isExpanded ? nil : 3)
                    .textSelection(.enabled)
            }

            // Copy button
            if isExpanded {
                HStack {
                    Spacer()
                    Button {
                        let text = "### Current Situation\n\(scenario.currentSituation)\n\n### Live Objective\n\(scenario.liveObjective)"
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                        copyConfirmed = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            copyConfirmed = false
                        }
                    } label: {
                        Label(
                            copyConfirmed ? "Copied!" : "Copy Scenario",
                            systemImage: copyConfirmed ? "checkmark" : "doc.on.doc"
                        )
                        .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }

    // MARK: - Editing Content

    private var editingContent: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                Text("CURRENT SITUATION")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                TextEditor(text: $editedSituation)
                    .font(.body)
                    .frame(minHeight: 80)
                    .scrollContentBackground(.hidden)
                    .background(Color(nsColor: .textBackgroundColor))
                    .cornerRadius(DesignSystem.CornerRadius.small)
            }

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                Text("LIVE OBJECTIVE")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)

                TextEditor(text: $editedObjective)
                    .font(.body)
                    .frame(minHeight: 100)
                    .scrollContentBackground(.hidden)
                    .background(Color(nsColor: .textBackgroundColor))
                    .cornerRadius(DesignSystem.CornerRadius.small)
            }
        }
    }

    private var sourceColor: Color {
        switch scenario.source {
        case .generated: return .orange
        case .userCreated: return .green
        }
    }
}

// MARK: - Add Scenario Sheet

struct AddScenarioSheet: View {
    @Binding var title: String
    @Binding var situation: String
    @Binding var objective: String
    let onAdd: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            Text("Add Scenario")
                .font(.headline)

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                    Text("Title")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    TextField("Brief, evocative title", text: $title)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                    Text("Current Situation")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    TextEditor(text: $situation)
                        .font(.body)
                        .frame(height: 100)
                        .scrollContentBackground(.hidden)
                        .background(Color(nsColor: .textBackgroundColor))
                        .cornerRadius(DesignSystem.CornerRadius.small)
                        .overlay(
                            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small)
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                        )
                }

                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                    Text("Live Objective")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    TextEditor(text: $objective)
                        .font(.body)
                        .frame(height: 80)
                        .scrollContentBackground(.hidden)
                        .background(Color(nsColor: .textBackgroundColor))
                        .cornerRadius(DesignSystem.CornerRadius.small)
                        .overlay(
                            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small)
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                        )
                }
            }

            HStack {
                Button("Cancel", action: onCancel)
                    .buttonStyle(.bordered)

                Button("Add", action: onAdd)
                    .buttonStyle(.borderedProminent)
                    .disabled(title.isEmpty || situation.isEmpty || objective.isEmpty)
            }
        }
        .padding(DesignSystem.Spacing.xl)
        .frame(width: 500)
    }
}

// MARK: - Export Scenario Sheet

struct ExportScenarioSheet: View {
    let content: String
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            HStack {
                Text("Export Scenarios")
                    .font(.headline)
                Spacer()
                Button("Done") {
                    dismiss()
                }
            }

            ScrollView {
                Text(content)
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(DesignSystem.Spacing.md)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .cornerRadius(DesignSystem.CornerRadius.small)

            HStack {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(content, forType: .string)
                    copied = true

                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        copied = false
                    }
                } label: {
                    HStack {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        Text(copied ? "Copied!" : "Copy to Clipboard")
                    }
                }
                .buttonStyle(.borderedProminent)

                Spacer()
            }
        }
        .padding(DesignSystem.Spacing.xl)
        .frame(width: 600, height: 500)
    }
}

