import SwiftUI

struct KnowledgeBaseView: View {
    @State private var viewModel: KnowledgeBaseViewModel
    @State private var showingNewFileSheet = false
    @State private var showingDeleteConfirmation = false
    @State private var fileToDelete: KnowledgeFile?

    // RAG state
    @State private var isProcessingRAG = false
    @State private var isUploadingToRAG = false
    @State private var isSyncingWithPinecone = false
    @State private var ragProgress: String = ""
    @State private var ragError: String?
    @State private var ragSuccess: String?
    @State private var showNamespaceInput = false
    @State private var pineconeNamespace: String = ""

    // New sheet states
    @State private var showYouTubeSheet = false
    @State private var showFreeTextSheet = false

    // Upload status tracking
    @State private var uploadedPineconeIds: Set<String> = []
    @State private var hasSyncedWithPinecone = false

    let apiKeyManager: APIKeyManager

    init(character: Character, repository: CombinedCharacterRepository, apiKeyManager: APIKeyManager) {
        self._viewModel = State(initialValue: KnowledgeBaseViewModel(
            character: character,
            repository: repository
        ))
        self.apiKeyManager = apiKeyManager
    }

    var body: some View {
        HSplitView {
            // Left sidebar - file list
            VStack(spacing: 0) {
                // Header with stats
                VStack(alignment: .leading, spacing: 8) {
                    Text("Knowledge Base")
                        .font(.headline)

                    HStack(spacing: 16) {
                        HStack(spacing: 4) {
                            Text("\(viewModel.fileCount)")
                                .font(.title3.bold())
                            Text("Files")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        HStack(spacing: 4) {
                            Text("\(viewModel.totalWordCount)")
                                .font(.title3.bold())
                            Text("Words")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Divider()

                    // RAG Actions
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "brain.head.profile")
                                .foregroundStyle(.purple)
                                .font(.caption)
                            Text("RAG")
                                .font(.caption.bold())
                        }

                        // Status messages
                        if let error = ragError {
                            Text(error)
                                .font(.caption2)
                                .foregroundStyle(.red)
                                .lineLimit(2)
                        }

                        if let success = ragSuccess {
                            Text(success)
                                .font(.caption2)
                                .foregroundStyle(.green)
                        }

                        if !ragProgress.isEmpty {
                            HStack(spacing: 4) {
                                ProgressView()
                                    .scaleEffect(0.5)
                                Text(ragProgress)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        // First row: Generate memories
                        HStack(spacing: 8) {
                            Button {
                                showYouTubeSheet = true
                            } label: {
                                Label("YouTube", systemImage: "play.rectangle")
                                    .font(.caption)
                            }
                            .buttonStyle(.modernSecondary)
                            .controlSize(.small)
                            .disabled(isProcessingRAG || isUploadingToRAG)
                            .help("Generate memories from YouTube video")

                            Button {
                                showFreeTextSheet = true
                            } label: {
                                Label("Text", systemImage: "doc.text")
                                    .font(.caption)
                            }
                            .buttonStyle(.modernSecondary)
                            .controlSize(.small)
                            .disabled(isProcessingRAG || isUploadingToRAG)
                            .help("Generate memories from free-form text")
                        }

                        // Second row: Sync and Upload
                        HStack(spacing: 8) {
                            Button {
                                Task {
                                    await syncWithPinecone()
                                }
                            } label: {
                                Label("Sync", systemImage: "arrow.triangle.2.circlepath")
                                    .font(.caption)
                            }
                            .buttonStyle(.modernSecondary)
                            .controlSize(.small)
                            .disabled(isProcessingRAG || isUploadingToRAG || isSyncingWithPinecone || pineconeNamespace.isEmpty)
                            .help("Sync with Pinecone to check upload status")

                            Button {
                                showNamespaceInput = true
                            } label: {
                                Label("Upload", systemImage: "icloud.and.arrow.up")
                                    .font(.caption)
                            }
                            .buttonStyle(.modernPrimary)
                            .controlSize(.small)
                            .disabled(isProcessingRAG || isUploadingToRAG || !hasUploadableContent)
                            .help("Upload to Pinecone")
                        }
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.regularMaterial)

                Divider()

                // Search bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)

                    TextField("Search knowledge...", text: $viewModel.searchText)
                        .textFieldStyle(.plain)
                }
                .padding(8)
                .background(.regularMaterial)
                .cornerRadius(8)
                .padding(10)

                // File list
                List(viewModel.filteredFiles, selection: $viewModel.selectedFile) { file in
                    KnowledgeFileRow(
                        file: file,
                        isSelected: viewModel.selectedFile?.id == file.id,
                        uploadStatus: uploadStatusForFile(file)
                    )
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
                .listStyle(.inset)
                .scrollContentBackground(.hidden)

                Divider()

                // Bottom toolbar
                HStack {
                    Button {
                        showingNewFileSheet = true
                    } label: {
                        Label("New File", systemImage: "plus")
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)

                    Spacer()

                    Button {
                        Task {
                            await viewModel.refresh()
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .help("Refresh")
                    .disabled(viewModel.isLoading)
                }
                .padding(10)
                .background(.bar)
            }
            .frame(minWidth: 200, idealWidth: 250, maxWidth: 300)
            .background(.regularMaterial)

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
                EmptyStateView(
                    icon: "doc.text",
                    title: "Select a Knowledge File",
                    message: "Select a file from the list to view or edit its content"
                )
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
        .sheet(isPresented: $showNamespaceInput) {
            PineconeUploadSheet(
                characterName: viewModel.character.name,
                namespace: $pineconeNamespace,
                onUpload: {
                    showNamespaceInput = false
                    Task {
                        await uploadToRAG()
                    }
                },
                onCancel: {
                    showNamespaceInput = false
                }
            )
        }
        .sheet(isPresented: $showYouTubeSheet) {
            YouTubeInputSheet(
                onProcess: { url in
                    showYouTubeSheet = false
                    Task {
                        await processYouTubeVideo(url: url)
                    }
                },
                onCancel: {
                    showYouTubeSheet = false
                }
            )
        }
        .sheet(isPresented: $showFreeTextSheet) {
            FreeTextInputSheet(
                onGenerate: { text, sourceLabel in
                    showFreeTextSheet = false
                    Task {
                        await generateMemoriesFromText(text: text, sourceLabel: sourceLabel)
                    }
                },
                onCancel: {
                    showFreeTextSheet = false
                }
            )
        }
    }

    // MARK: - RAG Helpers

    private var hasUploadableContent: Bool {
        viewModel.character.knowledgeFiles.contains { $0.fileName.hasSuffix(".jsonl") }
    }

    private func uploadStatusForFile(_ file: KnowledgeFile) -> KnowledgeFileRow.UploadStatus {
        guard file.fileName.hasSuffix(".jsonl") else {
            return .notApplicable
        }

        guard hasSyncedWithPinecone else {
            return .notSynced
        }

        // Check if any entries from this file are in Pinecone
        // The upload creates IDs in format "{namespace}_{index}"
        // We can check if the namespace prefix exists in uploadedPineconeIds
        if uploadedPineconeIds.isEmpty {
            return .notUploaded
        }

        // If we have synced and there are IDs, assume uploaded
        // A more sophisticated check would parse the JSONL and check each ID
        return .uploaded
    }

    private func syncWithPinecone() async {
        guard let pineconeKey = apiKeyManager.getAPIKey(for: .pinecone) else {
            ragError = "Pinecone API key not configured"
            return
        }

        guard let openAIKey = apiKeyManager.getAPIKey(for: .openAI) else {
            ragError = "OpenAI API key not configured"
            return
        }

        guard !pineconeNamespace.isEmpty else {
            ragError = "Enter namespace first via Upload"
            return
        }

        isSyncingWithPinecone = true
        ragError = nil
        ragSuccess = nil
        ragProgress = "Syncing with Pinecone..."

        do {
            let service = PineconeService(
                apiKey: pineconeKey,
                openAIApiKey: openAIKey,
                indexName: apiKeyManager.pineconeIndexName
            )

            let ids = try await service.fetchAllMemoryIds(
                namespace: pineconeNamespace,
                onProgress: { message in
                    Task { @MainActor in
                        ragProgress = message
                    }
                }
            )

            uploadedPineconeIds = ids
            hasSyncedWithPinecone = true
            ragProgress = ""
            ragSuccess = "Synced: \(ids.count) vectors"

        } catch {
            ragError = error.localizedDescription
            ragProgress = ""
        }

        isSyncingWithPinecone = false
    }

    private func processYouTubeVideo(url: String) async {
        guard let assemblyAIKey = apiKeyManager.getAPIKey(for: .assemblyAI) else {
            ragError = "AssemblyAI API key not configured"
            return
        }

        guard let openAIKey = apiKeyManager.getAPIKey(for: .openAI) else {
            ragError = "OpenAI API key not configured"
            return
        }

        isProcessingRAG = true
        ragError = nil
        ragSuccess = nil

        var audioURL: URL?
        let videoService = VideoService()

        do {
            // Step 1: Download video and extract audio
            ragProgress = "Downloading video..."
            let result = try await videoService.downloadAndExtractAudio(from: url)
            audioURL = result.audioURL
            let videoInfo = result.videoInfo

            // Step 2: Transcribe audio
            ragProgress = "Transcribing audio..."
            let assemblyAI = AssemblyAIService(apiKey: assemblyAIKey)
            var transcriptResult = try await assemblyAI.transcribeAudio(fileURL: audioURL!)

            // Step 2.5: Identify and relabel interviewee
            var intervieweeName: String? = nil
            if let speakerLabels = transcriptResult.speakerLabels, !speakerLabels.isEmpty {
                ragProgress = "Identifying interviewee..."
                let transcriptPreview = String(transcriptResult.text.prefix(2000))
                let openAI = OpenAIService(apiKey: openAIKey)

                if let identifiedName = try? await openAI.identifyInterviewee(
                    title: videoInfo.title,
                    description: videoInfo.description,
                    transcriptPreview: transcriptPreview
                ) {
                    intervieweeName = identifiedName
                    let relabeledSpeakerLabels = relabelSpeakers(
                        speakerLabels: speakerLabels,
                        intervieweeName: identifiedName
                    )
                    transcriptResult = Transcript(
                        id: transcriptResult.id,
                        text: transcriptResult.text,
                        speakerLabels: relabeledSpeakerLabels,
                        createdAt: transcriptResult.createdAt,
                        sourceURL: url,
                        title: videoInfo.title
                    )
                }
            }

            // Step 3: Generate structured knowledge base JSONL
            ragProgress = "Generating knowledge base..."
            let openAI = OpenAIService(apiKey: openAIKey)
            let characterName = intervieweeName ?? viewModel.character.name
            let jsonlContent = try await openAI.generateStructuredKnowledgeBase(
                characterName: characterName,
                fullTranscript: transcriptResult.text,
                speakerLabels: transcriptResult.speakerLabels,
                videoURL: url,
                videoTitle: videoInfo.title
            )

            // Cleanup audio file
            if let audioURL = audioURL {
                await videoService.cleanup(audioURL: audioURL)
            }

            // Step 4: Save JSONL file
            ragProgress = "Saving..."
            let sanitizedTitle = videoInfo.title
                .replacingOccurrences(of: "[^a-zA-Z0-9]", with: "_", options: .regularExpression)
                .prefix(50)
            let fileName = "\(sanitizedTitle)_kb.jsonl"

            let success = await viewModel.createKnowledgeFile(
                fileName: String(fileName),
                content: jsonlContent
            )

            ragProgress = ""
            if success {
                let entryCount = jsonlContent.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count
                ragSuccess = "Created \(entryCount) entries"
            } else {
                ragError = "Failed to save"
            }

        } catch {
            if let audioURL = audioURL {
                await videoService.cleanup(audioURL: audioURL)
            }
            ragError = error.localizedDescription
            ragProgress = ""
        }

        isProcessingRAG = false
    }

    private func generateMemoriesFromText(text: String, sourceLabel: String) async {
        guard let openAIKey = apiKeyManager.getAPIKey(for: .openAI) else {
            ragError = "OpenAI API key not configured"
            return
        }

        isProcessingRAG = true
        ragError = nil
        ragSuccess = nil
        ragProgress = "Generating memories..."

        do {
            let service = MemoryGenerationService(openAIApiKey: openAIKey)
            let memories = try await service.generateMemoriesFromText(
                characterName: viewModel.character.name,
                text: text,
                sourceLabel: sourceLabel,
                onProgress: { message in
                    Task { @MainActor in
                        ragProgress = message
                    }
                }
            )

            let jsonlContent = await service.memoriesToJSONL(memories)

            ragProgress = "Saving..."
            let sanitizedLabel = sourceLabel
                .replacingOccurrences(of: "[^a-zA-Z0-9]", with: "_", options: .regularExpression)
                .prefix(50)
            let fileName = "\(sanitizedLabel)_memories.jsonl"

            let success = await viewModel.createKnowledgeFile(
                fileName: String(fileName),
                content: jsonlContent
            )

            ragProgress = ""
            if success {
                ragSuccess = "\(memories.count) memories"
            } else {
                ragError = "Failed to save"
            }

        } catch {
            ragError = error.localizedDescription
            ragProgress = ""
        }

        isProcessingRAG = false
    }

    private func relabelSpeakers(speakerLabels: [SpeakerUtterance], intervieweeName: String) -> [SpeakerUtterance] {
        var speakerTimes: [String: TimeInterval] = [:]
        for utterance in speakerLabels {
            let duration = utterance.end - utterance.start
            speakerTimes[utterance.speaker, default: 0] += duration
        }

        guard let primarySpeaker = speakerTimes.max(by: { $0.value < $1.value })?.key else {
            return speakerLabels
        }

        return speakerLabels.map { utterance in
            let newSpeaker = utterance.speaker == primarySpeaker ? intervieweeName : utterance.speaker
            return SpeakerUtterance(
                id: utterance.id,
                speaker: newSpeaker,
                text: utterance.text,
                start: utterance.start,
                end: utterance.end
            )
        }
    }

    private func uploadToRAG() async {
        guard let pineconeKey = apiKeyManager.getAPIKey(for: .pinecone) else {
            ragError = "Pinecone API key not configured"
            return
        }

        guard let openAIKey = apiKeyManager.getAPIKey(for: .openAI) else {
            ragError = "OpenAI API key not configured"
            return
        }

        guard !pineconeNamespace.isEmpty else {
            ragError = "Enter namespace"
            return
        }

        isUploadingToRAG = true
        ragError = nil
        ragSuccess = nil
        ragProgress = "Preparing..."

        do {
            let documents = try PineconeService.parseCharacterKnowledge(knowledgeFiles: viewModel.character.knowledgeFiles)

            guard !documents.isEmpty else {
                ragError = "No JSONL files"
                isUploadingToRAG = false
                ragProgress = ""
                return
            }

            let service = PineconeService(
                apiKey: pineconeKey,
                openAIApiKey: openAIKey,
                indexName: apiKeyManager.pineconeIndexName
            )

            let result = try await service.uploadKnowledge(
                documents: documents,
                namespace: pineconeNamespace,
                clearExisting: true,
                onProgress: { message in
                    Task { @MainActor in
                        ragProgress = message
                    }
                }
            )

            ragProgress = ""
            ragSuccess = "\(result.documentsUploaded) uploaded"

        } catch {
            ragError = error.localizedDescription
            ragProgress = ""
        }

        isUploadingToRAG = false
    }
}

// MARK: - Pinecone Upload Sheet
struct PineconeUploadSheet: View {
    let characterName: String
    @Binding var namespace: String
    let onUpload: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Image(systemName: "icloud.and.arrow.up")
                    .font(.title2)
                    .foregroundStyle(.blue)
                Text("Upload to Pinecone")
                    .font(.title2.bold())
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Namespace (Character ID)")
                    .font(.headline)

                TextField("CHAR_xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx", text: $namespace)
                    .polishedInput()
                    .font(.system(.body, design: .monospaced))

                Text("Enter the Character ID from your backend system.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Upload") {
                    onUpload()
                }
                .buttonStyle(.modernPrimary)
                .keyboardShortcut(.defaultAction)
                .disabled(namespace.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 450)
    }
}

// MARK: - YouTube Input Sheet
struct YouTubeInputSheet: View {
    @State private var youtubeURL = ""
    let onProcess: (String) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Image(systemName: "play.rectangle")
                    .font(.title2)
                    .foregroundStyle(.red)
                Text("From YouTube")
                    .font(.title2.bold())
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("YouTube URL")
                    .font(.headline)

                TextField("https://www.youtube.com/watch?v=...", text: $youtubeURL)
                    .polishedInput()
                    .font(.system(.body, design: .monospaced))

                Text("Enter a YouTube video URL to download, transcribe, and generate a knowledge base.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Process") {
                    onProcess(youtubeURL)
                }
                .buttonStyle(.modernPrimary)
                .keyboardShortcut(.defaultAction)
                .disabled(youtubeURL.isEmpty || !isValidYouTubeURL)
            }
        }
        .padding(24)
        .frame(width: 500)
    }

    private var isValidYouTubeURL: Bool {
        youtubeURL.contains("youtube.com") || youtubeURL.contains("youtu.be")
    }
}

// MARK: - Free Text Input Sheet
struct FreeTextInputSheet: View {
    @State private var textContent = ""
    @State private var sourceLabel = ""
    let onGenerate: (String, String) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Image(systemName: "doc.text")
                    .font(.title2)
                    .foregroundStyle(.blue)
                Text("From Text")
                    .font(.title2.bold())
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Source Label")
                    .font(.headline)

                TextField("e.g., interview_2024, article_notes", text: $sourceLabel)
                    .polishedInput()

                Text("A short identifier for the source of this content.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Text Content")
                    .font(.headline)

                TextEditor(text: $textContent)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .background(Color(nsColor: .textBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                            .stroke(DesignSystem.Colors.inputBorder, lineWidth: 1)
                    )
                    .frame(minHeight: 200)

                Text("Paste any text content (interview transcript, article, notes, etc.) to generate memories.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Generate") {
                    onGenerate(textContent, sourceLabel)
                }
                .buttonStyle(.modernPrimary)
                .keyboardShortcut(.defaultAction)
                .disabled(textContent.isEmpty || sourceLabel.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 550, height: 500)
    }
}

// MARK: - Knowledge File Row
struct KnowledgeFileRow: View {
    let file: KnowledgeFile
    let isSelected: Bool
    let uploadStatus: UploadStatus

    enum UploadStatus {
        case notApplicable  // Not a JSONL file
        case notSynced      // Haven't checked Pinecone yet
        case uploaded       // All entries in Pinecone
        case notUploaded    // No entries in Pinecone
    }

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(file.displayName)
                    .font(.body)
                    .lineLimit(1)
                    .foregroundStyle(isSelected ? .white : .primary)

                HStack(spacing: 8) {
                    Text("\(file.wordCount) words")
                        .font(.caption)
                        .foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary)

                    Text("•")
                        .font(.caption)
                        .foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary)

                    Text(file.modifiedAt, format: .relative(presentation: .named))
                        .font(.caption)
                        .foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary)
                }
            }

            Spacer()

            // Upload status indicator for JSONL files
            if file.fileName.hasSuffix(".jsonl") {
                uploadStatusIndicator
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var uploadStatusIndicator: some View {
        switch uploadStatus {
        case .notApplicable:
            EmptyView()
        case .notSynced:
            Circle()
                .fill(Color.gray.opacity(0.5))
                .frame(width: 8, height: 8)
                .help("Not synced with Pinecone")
        case .uploaded:
            Circle()
                .fill(Color.green)
                .frame(width: 8, height: 8)
                .help("Uploaded to Pinecone")
        case .notUploaded:
            Circle()
                .fill(Color.orange)
                .frame(width: 8, height: 8)
                .help("Not uploaded to Pinecone")
        }
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
                        .keyboardShortcut(.cancelAction)

                        Button("Save") {
                            var updatedFile = file
                            updatedFile.content = editedContent
                            updatedFile.modifiedAt = Date()
                            onSave(updatedFile)
                            file = updatedFile
                            isEditing = false
                            hasUnsavedChanges = false
                        }
                        .buttonStyle(.modernPrimary)
                        .keyboardShortcut("s", modifiers: .command)
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
            .background(.regularMaterial)
            .overlay(
                Rectangle()
                    .frame(height: 1)
                    .foregroundStyle(.separator),
                alignment: .bottom
            )

            // Content
            if isEditing {
                TextEditor(text: $editedContent)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .background(Color(nsColor: .textBackgroundColor))
                    .onChange(of: editedContent) {
                        hasUnsavedChanges = editedContent != file.content
                    }
                    .padding(8)
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
        VStack(spacing: 20) {
            // Header
            Text("New Knowledge File")
                .font(.title2.bold())
                .frame(maxWidth: .infinity, alignment: .leading)

            // Form
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("File Name")
                        .font(.headline)

                    TextField("e.g., interview_summary", text: $fileName)
                        .polishedInput()

                    Text("Will be saved as .txt")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Content")
                        .font(.headline)

                    TextEditor(text: $content)
                        .font(.body)
                        .scrollContentBackground(.hidden)
                        .background(Color(nsColor: .textBackgroundColor))
                        .overlay(
                        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                            .stroke(DesignSystem.Colors.inputBorder, lineWidth: 1)
                    )
                        .frame(minHeight: 200)
                }
            }

            // Footer
            HStack {
                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Create") {
                    let finalFileName = fileName.hasSuffix(".txt") ? fileName : "\(fileName).txt"
                    onCreate(finalFileName, content)
                }
                .buttonStyle(.modernPrimary)
                .disabled(fileName.isEmpty || content.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 500, height: 500)
    }
}
