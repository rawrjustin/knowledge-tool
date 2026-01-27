import SwiftUI

struct CharacterCreationWizard: View {
    @State private var viewModel: CharacterCreationViewModel
    let onComplete: (Character) -> Void
    let onCancel: () -> Void

    init(
        localRepository: LocalCharacterRepository,
        apiKeyManager: APIKeyManager,
        onComplete: @escaping (Character) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self._viewModel = State(initialValue: CharacterCreationViewModel(
            localRepository: localRepository,
            apiKeyManager: apiKeyManager
        ))
        self.onComplete = onComplete
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Create New Character")
                    .font(.title.bold())

                Spacer()

                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            // Wizard content
            Group {
                switch viewModel.currentStep {
                case .pathSelection:
                    PathSelectionView(viewModel: viewModel)

                case .wikipediaInput:
                    WikipediaInputView(viewModel: viewModel)

                case .wikipediaPreview:
                    WikipediaPreviewView(viewModel: viewModel)

                case .originalInput:
                    OriginalInputView(viewModel: viewModel)

                case .youtubeInput:
                    YouTubeInputView(viewModel: viewModel)

                case .youtubeProcessing:
                    YouTubeProcessingView(viewModel: viewModel)

                case .generating:
                    GeneratingView(viewModel: viewModel)

                case .review:
                    ReviewView(viewModel: viewModel, onComplete: onComplete)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 800, minHeight: 600)
    }
}

// MARK: - Path Selection
struct PathSelectionView: View {
    @Bindable var viewModel: CharacterCreationViewModel

