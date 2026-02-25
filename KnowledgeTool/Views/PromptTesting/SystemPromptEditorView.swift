import SwiftUI

struct SystemPromptEditorView: View {
    @Bindable var viewModel: SystemPromptEditorViewModel
    @State private var selectedTab: SystemPromptType = .action
    @State private var showingSaveConfirmation = false
    @State private var promptTypeToSave: SystemPromptType?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("System Prompts")
                        .font(.headline)

                    Text("Edit ASP1, CSP1, and RSP2 templates")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if viewModel.isLoading {
                    ProgressView()
                        .controlSize(.small)
                }

                Button {
                    Task {
                        await viewModel.loadAllPrompts()
                    }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.modernSecondary)
                .disabled(viewModel.isLoading)
            }
            .padding()
            .background(.regularMaterial)

            Divider()

            // Tab picker
            Picker("Prompt Type", selection: $selectedTab) {
                Text(SystemPromptType.action.shortDisplayName).tag(SystemPromptType.action)
                Text(SystemPromptType.conversational.shortDisplayName).tag(SystemPromptType.conversational)
                Text(SystemPromptType.roleplay.shortDisplayName).tag(SystemPromptType.roleplay)
            }
            .pickerStyle(.segmented)
            .padding()

            // Error banner
            if let error = viewModel.error {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)

                    Text(error)
                        .font(.caption)

                    Spacer()

                    Button("Dismiss") {
                        viewModel.error = nil
                    }
                    .font(.caption)
                }
                .padding()
                .background(Color.red.opacity(0.1))

                Divider()
            }

            // Content based on selected tab
            if viewModel.isLoading {
                Spacer()
                ProgressView("Loading system prompts...")
                Spacer()
            } else {
                switch selectedTab {
                case .action:
                    promptEditorContent(
                        type: .action,
                        versions: viewModel.aspVersions,
                        selectedVersion: viewModel.selectedASPVersion,
                        editedContent: $viewModel.editedASPContent,
                        hasChanges: viewModel.hasASPChanges,
                        onSelectVersion: { viewModel.selectASPVersion($0) },
                        onDiscard: { viewModel.discardASPChanges() },
                        onSave: {
                            promptTypeToSave = .action
                            showingSaveConfirmation = true
                        }
                    )

                case .conversational:
                    promptEditorContent(
                        type: .conversational,
                        versions: viewModel.cspVersions,
                        selectedVersion: viewModel.selectedCSPVersion,
                        editedContent: $viewModel.editedCSPContent,
                        hasChanges: viewModel.hasCSPChanges,
                        onSelectVersion: { viewModel.selectCSPVersion($0) },
                        onDiscard: { viewModel.discardCSPChanges() },
                        onSave: {
                            promptTypeToSave = .conversational
                            showingSaveConfirmation = true
                        }
                    )

                case .roleplay:
                    promptEditorContent(
                        type: .roleplay,
                        versions: viewModel.rspVersions,
                        selectedVersion: viewModel.selectedRSPVersion,
                        editedContent: $viewModel.editedRSPContent,
                        hasChanges: viewModel.hasRSPChanges,
                        onSelectVersion: { viewModel.selectRSPVersion($0) },
                        onDiscard: { viewModel.discardRSPChanges() },
                        onSave: {
                            promptTypeToSave = .roleplay
                            showingSaveConfirmation = true
                        }
                    )
                }
            }
        }
        .sheet(isPresented: $showingSaveConfirmation) {
            if let type = promptTypeToSave {
                SystemPromptSaveConfirmationSheet(
                    promptType: type,
                    versions: versionsForType(type),
                    selectedVersion: selectedVersionForType(type),
                    nextVersion: nextVersionForType(type),
                    isSaving: viewModel.isSaving,
                    onSave: { option in
                        Task {
                            let success = await saveWithOption(type: type, option: option)
                            if success {
                                showingSaveConfirmation = false
                            }
                        }
                    },
                    onCancel: {
                        showingSaveConfirmation = false
                    }
                )
            }
        }
        .onAppear {
            if viewModel.aspVersions.isEmpty {
                Task {
                    await viewModel.loadAllPrompts()
                }
            }
        }
    }

    // MARK: - Editor Content

    @ViewBuilder
    private func promptEditorContent(
        type: SystemPromptType,
        versions: [SystemPromptVersion],
        selectedVersion: SystemPromptVersion?,
        editedContent: Binding<String>,
        hasChanges: Bool,
        onSelectVersion: @escaping (SystemPromptVersion) -> Void,
        onDiscard: @escaping () -> Void,
        onSave: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 0) {
            // Version selector and actions
            HStack {
                // Version picker
                if !versions.isEmpty {
                    Menu {
                        ForEach(versions) { version in
                            Button {
                                onSelectVersion(version)
                            } label: {
                                HStack {
                                    Text(version.displayName)
                                    if version.id == selectedVersion?.id {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(selectedVersion?.displayName ?? "Select version")
                                .font(.subheadline.bold())

                            Image(systemName: "chevron.down")
                                .font(.caption)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.regularMaterial)
                        .cornerRadius(6)
                    }
                } else {
                    Text("No versions found")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                // Change indicator
                if hasChanges {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 8, height: 8)

                        Text("Unsaved changes")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                // Word count
                Text("\(editedContent.wrappedValue.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count) words")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                // Actions
                if hasChanges {
                    Button("Discard") {
                        onDiscard()
                    }
                    .buttonStyle(.modernSecondary)
                }

                Button {
                    onSave()
                } label: {
                    Label("Apply Changes", systemImage: "arrow.up.circle.fill")
                }
                .buttonStyle(.modernPrimary)
                .disabled(!hasChanges || viewModel.isSaving)
            }
            .padding()
            .background(.thinMaterial)

            Divider()

            // Editor
            if selectedVersion != nil {
                TextEditor(text: editedContent)
                    .font(.system(.body, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .background(Color(nsColor: .textBackgroundColor))
                    .padding(8)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "doc.text")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)

                    Text("No \(type.rawValue) versions found")
                        .font(.headline)

                    Text("Create a new version to get started")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - Helpers

    private func versionsForType(_ type: SystemPromptType) -> [SystemPromptVersion] {
        switch type {
        case .action: return viewModel.aspVersions
        case .conversational: return viewModel.cspVersions
        case .roleplay: return viewModel.rspVersions
        }
    }

    private func selectedVersionForType(_ type: SystemPromptType) -> SystemPromptVersion? {
        switch type {
        case .action: return viewModel.selectedASPVersion
        case .conversational: return viewModel.selectedCSPVersion
        case .roleplay: return viewModel.selectedRSPVersion
        }
    }

    private func nextVersionForType(_ type: SystemPromptType) -> Int {
        switch type {
        case .action: return viewModel.nextASPVersion
        case .conversational: return viewModel.nextCSPVersion
        case .roleplay: return viewModel.nextRSPVersion
        }
    }

    private func saveWithOption(type: SystemPromptType, option: SystemPromptEditorViewModel.SaveOption) async -> Bool {
        switch type {
        case .action: return await viewModel.saveASP(option: option)
        case .conversational: return await viewModel.saveCSP(option: option)
        case .roleplay: return await viewModel.saveRSP(option: option)
        }
    }
}

// MARK: - System Prompt Save Confirmation Sheet

struct SystemPromptSaveConfirmationSheet: View {
    let promptType: SystemPromptType
    let versions: [SystemPromptVersion]
    let selectedVersion: SystemPromptVersion?
    let nextVersion: Int
    let isSaving: Bool
    let onSave: (SystemPromptEditorViewModel.SaveOption) -> Void
    let onCancel: () -> Void

    @State private var selectedOption: SaveOptionChoice = .overwrite

    enum SaveOptionChoice {
        case overwrite
        case createNew
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.title2)

                Text("Save Changes to \(promptType.rawValue)?")
                    .font(.headline)

                Spacer()
            }
            .padding()
            .background(Color.orange.opacity(0.1))

            Divider()

            // Content
            VStack(alignment: .leading, spacing: 20) {
                Text("How would you like to save your changes?")
                    .font(.subheadline)

                // Option 1: Overwrite
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: selectedOption == .overwrite ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(selectedOption == .overwrite ? .blue : .secondary)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Overwrite existing version")
                                .font(.subheadline.bold())

                            if let selected = selectedVersion {
                                Text("Update \(selected.displayName) with your changes")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedOption = .overwrite
                    }
                }
                .padding()
                .background(selectedOption == .overwrite ? Color.blue.opacity(0.1) : Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(selectedOption == .overwrite ? Color.blue : Color.clear, lineWidth: 2)
                )

                // Option 2: Create new
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: selectedOption == .createNew ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(selectedOption == .createNew ? .blue : .secondary)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Create new version")
                                .font(.subheadline.bold())

                            Text("Save as \(promptType.rawValue)\(nextVersion) (keeps existing versions)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedOption = .createNew
                    }
                }
                .padding()
                .background(selectedOption == .createNew ? Color.blue.opacity(0.1) : Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(selectedOption == .createNew ? Color.blue : Color.clear, lineWidth: 2)
                )

                // Warning
                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.blue)

                    Text("Changes will be saved to the cloud immediately.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()

            Divider()

            // Actions
            HStack {
                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button {
                    let option: SystemPromptEditorViewModel.SaveOption
                    switch selectedOption {
                    case .overwrite:
                        option = .overwrite(version: selectedVersion?.version ?? 1)
                    case .createNew:
                        option = .createNew
                    }
                    onSave(option)
                } label: {
                    if isSaving {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Save Changes")
                    }
                }
                .buttonStyle(.modernPrimary)
                .disabled(isSaving)
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 450)
    }
}
