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
        case .scenarios: return "Situations & objectives"
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
    @Environment(BackgroundJobManager.self) private var backgroundJobManager
    @State private var selectedTab: DashboardTab = .persona
    @State private var showingAugmentSheet = false
    @State private var editorViewModel: CharacterEditorViewModel
    var scenarioViewModel: ScenarioViewModel?
    var creationViewModel: CharacterCreationViewModel?
    @State private var showingSaveConfirmation = false
    @State private var showSaveSuccess = false
    @State private var showingDiscardAlert = false
    @State private var showingRenameSheet = false
    @State private var isRenaming = false
    @State private var renameDraft: String = ""
    @State private var renameError: String?
    @State private var showingPublishSheet = false
    @State private var publishViewModel = PublishViewModel()

    init(
        character: Character,
        repository: CombinedCharacterRepository,
        apiKeyManager: APIKeyManager,
        scenarioViewModel: ScenarioViewModel? = nil,
        creationViewModel: CharacterCreationViewModel? = nil,
        onCharacterUpdated: @escaping (Character) -> Void
    ) {
        self.character = character
        self.repository = repository
        self.apiKeyManager = apiKeyManager
        self.scenarioViewModel = scenarioViewModel
        self.creationViewModel = creationViewModel
        self.onCharacterUpdated = onCharacterUpdated
        self._editorViewModel = State(initialValue: CharacterEditorViewModel(
            mode: .edit(character),
            repository: repository
        ))
    }

    private var isCharacterGenerating: Bool {
        character.isGenerating || backgroundJobManager.isGenerating(characterName: character.name, type: .characterCreation)
    }

    var body: some View {
        if isCharacterGenerating {
            CharacterGeneratingView(character: character, creationViewModel: creationViewModel)
        } else {
            dashboardContent
        }
    }

    private var dashboardContent: some View {
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
        .toast(isShowing: $showSaveSuccess, message: "Character saved successfully", style: .success)
        .alert("Revert Changes?", isPresented: $showingDiscardAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Revert", role: .destructive) {
                editorViewModel.discardChanges()
            }
        } message: {
            Text("This will revert all unsaved changes to the persona markdown.")
        }
        .sheet(isPresented: $showingSaveConfirmation) {
            SaveConfirmationSheet(
                viewModel: editorViewModel,
                onConfirm: {
                    Task {
                        if await editorViewModel.save() {
                            showingSaveConfirmation = false
                            showSaveSuccess = true
                            if let character = editorViewModel.character {
                                onCharacterUpdated(character)
                            }
                        }
                    }
                },
                onCancel: {
                    showingSaveConfirmation = false
                }
            )
        }
        .sheet(isPresented: $showingRenameSheet) {
            RenameCharacterSheet(
                currentName: character.name,
                draftName: $renameDraft,
                isSaving: isRenaming,
                error: renameError,
                onCancel: {
                    showingRenameSheet = false
                    renameError = nil
                },
                onConfirm: {
                    Task { @MainActor in
                        await renameCharacter()
                    }
                }
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
                    // Name + rename inline
                    HStack(spacing: DesignSystem.Spacing.sm) {
                        Text(character.name)
                            .font(.title2.weight(.semibold))

                        Button {
                            renameDraft = character.name
                            renameError = nil
                            showingRenameSheet = true
                        } label: {
                            Image(systemName: "pencil")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .disabled(editorViewModel.hasUnsavedChanges || isRenaming)
                        .help(editorViewModel.hasUnsavedChanges ? "Save or revert changes before renaming" : "Rename this character")
                    }

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
                        Text(character.systemPromptType.shortDisplayName)
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.15))
                            .foregroundStyle(.blue)
                            .clipShape(Capsule())

                        // Genies publish status
                        PublishStatusBadge(character: character, repository: repository)

                        // Cloud sync status
                        if syncManager.canSync {
                            SyncStatusIndicator()
                        }

                        // Unsaved changes indicator
                        if editorViewModel.hasUnsavedChanges {
                            StatusBadge(text: "Unsaved changes", status: .warning)
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
                    value: "\(wordCount(editorViewModel.markdownContent))",
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
                .buttonStyle(.modernSecondary)
                .help("Add source content to enhance this persona")

                if editorViewModel.hasUnsavedChanges {
                    Button {
                        showingDiscardAlert = true
                    } label: {
                        Label("Revert", systemImage: "arrow.uturn.backward")
                    }
                    .buttonStyle(.modernSecondary)
                    .help("Revert all changes")
                }

                // Save button
                Button {
                    if editorViewModel.hasUnsavedChanges {
                        showingSaveConfirmation = true
                    }
                } label: {
                    Label("Save", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.modernSecondary)
                .disabled(!editorViewModel.hasUnsavedChanges || editorViewModel.isSaving)
                .help("Save changes (Cmd+S)")
                .keyboardShortcut("s", modifiers: .command)

                // Save & Publish / Publish / Update — primary action
                publishActionButton
            }
        }
        .padding(DesignSystem.Spacing.lg)
        .background(.regularMaterial)
        .task {
            await publishViewModel.loadPublishState(for: character, repository: repository)
        }
        .onChange(of: character.sha) { _, _ in
            Task {
                await publishViewModel.loadPublishState(for: character, repository: repository)
            }
        }
        .sheet(isPresented: $showingPublishSheet) {
            PublishSheet(
                character: character,
                repository: repository,
                publishViewModel: publishViewModel,
                onDismiss: { showingPublishSheet = false }
            )
        }
    }

    @ViewBuilder
    private var publishActionButton: some View {
        switch publishViewModel.publishState {
        case .unpublished:
            if editorViewModel.hasUnsavedChanges {
                // Has unsaved changes + not published → Save & Publish
                Button {
                    Task {
                        if await editorViewModel.save() {
                            showSaveSuccess = true
                            if let character = editorViewModel.character {
                                onCharacterUpdated(character)
                            }
                            showingPublishSheet = true
                        }
                    }
                } label: {
                    Label("Save & Publish", systemImage: "arrow.up.circle.fill")
                }
                .buttonStyle(.modernPrimary)
                .disabled(editorViewModel.isSaving)
            } else {
                Button {
                    showingPublishSheet = true
                } label: {
                    Label("Publish", systemImage: "arrow.up.circle.fill")
                }
                .buttonStyle(.modernPrimary)
            }

        case .clean:
            // Already published and clean — no action needed, badge shows status
            EmptyView()

        case .dirtyEdits:
            if editorViewModel.hasUnsavedChanges {
                Button {
                    Task {
                        if await editorViewModel.save() {
                            showSaveSuccess = true
                            if let character = editorViewModel.character {
                                onCharacterUpdated(character)
                            }
                            showingPublishSheet = true
                        }
                    }
                } label: {
                    Label("Save & Update", systemImage: "arrow.up.circle.fill")
                }
                .buttonStyle(.modernPrimary)
                .disabled(editorViewModel.isSaving)
            } else {
                Button {
                    showingPublishSheet = true
                } label: {
                    Label("Update Config", systemImage: "arrow.up.circle")
                }
                .buttonStyle(.modernPrimary)
            }
        }
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
        .background(.regularMaterial)
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
                viewModel: editorViewModel,
                knowledgeBySection: character.sectionsWithKnowledge
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
            if let scenarioViewModel = scenarioViewModel {
                ScenarioGeneratorView(
                    character: character,
                    viewModel: scenarioViewModel
                )
            } else {
                ProgressView("Loading...")
            }
        }
    }

    private func wordCount(_ text: String) -> Int {
        text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count
    }

    @MainActor
    private func renameCharacter() async {
        guard !isRenaming else { return }
        renameError = nil

        let newName = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty else {
            renameError = "Name cannot be empty."
            return
        }

        if newName.lowercased() == character.name.lowercased() {
            showingRenameSheet = false
            return
        }

        isRenaming = true
        defer { isRenaming = false }

        do {
            let updated = try await repository.renameCharacter(character, to: newName)
            editorViewModel = CharacterEditorViewModel(mode: .edit(updated), repository: repository)
            showingRenameSheet = false
            renameError = nil
            onCharacterUpdated(updated)
        } catch {
            renameError = error.localizedDescription
        }
    }
}