    var body: some View {
        VStack(spacing: 40) {
            Spacer()

            VStack(spacing: 16) {
                Image(systemName: "person.badge.plus")
                    .font(.system(size: 72))
                    .foregroundStyle(.blue)

                Text("How would you like to create this character?")
                    .font(.title2)
            }

            HStack(spacing: 24) {
                // Wikipedia path
                Button {
                    viewModel.selectPath(.wikipedia)
                } label: {
                    VStack(spacing: 12) {
                        Image(systemName: "globe")
                            .font(.system(size: 48))
                            .foregroundStyle(.blue)

                        Text("From Wikipedia")
                            .font(.headline)

                        Text("Create from an existing\ncharacter or celebrity")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(width: 200, height: 180)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(12)
                }
                .buttonStyle(.plain)

                // YouTube path
                Button {
                    viewModel.selectPath(.youtube)
                } label: {
                    VStack(spacing: 12) {
                        Image(systemName: "play.rectangle.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(.red)

                        Text("From YouTube")
                            .font(.headline)

                        Text("Create from video\ninterviews & content")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(width: 200, height: 180)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(12)
                }
                .buttonStyle(.plain)

                // Original path
                Button {
                    viewModel.selectPath(.original)
                } label: {
                    VStack(spacing: 12) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 48))
                            .foregroundStyle(.purple)

                        Text("Original Character")
                            .font(.headline)

                        Text("Start from scratch with\nAI creative expansion")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(width: 200, height: 180)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(12)
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
        .padding()
    }
}

// MARK: - Wikipedia Input
struct WikipediaInputView: View {
    @Bindable var viewModel: CharacterCreationViewModel

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 24) {
                Image(systemName: "globe")
                    .font(.system(size: 64))
                    .foregroundStyle(.blue)

                Text("Enter Wikipedia URL")
                    .font(.title2.bold())

                VStack(alignment: .leading, spacing: 12) {
                    TextField("https://en.wikipedia.org/wiki/...", text: $viewModel.wikipediaURL)
                        .textFieldStyle(.roundedBorder)
                        .font(.body)

                    Text("Paste the Wikipedia URL for the character or celebrity")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: 500)

                if let error = viewModel.error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                HStack(spacing: 12) {
                    Button("Back") {
                        viewModel.goBack()
                    }

                    Button("Preview Character") {
                        Task {
                            await viewModel.fetchWikipediaPreview()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.wikipediaURL.isEmpty)
                }
            }

            Spacer()
        }
        .padding()
    }
}

// MARK: - Wikipedia Preview
struct WikipediaPreviewView: View {
    @Bindable var viewModel: CharacterCreationViewModel

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 24) {
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.blue)

                if let characterName = viewModel.previewCharacterName {
                    Text(characterName)
                        .font(.title.bold())
                }

                if let snippet = viewModel.previewSnippet {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Preview")
                            .font(.headline)
                            .foregroundStyle(.secondary)

                        ScrollView {
                            Text(snippet)
                                .font(.body)
                                .foregroundStyle(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(height: 200)
                        .padding()
                        .background(Color(nsColor: .controlBackgroundColor))
                        .cornerRadius(8)
                    }
                    .frame(maxWidth: 500)
                }

                Text("This character will be generated using the ASP-1 template")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                // Research info
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    Text("Web research typically takes 30-60 seconds")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)

                if let error = viewModel.error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                HStack(spacing: 12) {
                    Button("Back") {
                        viewModel.goBackFromPreview()
                    }

                    Button("Generate Character") {
                        Task {
                            await viewModel.generateFromWikipedia()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            Spacer()
        }
        .padding()
    }
}

// MARK: - Original Input
struct OriginalInputView: View {
    @Bindable var viewModel: CharacterCreationViewModel

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 24) {
                Image(systemName: "sparkles")
                    .font(.system(size: 64))
                    .foregroundStyle(.purple)

                Text("Describe Your Character")
                    .font(.title2.bold())

                VStack(alignment: .leading, spacing: 12) {
                    TextEditor(text: $viewModel.originalDescription)
                        .font(.body)
                        .frame(height: 200)
                        .border(Color(nsColor: .separatorColor))

                    Text("Describe the character in a few sentences. AI will creatively expand this into a full persona.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: 500)

                // Research info
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    Text("For real people, web research takes 30-60 seconds")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)

                if let error = viewModel.error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                HStack(spacing: 12) {
                    Button("Back") {
                        viewModel.goBack()
                    }

                    Button("Generate Character") {
                        Task {
                            await viewModel.generateOriginal()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.originalDescription.isEmpty)
                }
            }

            Spacer()
        }
        .padding()
    }
}

// MARK: - YouTube Input
struct YouTubeInputView: View {
    @Bindable var viewModel: CharacterCreationViewModel
    @FocusState private var focusedFieldIndex: Int?
    @State private var showingErrorAlert = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 24) {
                Image(systemName: "play.rectangle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.red)

                Text("Enter YouTube Video URLs")
                    .font(.title2.bold())

                Text("Add videos featuring the character (interviews, podcasts, etc.)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 16) {
                    // Character name override (optional)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Character Name (optional)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        TextField("Auto-detected from videos if left empty", text: $viewModel.youtubeCharacterName)
                            .textFieldStyle(.roundedBorder)
                    }

                    Divider()

                    // YouTube URLs
                    HStack {
                        Text("Video URLs")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Spacer()

                        Button {
                            viewModel.addYouTubeURL()
                            // Focus the newly added field
                            focusedFieldIndex = viewModel.youtubeURLs.count - 1
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "plus.circle.fill")
                                Text("Add Video")
                            }
                            .font(.subheadline)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.blue)
                    }

                    VStack(spacing: 8) {
                        ForEach(viewModel.youtubeURLs.indices, id: \.self) { index in
                            HStack(spacing: 8) {
                                Text("\(index + 1).")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .frame(width: 24, alignment: .trailing)

                                TextField("https://youtube.com/watch?v=...", text: $viewModel.youtubeURLs[index])
                                    .textFieldStyle(.roundedBorder)
                                    .focused($focusedFieldIndex, equals: index)

                                Button {
                                    viewModel.removeYouTubeURL(at: index)
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundStyle(viewModel.youtubeURLs.count > 1 ? .red : .gray.opacity(0.3))
                                }
                                .buttonStyle(.plain)
                                .disabled(viewModel.youtubeURLs.count <= 1)
                            }
                        }
                    }
                }
                .frame(maxWidth: 600)

                // Research info
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    Text("Web research typically takes 30-60 seconds after video processing")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)

                HStack(spacing: 12) {
                    Button("Back") {
                        viewModel.goBack()
                    }

                    Button("Process Videos") {
                        Task {
                            await viewModel.processYouTubeVideos()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.youtubeURLs.allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty })
                }
            }

            Spacer()
        }
        .padding()
        .onChange(of: viewModel.error) { _, newError in
            if let error = newError, !error.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                showingErrorAlert = true
            }
        }
        .alert("Error", isPresented: $showingErrorAlert) {
            Button("Copy Error") {
                if let error = viewModel.error {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(error, forType: .string)
                }
            }
            Button("OK", role: .cancel) {
                viewModel.error = nil
            }
        } message: {
            Text(viewModel.error ?? "An unknown error occurred")
        }
    }
}

