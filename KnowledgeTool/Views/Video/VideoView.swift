import SwiftUI
import UniformTypeIdentifiers

struct VideoView: View {
    @State var viewModel: VideoViewModel
    @State private var showingToast = false
    @State private var toastMessage = ""
    @State private var toastStyle: ToastStyle = .success

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                HeaderView(
                    title: "Video Transcription",
                    subtitle: "Transcribe and summarize videos from URLs or file uploads"
                )

                // Important Notice
                HStack(spacing: 12) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(.blue)
                        .font(.title3)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("⚠️ Designed for Interview Content")
                            .font(.subheadline.bold())

                        Text("This tool works best with interview videos. It will attempt to identify and label the interviewee by name using the video title and description.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
                .padding()
                .background(Color.blue.opacity(0.1))
                .cornerRadius(12)

                // Input Section
                VStack(alignment: .leading, spacing: 16) {
                    Text("Video Source")
                        .font(.headline)

                    // URL Input
                    HStack(spacing: 12) {
                        TextField("Enter video URL (YouTube, Vimeo, etc.)", text: $viewModel.urlInput)
                            .textFieldStyle(.roundedBorder)
                            .disabled(viewModel.processingState.isProcessing)

                        Button {
                            Task {
                                await viewModel.processVideoFromURL()
                            }
                        } label: {
                            Label("Process URL", systemImage: "link")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(viewModel.urlInput.isEmpty || viewModel.processingState.isProcessing)
                    }

                    // OR separator
                    HStack {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.3))
                            .frame(height: 1)

                        Text("OR")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)

                        Rectangle()
                            .fill(Color.secondary.opacity(0.3))
                            .frame(height: 1)
                    }
                    .padding(.vertical, 8)

                    // File Upload
                    FileDropZone(onFileDrop: { url in
                        Task {
                            await viewModel.processVideoFromFile(url)
                        }
                    }, isProcessing: viewModel.processingState.isProcessing)
                }
                .padding()
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(12)

                // Processing State
                if viewModel.processingState.isProcessing {
                    ProcessingView(state: viewModel.processingState)
                }

                // Error Message
                if let errorMessage = viewModel.errorMessage {
                    ErrorBanner(message: errorMessage)
                }

                // Results
                if viewModel.processingState == .completed {
                    ResultsSection(
                        videoInfo: viewModel.videoInfo,
                        transcript: viewModel.transcript,
                        summary: viewModel.summary,
                        onExportTranscript: {
                            if let content = viewModel.exportTranscript() {
                                saveToFile(content: content, filename: "transcript")
                            }
                        },
                        onExportSummary: {
                            if let content = viewModel.exportSummary() {
                                saveToFile(content: content, filename: "summary")
                            }
                        },
                        onReset: {
                            viewModel.reset()
                        },
                        onCopySuccess: { message in
                            showToast(message: message, style: .success)
                        }
                    )
                }
            }
            .padding(24)
        }
        .toast(isShowing: $showingToast, message: toastMessage, style: toastStyle)
    }

    // MARK: - Show Toast
    private func showToast(message: String, style: ToastStyle) {
        toastMessage = message
        toastStyle = style
        withAnimation {
            showingToast = true
        }
    }

    // MARK: - Save to File
    private func saveToFile(content: String, filename: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(filename).txt"
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true

        panel.begin { response in
            if response == .OK, let url = panel.url {
                do {
                    try content.write(to: url, atomically: true, encoding: .utf8)
                    showToast(message: "File saved successfully", style: .success)
                } catch {
                    showToast(message: "Failed to save file: \(error.localizedDescription)", style: .error)
                }
            }
        }
    }
}

// MARK: - File Drop Zone
struct FileDropZone: View {
    let onFileDrop: (URL) -> Void
    let isProcessing: Bool

    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "video.badge.plus")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("Drop video file here or click to browse")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text("Supported formats: MP4, MOV, AVI, MKV, and more")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Button {
                selectVideoFile()
            } label: {
                Label("Choose File", systemImage: "folder")
            }
            .disabled(isProcessing)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 200)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    isTargeted ? Color.accentColor : Color.secondary.opacity(0.3),
                    style: StrokeStyle(lineWidth: 2, dash: [8])
                )
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isTargeted ? Color.accentColor.opacity(0.1) : Color.clear)
                )
        )
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            handleDrop(providers: providers)
        }
    }

    private func selectVideoFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [
            .movie, .video, .mpeg4Movie, .quickTimeMovie, .avi
        ]

        panel.begin { response in
            if response == .OK, let url = panel.url {
                onFileDrop(url)
            }
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else {
                return
            }

            DispatchQueue.main.async {
                onFileDrop(url)
            }
        }

        return true
    }
}

