import SwiftUI
import UniformTypeIdentifiers

struct VideoView: View {
    @State var viewModel: VideoViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                HeaderView(
                    title: "Video Transcription",
                    subtitle: "Transcribe and summarize videos from URLs or file uploads"
                )

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
                        }
                    )
                }
            }
            .padding(24)
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
                try? content.write(to: url, atomically: true, encoding: .utf8)
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

            // Summary
            if let summary = summary {
                ResultCard(
                    title: "Summary",
                    icon: "doc.text.fill",
                    content: summary.text,
                    onExport: onExportSummary
                )
            }

            // Transcript
            if let transcript = transcript {
                TranscriptCard(
                    transcript: transcript,
                    onExport: onExportTranscript
                )
            }
        }
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

// MARK: - Transcript Card
struct TranscriptCard: View {
    let transcript: Transcript
    let onExport: () -> Void

    @State private var showingSpeakerLabels = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Transcript", systemImage: "text.quote")
                    .font(.headline)

                Spacer()

                if transcript.speakerLabels != nil {
                    Toggle("Speaker Labels", isOn: $showingSpeakerLabels)
                        .toggleStyle(.switch)
                }

                Button {
                    onExport()
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
            }

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
            }
            .frame(maxHeight: 400)
            .background(Color(nsColor: .textBackgroundColor))
            .cornerRadius(8)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
    }
}

#Preview {
    VideoView(viewModel: VideoViewModel(apiKeyManager: APIKeyManager()))
        .frame(width: 800, height: 900)
}
