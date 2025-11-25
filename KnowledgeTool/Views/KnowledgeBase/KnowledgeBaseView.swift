import SwiftUI

struct KnowledgeBaseView: View {
    @State private var viewModel: KnowledgeBaseViewModel
    @State private var showingNewFileSheet = false
    @State private var showingDeleteConfirmation = false
    @State private var fileToDelete: KnowledgeFile?

    init(character: Character, localRepository: LocalCharacterRepository) {
        self._viewModel = State(initialValue: KnowledgeBaseViewModel(
            character: character,
            localRepository: localRepository
        ))
    }

    var body: some View {
        HSplitView {
            // Left sidebar - file list
            VStack(spacing: 0) {
                // Header with stats
                VStack(alignment: .leading, spacing: 12) {
                    Text("Knowledge Base")
                        .font(.title2.bold())

                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(viewModel.fileCount)")
                                .font(.title3.bold())
                            Text("Files")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(viewModel.totalWordCount)")
                                .font(.title3.bold())
                            Text("Words")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding()

                Divider()

                // Search bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)

                    TextField("Search knowledge...", text: $viewModel.searchText)
                        .textFieldStyle(.plain)
                }
                .padding()
                .background(Color(nsColor: .controlBackgroundColor))

                Divider()

                // File list
                if viewModel.filteredFiles.isEmpty {
                    VStack(spacing: 12) {
                        Spacer()

                        Image(systemName: "doc.text")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)

                        Text(viewModel.searchText.isEmpty ? "No Knowledge Files" : "No Results")
                            .font(.headline)

                        if viewModel.searchText.isEmpty {
                            Text("Add knowledge files to build this character's knowledge base")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }

                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    List(viewModel.filteredFiles, selection: $viewModel.selectedFile) { file in
                        KnowledgeFileRow(file: file, isSelected: viewModel.selectedFile?.id == file.id)
                            .tag(file)
                            .contextMenu {
                                Button(role: .destructive) {
                                    fileToDelete = file
                                    showingDeleteConfirmation = true
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                }

                Divider()

                // Bottom toolbar
                HStack {
                    Button {
                        showingNewFileSheet = true
                    } label: {
                        Label("New File", systemImage: "plus.circle.fill")
                            .font(.subheadline)
                    }
                    .buttonStyle(.borderedProminent)

                    Spacer()

                    Button {
                        Task {
                            await viewModel.refresh()
                        }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                            .font(.subheadline)
                    }
                    .disabled(viewModel.isLoading)
                }
                .padding()
            }
            .frame(minWidth: 250, idealWidth: 300, maxWidth: 350)
            .background(Color(nsColor: .controlBackgroundColor))

            // Right side - file content viewer/editor
            if let selectedFile = viewModel.selectedFile {
                KnowledgeFileDetailView(
                    file: selectedFile,
                    onSave: { updatedFile in
                        Task {
                            _ = await viewModel.saveKnowledgeFile(updatedFile)
                        }
                    },
                    onDelete: {
                        fileToDelete = selectedFile
                        showingDeleteConfirmation = true
                    }
                )
                .id(selectedFile.id) // Force view to recreate when file changes
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)

                    Text("Select a Knowledge File")
                        .font(.title2.bold())

                    Text("Choose a file from the list to view or edit its content")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .textBackgroundColor))
            }
        }
        .alert("Delete File?", isPresented: $showingDeleteConfirmation, presenting: fileToDelete) { file in
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                Task {
                    _ = await viewModel.deleteKnowledgeFile(file)
                }
            }
        } message: { file in
            Text("Are you sure you want to delete \"\(file.fileName)\"? This action cannot be undone.")
        }
        .sheet(isPresented: $showingNewFileSheet) {
            NewKnowledgeFileSheet(
                onCreate: { fileName, content in
                    Task {
                        let success = await viewModel.createKnowledgeFile(fileName: fileName, content: content)
                        if success {
                            showingNewFileSheet = false
                        }
                    }
                },
                onCancel: {
                    showingNewFileSheet = false
                }
            )
        }
    }
}

// MARK: - Knowledge File Row
struct KnowledgeFileRow: View {
    let file: KnowledgeFile
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(file.displayName)
                .font(.body)
                .lineLimit(1)

            HStack(spacing: 12) {
                Label("\(file.wordCount) words", systemImage: "doc.text")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(file.modifiedAt, format: .relative(presentation: .named))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Knowledge File Detail View
struct KnowledgeFileDetailView: View {
    @State private var file: KnowledgeFile
    @State private var isEditing = false
    @State private var editedContent: String
    @State private var hasUnsavedChanges = false

    let onSave: (KnowledgeFile) -> Void
    let onDelete: () -> Void

    init(file: KnowledgeFile, onSave: @escaping (KnowledgeFile) -> Void, onDelete: @escaping () -> Void) {
        self._file = State(initialValue: file)
        self._editedContent = State(initialValue: file.content)
        self.onSave = onSave
        self.onDelete = onDelete
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(file.displayName)
                        .font(.title2.bold())

                    Text("\(editedContent.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count) words • Modified \(file.modifiedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if hasUnsavedChanges {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 8, height: 8)
                        Text("Unsaved")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.trailing)
                }

                // Actions
                HStack(spacing: 12) {
                    if isEditing {
                        Button("Cancel") {
                            editedContent = file.content
                            isEditing = false
                            hasUnsavedChanges = false
                        }

                        Button("Save") {
                            var updatedFile = file
                            updatedFile.content = editedContent
                            updatedFile.modifiedAt = Date()
                            onSave(updatedFile)
                            file = updatedFile
                            isEditing = false
                            hasUnsavedChanges = false
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        Button {
                            isEditing = true
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }

                        Button(role: .destructive) {
                            onDelete()
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .padding()

            Divider()

            // Content
            if isEditing {
                TextEditor(text: $editedContent)
                    .font(.system(.body, design: .default))
                    .onChange(of: editedContent) {
                        hasUnsavedChanges = editedContent != file.content
                    }
            } else {
                ScrollView {
                    Text(file.content)
                        .font(.body)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .onChange(of: file) {
            editedContent = file.content
            isEditing = false
            hasUnsavedChanges = false
        }
    }
}

// MARK: - New Knowledge File Sheet
struct NewKnowledgeFileSheet: View {
    @State private var fileName = ""
    @State private var content = ""

    let onCreate: (String, String) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("New Knowledge File")
                    .font(.title2.bold())

                Spacer()

                Button("Cancel") {
                    onCancel()
                }
            }
            .padding()

            Divider()

            // Form
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("File Name")
                        .font(.headline)

                    TextField("Enter file name (e.g., interview_summary.txt)", text: $fileName)
                        .textFieldStyle(.roundedBorder)

                    Text("Must end with .txt")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Content")
                        .font(.headline)

                    TextEditor(text: $content)
                        .font(.system(.body, design: .default))
                        .border(Color(nsColor: .separatorColor))
                        .frame(minHeight: 300)
                }
            }
            .padding()

            Divider()

            // Footer
            HStack {
                Spacer()

                Button("Create") {
                    let finalFileName = fileName.hasSuffix(".txt") ? fileName : "\(fileName).txt"
                    onCreate(finalFileName, content)
                }
                .buttonStyle(.borderedProminent)
                .disabled(fileName.isEmpty || content.isEmpty)
            }
            .padding()
        }
        .frame(width: 600, height: 500)
    }
}