// MARK: - YouTube Processing
struct YouTubeProcessingView: View {
    @Bindable var viewModel: CharacterCreationViewModel
    @State private var showingErrorAlert = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 16) {
                Image(systemName: "waveform")
                    .font(.system(size: 64))
                    .foregroundStyle(.red)
                    .symbolEffect(.variableColor.iterative.reversing)

                Text("Processing Videos")
                    .font(.title2.bold())

                if let detectedName = viewModel.detectedCharacterName {
                    Text("Detected: \(detectedName)")
                        .font(.headline)
                        .foregroundStyle(.blue)
                }
            }

            // Video processing status
            ScrollView {
                VStack(spacing: 16) {
                    ForEach(viewModel.youtubeProcessingStatus.values.sorted(by: { $0.id < $1.id })) { status in
                        VideoProcessingStatusRow(status: status)
                    }
                }
                .padding()
            }
            .frame(maxWidth: 600, maxHeight: 350)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(12)

            // Summary
            if !viewModel.processedTranscripts.isEmpty {
                HStack(spacing: 24) {
                    VStack {
                        Text("\(viewModel.processedTranscripts.count)")
                            .font(.title.bold())
                            .foregroundStyle(.green)
                        Text("Completed")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    VStack {
                        let failed = viewModel.youtubeProcessingStatus.values.filter { $0.state.isFailed }.count
                        Text("\(failed)")
                            .font(.title.bold())
                            .foregroundStyle(failed > 0 ? .red : .secondary)
                        Text("Failed")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Show error inline if present (in addition to alert)
            if let error = viewModel.error {
                VStack(spacing: 8) {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        Text("Generation Failed")
                            .font(.headline)
                            .foregroundStyle(.red)
                    }
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 500)

                    Button("Go Back") {
                        viewModel.goBackFromYouTubeProcessing()
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
                .background(Color.red.opacity(0.1))
                .cornerRadius(8)
            }

            Spacer()
        }
        .padding()
        .onChange(of: viewModel.error) { _, newError in
            if let error = newError, !error.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                showingErrorAlert = true
            }
        }
        .alert("Error", isPresented: $showingErrorAlert) {
            Button("Copy Error") {
                if let error = viewModel.error {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(error, forType: .string)
                }
            }
            Button("OK", role: .cancel) {
                viewModel.error = nil
            }
        } message: {
            Text(viewModel.error ?? "An unknown error occurred")
        }
    }
}

// MARK: - Video Processing Status Row
struct VideoProcessingStatusRow: View {
    let status: CharacterCreationViewModel.YouTubeVideoStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                // Status icon
                Group {
                    switch status.state {
                    case .pending:
                        Image(systemName: "clock")
                            .foregroundStyle(.secondary)
                    case .downloading, .transcribing, .identifying, .extractingDialogue, .generatingKnowledge:
                        ProgressView()
                            .scaleEffect(0.7)
                    case .completed:
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    case .failed:
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.red)
                    }
                }
                .frame(width: 24)

                VStack(alignment: .leading, spacing: 4) {
                    if let title = status.videoTitle {
                        Text(title)
                            .font(.subheadline)
                            .lineLimit(1)
                    } else {
                        Text(status.url)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    HStack(spacing: 8) {
                        if case .failed = status.state {
                            Text("Failed")
                                .font(.caption)
                                .foregroundStyle(.red)
                        } else {
                            Text(status.state.displayText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if let name = status.intervieweeName {
                            Text("Speaker: \(name)")
                                .font(.caption)
                                .foregroundStyle(.blue)
                        }
                    }
                }

                Spacer()
            }

            // Show full error message if failed
            if case .failed(let errorMessage) = status.state {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(4)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color(nsColor: .windowBackgroundColor))
        .cornerRadius(8)
    }
}

// MARK: - Generating View
struct GeneratingView: View {
    @Bindable var viewModel: CharacterCreationViewModel