// MARK: - Results Section
struct ResultsSection: View {
    let videoInfo: VideoInfo?
    let transcript: Transcript?
    let summary: Summary?
    let onExportTranscript: () -> Void
    let onExportSummary: () -> Void
    let onReset: () -> Void
    let onCopySuccess: (String) -> Void

    @State private var selectedTab = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Results")
                    .font(.title2.bold())

                Spacer()

                Button {
                    onReset()
                } label: {
                    Label("New", systemImage: "plus.circle.fill")
                }
                .buttonStyle(.bordered)
            }

            // Video Info
            if let videoInfo = videoInfo {
                VideoInfoCard(videoInfo: videoInfo)
            }

            // Tabbed Interface
            VStack(spacing: 0) {
                // Tab Bar
                HStack(spacing: 0) {
                    TabButton(
                        title: "Summary",
                        icon: "doc.text.fill",
                        isSelected: selectedTab == 0
                    ) {
                        selectedTab = 0
                    }

                    TabButton(
                        title: "Dialogue Examples",
                        icon: "quote.bubble.fill",
                        isSelected: selectedTab == 1
                    ) {
                        selectedTab = 1
                    }

                    TabButton(
                        title: "Raw Transcript",
                        icon: "text.quote",
                        isSelected: selectedTab == 2
                    ) {
                        selectedTab = 2
                    }

                    Spacer()
                }
                .background(Color(nsColor: .controlBackgroundColor))

                Divider()

                // Tab Content
                Group {
                    switch selectedTab {
                    case 0:
                        if let summary = summary {
                            SummaryTabContent(summary: summary, onExport: onExportSummary, onCopySuccess: onCopySuccess)
                        }
                    case 1:
                        if let summary = summary,
                           let dialogueExamples = summary.speakerDialogueExamples,
                           !dialogueExamples.isEmpty {
                            DialogueTabContent(dialogueExamples: dialogueExamples, onCopySuccess: onCopySuccess)
                        } else {
                            EmptyTabMessage(message: "No dialogue examples available")
                        }
                    case 2:
                        if let transcript = transcript {
                            TranscriptTabContent(transcript: transcript, onExport: onExportTranscript, onCopySuccess: onCopySuccess)
                        }
                    default:
                        EmptyView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .textBackgroundColor))
            }
            .frame(height: 500)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(12)
        }
    }
}

