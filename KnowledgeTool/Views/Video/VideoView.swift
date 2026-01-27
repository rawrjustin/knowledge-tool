import SwiftUI
import UniformTypeIdentifiers

struct VideoView: View {
    @Bindable var viewModel: VideoViewModel
    @State private var showingToast = false
    @State private var toastMessage = ""
    @State private var toastStyle: ToastStyle = .success
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxl) {
                // Header
                HeaderView(
                    title: "Video Transcription",
                    subtitle: "Transcribe and summarize videos from URLs or file uploads",
                    icon: "video.fill"
                )

                // Important Notice
                InfoBanner(
                    title: "Designed for Interview Content",
                    message: "This tool works best with interview videos. It will attempt to identify and label the interviewee by name.",
                    icon: "person.wave.2.fill"
                )

                // Input Section
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
                    SectionHeader(title: "Video Source", icon: "film")

                    // URL Input
                    HStack(spacing: DesignSystem.Spacing.md) {
                        HStack(spacing: DesignSystem.Spacing.sm) {
                            Image(systemName: "link")
                                .foregroundStyle(.secondary)

                            TextField("Enter video URL (YouTube, Vimeo, etc.)", text: $viewModel.urlInput)
                                .textFieldStyle(.plain)
                        }
                        .padding(DesignSystem.Spacing.md)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
                        .overlay(
                            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                                .stroke(DesignSystem.Colors.inputBorder, lineWidth: 1)
                        )
                        .disabled(viewModel.processingState.isProcessing)

                        Button {
                            Task {
                                await viewModel.processVideoFromURL()
                            }
                        } label: {
                            Label("Process", systemImage: "play.fill")
                                .font(.subheadline.weight(.medium))
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(viewModel.urlInput.isEmpty || viewModel.processingState.isProcessing)
                        .help("Process video from URL")
                    }

                    // OR separator
                    HStack(spacing: DesignSystem.Spacing.md) {
                        Rectangle()
                            .fill(DesignSystem.Colors.divider)
                            .frame(height: 1)

                        Text("OR")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.tertiary)

                        Rectangle()
                            .fill(DesignSystem.Colors.divider)
                            .frame(height: 1)
                    }
                    .padding(.vertical, DesignSystem.Spacing.xs)

                    // File Upload
                    FileDropZone(onFileDrop: { url in
                        Task {
                            await viewModel.processVideoFromFile(url)
                        }
                    }, isProcessing: viewModel.processingState.isProcessing)
                }
                .cardStyle()

                // Processing State
                if viewModel.processingState.isProcessing {
                    ProcessingView(state: viewModel.processingState)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                // Error Message
                if let errorMessage = viewModel.errorMessage {
                    ErrorBanner(
                        message: errorMessage,
                        onDismiss: { viewModel.errorMessage = nil },
                        onRetry: {
                            Task {
                                await viewModel.processVideoFromURL()
                            }
                        }
                    )
                    .transition(.move(edge: .top).combined(with: .opacity))
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
                            withAnimation(DesignSystem.Animation.smooth) {
                                viewModel.reset()
                            }
                        },
                        onCopySuccess: { message in
                            showToast(message: message, style: .success)
                        }
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .padding(DesignSystem.Spacing.xxl)
            .animation(DesignSystem.Animation.smooth, value: viewModel.processingState.isProcessing)
            .animation(DesignSystem.Animation.smooth, value: viewModel.errorMessage != nil)
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
    @State private var isHovered = false

    var body: some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            ZStack {
                Circle()
                    .fill(isTargeted ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.08))
                    .frame(width: 72, height: 72)

                Image(systemName: "video.badge.plus")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(isTargeted ? Color.accentColor : .secondary)
            }
            .scaleEffect(isTargeted ? 1.1 : 1.0)
            .animation(DesignSystem.Animation.spring, value: isTargeted)

            VStack(spacing: DesignSystem.Spacing.xs) {
                Text("Drop video file here")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Text("or click to browse")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: DesignSystem.Spacing.sm) {
                ForEach(["MP4", "MOV", "AVI", "MKV"], id: \.self) { format in
                    Text(format)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, DesignSystem.Spacing.sm)
                        .padding(.vertical, DesignSystem.Spacing.xxs)
                        .background(Color.secondary.opacity(0.08))
                        .clipShape(Capsule())
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 180)
        .background {
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large)
                .strokeBorder(
                    isTargeted ? Color.accentColor : (isHovered ? Color.secondary.opacity(0.5) : Color.secondary.opacity(0.2)),
                    style: StrokeStyle(lineWidth: 2, dash: [8, 4])
                )
                .background(
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large)
                        .fill(isTargeted ? Color.accentColor.opacity(0.05) : (isHovered ? Color.secondary.opacity(0.02) : Color.clear))
                )
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if !isProcessing {
                selectVideoFile()
            }
        }
        .onHover { hovering in
            isHovered = hovering
        }
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            handleDrop(providers: providers)
        }
        .animation(DesignSystem.Animation.quick, value: isHovered)
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
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
            // Section header with actions
            HStack {
                SectionHeader(title: "Results", icon: "checkmark.circle.fill")

                Spacer()

                HStack(spacing: DesignSystem.Spacing.sm) {
                    // Export all button
                    Menu {
                        Button {
                            onExportSummary()
                        } label: {
                            Label("Export Summary", systemImage: "doc.text")
                        }

                        Button {
                            onExportTranscript()
                        } label: {
                            Label("Export Transcript", systemImage: "text.quote")
                        }
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                            .font(.subheadline)
                    }
                    .buttonStyle(.bordered)
                    .help("Export results")

                    Button {
                        onReset()
                    } label: {
                        Label("New Video", systemImage: "plus")
                            .font(.subheadline)
                    }
                    .buttonStyle(.borderedProminent)
                    .help("Process another video")
                }
            }

            // Video Info
            if let videoInfo = videoInfo {
                VideoInfoCard(videoInfo: videoInfo)
            }

            // Tabbed Interface
            VStack(spacing: 0) {
                // Tab Bar with icons
                HStack(spacing: 0) {
                    TabButton(
                        title: "Summary",
                        icon: "text.alignleft",
                        isSelected: selectedTab == 0
                    ) {
                        withAnimation(DesignSystem.Animation.quick) {
                            selectedTab = 0
                        }
                    }

                    TabButton(
                        title: "Dialogue",
                        icon: "quote.bubble",
                        isSelected: selectedTab == 1
                    ) {
                        withAnimation(DesignSystem.Animation.quick) {
                            selectedTab = 1
                        }
                    }

                    TabButton(
                        title: "Transcript",
                        icon: "text.word.spacing",
                        isSelected: selectedTab == 2
                    ) {
                        withAnimation(DesignSystem.Animation.quick) {
                            selectedTab = 2
                        }
                    }
                }
                .padding(DesignSystem.Spacing.xs)
                .background(.ultraThinMaterial)

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
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large))
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large)
                    .stroke(DesignSystem.Colors.cardBorder, lineWidth: 1)
            )
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.06), radius: 8, y: 2)
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
            HStack(spacing: DesignSystem.Spacing.xs) {
                Image(systemName: icon)
                    .font(.caption)
                Text(title)
                    .font(.subheadline.weight(isSelected ? .semibold : .regular))
            }
            .foregroundStyle(isSelected ? .primary : .secondary)
            .padding(.horizontal, DesignSystem.Spacing.md)
            .padding(.vertical, DesignSystem.Spacing.sm)
            .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small))
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
                .controlSize(.small)

                Button {
                    onExport()
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(10)
            .background(.regularMaterial)

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
                .controlSize(.small)

                Button {
                    exportDialogueExamples()
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(10)
            .background(.regularMaterial)

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
                        .background(.regularMaterial)
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(.tertiary.opacity(0.3), lineWidth: 0.5)
                        )
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
                        .controlSize(.small)
                }

                Spacer()

                Button {
                    copyTranscript()
                    onCopySuccess("Transcript copied to clipboard")
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    onExport()
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(10)
            .background(.regularMaterial)

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
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.lg) {
            // Video icon/thumbnail placeholder
            ZStack {
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                    .fill(Color.accentColor.opacity(0.1))
                    .frame(width: 80, height: 60)

                Image(systemName: "play.rectangle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(Color.accentColor)
            }

            // Video details
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                Text(videoInfo.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)

                HStack(spacing: DesignSystem.Spacing.md) {
                    if let duration = videoInfo.duration {
                        HStack(spacing: DesignSystem.Spacing.xs) {
                            Image(systemName: "clock")
                                .font(.caption2)
                            Text(formatDuration(duration))
                                .font(.caption)
                        }
                        .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()
        }
        .padding(DesignSystem.Spacing.md)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large))
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large)
                .stroke(DesignSystem.Colors.cardBorder, lineWidth: 1)
        )
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