    // Deduplicate and get unique logs (filter out repetitive polling messages)
    private var uniqueLogs: [String] {
        var seen = Set<String>()
        var result: [String] = []

        for log in viewModel.progressLogs {
            // Normalize polling messages to avoid duplicates
            let normalizedLog: String
            if log.contains("Research in progress") {
                normalizedLog = "Research in progress..."
            } else if log.contains("Processing...") {
                normalizedLog = "Processing..."
            } else {
                normalizedLog = log
            }

            if !seen.contains(normalizedLog) {
                seen.insert(normalizedLog)
                result.append(log)  // Keep the original log text
            } else if log.contains("Research in progress") || log.contains("Processing...") {
                // Update the last occurrence with the latest time
                if let lastIndex = result.lastIndex(where: { $0.contains("Research in progress") || $0.contains("Processing...") }) {
                    result[lastIndex] = log
                }
            }
        }
        return result
    }

    // Get the current status message (last meaningful log)
    private var currentStatus: String {
        if let last = viewModel.progressLogs.last {
            return last
        }
        return "Starting..."
    }

    // Check if we're in a polling state
    private var isPolling: Bool {
        currentStatus.contains("Research in progress") || currentStatus.contains("Processing...")
    }

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // Animated icon
            VStack(spacing: 20) {
                ZStack {
                    // Outer pulsing ring
                    Circle()
                        .stroke(Color.blue.opacity(0.3), lineWidth: 3)
                        .frame(width: 100, height: 100)
                        .scaleEffect(isPolling ? 1.2 : 1.0)
                        .opacity(isPolling ? 0.0 : 0.5)
                        .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: false), value: isPolling)

                    // Inner circle with icon
                    Circle()
                        .fill(Color.blue.opacity(0.1))
                        .frame(width: 80, height: 80)

                    Image(systemName: "sparkles")
                        .font(.system(size: 36))
                        .foregroundStyle(.blue)
                        .symbolEffect(.pulse.wholeSymbol, options: .repeating)
                }

                Text("Generating Character...")
                    .font(.title2.bold())

                // Current status prominently displayed
                Text(currentStatus)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
                    .animation(.easeInOut(duration: 0.3), value: currentStatus)
            }

            // Compact log view - shows unique steps only
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Activity Log")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(viewModel.progressLogs.count) events")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                Divider()

                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(uniqueLogs.enumerated()), id: \.offset) { index, log in
                                let isCurrentItem = index == uniqueLogs.count - 1
                                HStack(alignment: .top, spacing: 8) {
                                    // Status indicator - spinner for current item, checkmark for completed
                                    if isCurrentItem {
                                        ProgressView()
                                            .scaleEffect(0.5)
                                            .frame(width: 12, height: 12)
                                            .padding(.top, 2)
                                    } else {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 10))
                                            .foregroundStyle(.green)
                                            .frame(width: 12, height: 12)
                                            .padding(.top, 3)
                                    }

                                    Text(log)
                                        .font(.caption)
                                        .foregroundStyle(isCurrentItem ? .primary : .secondary)
                                }
                                .id(index)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 4)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    .onChange(of: viewModel.progressLogs.count) { _, _ in
                        withAnimation {
                            proxy.scrollTo(uniqueLogs.count - 1, anchor: .bottom)
                        }
                    }
                }
            }
            .frame(maxWidth: 500, maxHeight: 200)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            )

            Spacer()
        }
        .padding()
    }
}

// MARK: - Review View
struct ReviewView: View {
    @Bindable var viewModel: CharacterCreationViewModel
    let onComplete: (Character) -> Void

    @State private var editedContent: String

    init(viewModel: CharacterCreationViewModel, onComplete: @escaping (Character) -> Void) {
        self.viewModel = viewModel
        self.onComplete = onComplete
        self._editedContent = State(initialValue: viewModel.generatedContent)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header with actions
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Review Character")
                        .font(.title2.bold())

                    Text("\(editedContent.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count) words")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 12) {
                    Button("Discard") {
                        viewModel.discard()
                    }

                    Button("Save Character") {
                        Task {
                            await viewModel.saveCharacter(content: editedContent)
                            if let character = viewModel.savedCharacter {
                                onComplete(character)
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()

            Divider()

            // Content editor
            TextEditor(text: $editedContent)
                .font(.system(.body, design: .monospaced))
                .padding()
        }
    }
}