// MARK: - Tab Button
struct TabButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)

                Text(title)
                    .font(.subheadline)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(isSelected ? Color(nsColor: .textBackgroundColor) : Color.clear)
            .foregroundStyle(isSelected ? .primary : .secondary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Summary Tab Content
struct SummaryTabContent: View {
    let summary: Summary
    let onExport: () -> Void
    let onCopySuccess: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Spacer()

                Button {
                    copyToClipboard(summary.text)
                    onCopySuccess("Summary copied to clipboard")
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)

                Button {
                    onExport()
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
            }
            .padding()

            Divider()

            // Content
            ScrollView {
                Text(summary.text)
                    .textSelection(.enabled)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func copyToClipboard(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }
}

// MARK: - Dialogue Tab Content
struct DialogueTabContent: View {
    let dialogueExamples: [SpeakerDialogueExamples]
    let onCopySuccess: (String) -> Void

    @State private var showingExportToast = false
    @State private var exportToastMessage = ""
    @State private var exportToastStyle: ToastStyle = .success

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Spacer()

                Button {
                    copyAllDialogueExamples()
                    onCopySuccess("Dialogue examples copied to clipboard")
                } label: {
                    Label("Copy All", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)

                Button {
                    exportDialogueExamples()
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
            }
            .padding()

            Divider()

            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(dialogueExamples) { speakerExample in
                        VStack(alignment: .leading, spacing: 8) {
                            // Speaker header
                            HStack {
                                Text(speakerExample.speaker)
                                    .font(.headline)
                                    .foregroundStyle(.primary)

                                Spacer()

                                Text("\(speakerExample.examples.count) examples")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.bottom, 4)

                            // Dialogue examples
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(Array(speakerExample.examples.enumerated()), id: \.offset) { index, example in
                                    HStack(alignment: .top, spacing: 8) {
                                        Text("\(index + 1).")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .frame(width: 20, alignment: .trailing)

                                        Text(example)
                                            .font(.body)
                                            .textSelection(.enabled)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .padding(.vertical, 4)

                                    if index < speakerExample.examples.count - 1 {
                                        Divider()
                                    }
                                }
                            }
                        }
                        .padding()
                        .background(Color(nsColor: .controlBackgroundColor))
                        .cornerRadius(8)
                    }
                }
                .padding()
            }
        }
        .toast(isShowing: $showingExportToast, message: exportToastMessage, style: exportToastStyle)
    }

    private func copyAllDialogueExamples() {
        var output = "=== Characteristic Dialogue Examples ===\n\n"

        for speakerExample in dialogueExamples {
            output += "\(speakerExample.speaker):\n"
            for (index, example) in speakerExample.examples.enumerated() {
                output += "\(index + 1). \(example)\n"
            }
            output += "\n"
        }

        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(output, forType: .string)
        #endif
    }

    private func exportDialogueExamples() {
        var output = "=== Characteristic Dialogue Examples ===\n\n"

        for speakerExample in dialogueExamples {
            output += "\(speakerExample.speaker):\n"
            for (index, example) in speakerExample.examples.enumerated() {
                output += "\(index + 1). \(example)\n"
            }
            output += "\n"
        }

        let panel = NSSavePanel()
        panel.nameFieldStringValue = "dialogue_examples.txt"
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true

        panel.begin { response in
            if response == .OK, let url = panel.url {
                do {
                    try output.write(to: url, atomically: true, encoding: .utf8)
                    exportToastMessage = "File saved successfully"
                    exportToastStyle = .success
                    withAnimation { showingExportToast = true }
                } catch {
                    exportToastMessage = "Failed to save: \(error.localizedDescription)"
                    exportToastStyle = .error
                    withAnimation { showingExportToast = true }
                }
            }
        }
    }
}

// MARK: - Transcript Tab Content
struct TranscriptTabContent: View {
    let transcript: Transcript
    let onExport: () -> Void
    let onCopySuccess: (String) -> Void

    @State private var showingSpeakerLabels = true

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                if transcript.speakerLabels != nil {
                    Toggle("Speaker Labels", isOn: $showingSpeakerLabels)
                        .toggleStyle(.switch)
                }

                Spacer()

                Button {
                    copyTranscript()
                    onCopySuccess("Transcript copied to clipboard")
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)

                Button {
                    onExport()
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
            }
            .padding()

            Divider()

            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if showingSpeakerLabels, let speakerLabels = transcript.speakerLabels {
                        ForEach(speakerLabels) { utterance in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(utterance.speaker)
                                        .font(.caption.bold())
                                        .foregroundStyle(.secondary)

                                    Text(utterance.formattedTimestamp)
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }

                                Text(utterance.text)
                                    .textSelection(.enabled)
                            }
                            .padding(.bottom, 8)
                        }
                    } else {
                        Text(transcript.text)
                            .textSelection(.enabled)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func copyTranscript() {
        var output = ""

        if showingSpeakerLabels, let speakerLabels = transcript.speakerLabels {
            for utterance in speakerLabels {
                output += "[\(utterance.formattedTimestamp)] \(utterance.speaker): \(utterance.text)\n\n"
            }
        } else {
            output = transcript.text
        }

        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(output, forType: .string)
        #endif
    }
}

// MARK: - Empty Tab Message
struct EmptyTabMessage: View {
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text(message)
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Video Info Card
struct VideoInfoCard: View {
    let videoInfo: VideoInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Video Information", systemImage: "info.circle.fill")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    Text("Title:")
                        .foregroundStyle(.secondary)
                        .frame(width: 80, alignment: .leading)
                    Text(videoInfo.title)
                }

                if let duration = videoInfo.duration {
                    HStack(alignment: .top) {
                        Text("Duration:")
                            .foregroundStyle(.secondary)
                            .frame(width: 80, alignment: .leading)
                        Text(formatDuration(duration))
                    }
                }
            }
            .font(.body)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%d:%02d", minutes, secs)
        }
    }
}

#Preview {
    VideoView(viewModel: VideoViewModel(apiKeyManager: APIKeyManager()))
        .frame(width: 800, height: 900)
}
