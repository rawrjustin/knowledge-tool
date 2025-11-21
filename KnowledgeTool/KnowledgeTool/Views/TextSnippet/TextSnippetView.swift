import SwiftUI

struct TextSnippetView: View {
    @State var viewModel: TextSnippetViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                HeaderView(
                    title: "Text Snippet Analysis",
                    subtitle: "Analyze and summarize any text snippet"
                )

                // Input Section
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("Text Input")
                            .font(.headline)

                        Spacer()

                        Button {
                            viewModel.pasteFromClipboard()
                        } label: {
                            Label("Paste from Clipboard", systemImage: "doc.on.clipboard")
                        }
                        .buttonStyle(.bordered)
                    }

                    TextEditor(text: $viewModel.textInput)
                        .font(.body)
                        .frame(minHeight: 200, maxHeight: 400)
                        .padding(8)
                        .background(Color(nsColor: .textBackgroundColor))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                        )
                        .disabled(viewModel.processingState.isProcessing)

                    HStack {
                        Text("\(viewModel.textInput.count) characters")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Spacer()

                        Button {
                            Task {
                                await viewModel.processTextSnippet()
                            }
                        } label: {
                            Label("Analyze", systemImage: "sparkles")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(viewModel.textInput.isEmpty || viewModel.processingState.isProcessing)
                        .keyboardShortcut(.return, modifiers: .command)
                    }
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
                    TextSnippetResultsSection(
                        analysis: viewModel.analysis,
                        originalText: viewModel.textInput,
                        onExport: {
                            if let content = viewModel.exportAnalysis() {
                                saveToFile(content: content, filename: "text_analysis")
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

// MARK: - Text Snippet Results Section
struct TextSnippetResultsSection: View {
    let analysis: Summary?
    let originalText: String
    let onExport: () -> Void
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

            // Statistics
            TextStatisticsCard(text: originalText)

            // Analysis
            if let analysis = analysis {
                ResultCard(
                    title: "Analysis",
                    icon: "sparkles",
                    content: analysis.text,
                    onExport: onExport
                )
            }

            // Original Text (collapsible)
            OriginalTextCard(text: originalText)
        }
    }
}

// MARK: - Text Statistics Card
struct TextStatisticsCard: View {
    let text: String

    private var statistics: TextStatistics {
        TextStatistics(text: text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Statistics", systemImage: "chart.bar.fill")
                .font(.headline)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 16) {
                StatisticItem(label: "Characters", value: "\(statistics.characterCount)")
                StatisticItem(label: "Words", value: "\(statistics.wordCount)")
                StatisticItem(label: "Lines", value: "\(statistics.lineCount)")
                StatisticItem(label: "Sentences", value: "\(statistics.sentenceCount)")
                StatisticItem(label: "Paragraphs", value: "\(statistics.paragraphCount)")
                StatisticItem(label: "Avg Words/Sentence", value: "\(statistics.avgWordsPerSentence)")
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
    }
}

// MARK: - Statistic Item
struct StatisticItem: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.title3.bold())
                .foregroundStyle(.primary)

            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Original Text Card
struct OriginalTextCard: View {
    let text: String

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Label("Original Text", systemImage: "doc.plaintext")
                        .font(.headline)

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption.bold())
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)

            if isExpanded {
                ScrollView {
                    Text(text)
                        .textSelection(.enabled)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 300)
                .background(Color(nsColor: .textBackgroundColor))
                .cornerRadius(8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
    }
}

// MARK: - Text Statistics
struct TextStatistics {
    let text: String

    var characterCount: Int {
        text.count
    }

    var wordCount: Int {
        text.split(separator: " ").count
    }

    var lineCount: Int {
        text.components(separatedBy: .newlines).count
    }

    var sentenceCount: Int {
        let sentences = text.components(separatedBy: CharacterSet(charactersIn: ".!?"))
        return sentences.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
    }

    var paragraphCount: Int {
        let paragraphs = text.components(separatedBy: "\n\n")
        return paragraphs.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
    }

    var avgWordsPerSentence: Int {
        guard sentenceCount > 0 else { return 0 }
        return wordCount / sentenceCount
    }
}

#Preview {
    TextSnippetView(viewModel: TextSnippetViewModel(apiKeyManager: APIKeyManager()))
        .frame(width: 800, height: 900)
}
