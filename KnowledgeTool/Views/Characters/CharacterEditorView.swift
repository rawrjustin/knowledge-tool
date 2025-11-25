import SwiftUI

struct CharacterEditorView: View {
    @State private var viewModel: CharacterEditorViewModel
    let onSave: (Character) -> Void
    let onCancel: () -> Void

    @State private var showingDiscardAlert = false

    init(
        mode: CharacterEditorViewModel.Mode,
        localRepository: LocalCharacterRepository,
        onSave: @escaping (Character) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self._viewModel = State(initialValue: CharacterEditorViewModel(
            mode: mode,
            localRepository: localRepository
        ))
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(viewModel.character == nil ? "Create Character" : "Edit Character")
                        .font(.title2.bold())

                    if viewModel.hasUnsavedChanges {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.orange)
                                .frame(width: 8, height: 8)
                            Text("Unsaved changes")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Spacer()

                // Actions
                HStack(spacing: 12) {
                    Button("Cancel") {
                        handleCancel()
                    }
                    .keyboardShortcut(.cancelAction)

                    Button("Save") {
                        Task {
                            if await viewModel.save() {
                                if let character = viewModel.character {
                                    onSave(character)
                                }
                            }
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.name.isEmpty || viewModel.isSaving)
                }
            }
            .padding()

            Divider()

            // Error banner
            if let error = viewModel.error {
                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)

                    Text(error)
                        .font(.subheadline)

                    Spacer()

                    Button("Dismiss") {
                        viewModel.error = nil
                    }
                    .font(.subheadline)
                }
                .padding()
                .background(Color.red.opacity(0.1))

                Divider()
            }

            // Editor content
            HSplitView {
                // Left sidebar - metadata
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Character Name")
                            .font(.headline)

                        TextField("Enter character name", text: $viewModel.name)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: viewModel.name) {
                                viewModel.markAsChanged()
                            }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("System Prompt Type")
                            .font(.headline)

                        Picker("", selection: $viewModel.systemPromptType) {
                            ForEach(SystemPromptType.allCases, id: \.self) { type in
                                VStack(alignment: .leading) {
                                    Text(type.displayName)
                                        .font(.body)
                                    Text(type.description)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .tag(type)
                            }
                        }
                        .pickerStyle(.radioGroup)
                        .onChange(of: viewModel.systemPromptType) {
                            viewModel.markAsChanged()
                        }
                    }

                    Divider()

                    // Metadata info
                    if let character = viewModel.character {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Metadata")
                                .font(.headline)

                            MetadataRow(
                                label: "Version",
                                value: character.versionDisplay
                            )

                            MetadataRow(
                                label: "Created",
                                value: character.createdAt.formatted(date: .abbreviated, time: .shortened)
                            )

                            MetadataRow(
                                label: "Last Modified",
                                value: character.lastModified.formatted(date: .abbreviated, time: .shortened)
                            )

                            MetadataRow(
                                label: "Knowledge Files",
                                value: "\(character.knowledgeFiles.count)"
                            )

                            MetadataRow(
                                label: "Total Words",
                                value: "\(character.totalKnowledgeWords)"
                            )
                        }
                    }

                    Spacer()
                }
                .padding()
                .frame(minWidth: 250, idealWidth: 300, maxWidth: 350)
                .background(Color(nsColor: .controlBackgroundColor))

                // Right side - markdown editor
                VStack(spacing: 0) {
                    // Toolbar
                    HStack {
                        Text("Persona Markdown")
                            .font(.headline)

                        Spacer()

                        Text("\(viewModel.markdownContent.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count) words")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .background(Color(nsColor: .windowBackgroundColor))

                    Divider()

                    // Markdown editor
                    TextEditor(text: $viewModel.markdownContent)
                        .font(.system(.body, design: .monospaced))
                        .onChange(of: viewModel.markdownContent) {
                            viewModel.markAsChanged()
                        }
                }
            }
        }
        .frame(minWidth: 800, minHeight: 600)
        .alert("Discard Changes?", isPresented: $showingDiscardAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Discard", role: .destructive) {
                onCancel()
            }
        } message: {
            Text("You have unsaved changes. Are you sure you want to discard them?")
        }
    }

    private func handleCancel() {
        if viewModel.hasUnsavedChanges {
            showingDiscardAlert = true
        } else {
            onCancel()
        }
    }
}

// MARK: - Metadata Row
struct MetadataRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Text(value)
                .font(.caption)
        }
    }
}