// MARK: - Rename Sheet

private struct RenameCharacterSheet: View {
    let currentName: String
    @Binding var draftName: String
    let isSaving: Bool
    let error: String?
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                Text("Rename Character")
                    .font(.title2.bold())
                Text("This renames the local folder and updates Supabase (if sync is enabled).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                Text("New Name")
                    .font(.headline)
                TextField("Name", text: $draftName)
                    .polishedInput()
                Text("Current: \(currentName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let error, !error.isEmpty {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(DesignSystem.Spacing.sm)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(DesignSystem.CornerRadius.small)
            }

            HStack {
                Button("Cancel") { onCancel() }
                    .keyboardShortcut(.cancelAction)

                Spacer()

                Button(isSaving ? "Renaming..." : "Rename") { onConfirm() }
                    .buttonStyle(.modernPrimary)
                    .disabled(isSaving || draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(DesignSystem.Spacing.xl)
        .frame(width: 520)
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
    @Bindable var viewModel: CharacterEditorViewModel
    let knowledgeBySection: [String: [KnowledgeSource]]

    @State private var editingSectionTitle: String?
    @State private var editableContent: String = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
                // Parse sections from markdown
                ForEach(parsedSections, id: \.title) { section in
                    PersonaSectionCard(
                        section: section,
                        knowledgeSources: knowledgeBySection[section.title] ?? [],
                        isEditing: editingSectionTitle == section.title,
                        editableContent: editingSectionTitle == section.title ? $editableContent : nil,
                        onStartEditing: {
                            // Auto-commit previous section if switching
                            if let previousTitle = editingSectionTitle, previousTitle != section.title {
                                commitCurrentEdit()
                            }
                            editingSectionTitle = section.title
                            editableContent = section.content
                        },
                        onDoneEditing: {
                            commitCurrentEdit()
                        },
                        onCancelEditing: {
                            editingSectionTitle = nil
                            editableContent = ""
                        }
                    )
                }
            }
            .padding(DesignSystem.Spacing.lg)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var parsedSections: [PersonaSection] {
        parseMarkdownSections(viewModel.markdownContent)
    }

    private func commitCurrentEdit() {
        guard let title = editingSectionTitle else { return }
        updateSection(title: title, newContent: editableContent)
        editingSectionTitle = nil
        editableContent = ""
    }

    private func updateSection(title: String, newContent: String) {
        let escaped = NSRegularExpression.escapedPattern(for: title)
        let pattern = "(##\\s*\(escaped)\\s*\\n)([\\s\\S]*?)(?=\\n##\\s|\\z)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return }

        let nsString = viewModel.markdownContent as NSString
        let fullRange = NSRange(location: 0, length: nsString.length)

        guard let match = regex.firstMatch(in: viewModel.markdownContent, range: fullRange),
              match.numberOfRanges >= 3 else { return }

        let contentRange = match.range(at: 2)
        let replacement = newContent.trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
        viewModel.markdownContent = nsString.replacingCharacters(in: contentRange, with: replacement)
        viewModel.markAsChanged()
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
    let isEditing: Bool
    let editableContent: Binding<String>?
    let onStartEditing: () -> Void
    let onDoneEditing: () -> Void
    let onCancelEditing: () -> Void

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

                    // Edit button
                    if !isEditing {
                        Button {
                            if !isExpanded {
                                withAnimation(DesignSystem.Animation.quick) {
                                    isExpanded = true
                                }
                            }
                            onStartEditing()
                        } label: {
                            Image(systemName: "pencil")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(DesignSystem.Spacing.xs)
                        }
                        .buttonStyle(.plain)
                        .help("Edit this section")
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
            if isExpanded || isEditing {
                Divider()

                if isEditing, let binding = editableContent {
                    // Editing mode
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                        TextEditor(text: binding)
                            .font(.system(.body, design: .monospaced))
                            .frame(minHeight: 150, maxHeight: 400)
                            .scrollContentBackground(.hidden)
                            .background(Color(nsColor: .textBackgroundColor))

                        HStack {
                            Spacer()

                            Button("Cancel") {
                                onCancelEditing()
                            }
                            .buttonStyle(.modernSecondary)
                            .keyboardShortcut(.cancelAction)

                            Button("Done") {
                                onDoneEditing()
                            }
                            .buttonStyle(.modernPrimary)
                            .keyboardShortcut(.defaultAction)
                        }
                    }
                    .padding(DesignSystem.Spacing.md)
                } else {
                    // Read-only display
                    Text(section.content)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .padding(DesignSystem.Spacing.md)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
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
        .sectionContainer(padding: 0)
        .onChange(of: isEditing) { _, newValue in
            if newValue && !isExpanded {
                withAnimation(DesignSystem.Animation.quick) {
                    isExpanded = true
                }
            }
        }
    }
}
