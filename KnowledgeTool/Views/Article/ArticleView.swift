import SwiftUI

struct ArticleView: View {
    @State var viewModel: ArticleViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                HeaderView(
                    title: "Article Summarization",
                    subtitle: "Extract and summarize content from articles and web pages"
                )

                // Input Section
                VStack(alignment: .leading, spacing: 16) {
                    Text("Article URL")
                        .font(.headline)

                    HStack(spacing: 12) {
                        TextField("Enter article URL", text: $viewModel.urlInput)
                            .polishedInput()
                            .disabled(viewModel.processingState.isProcessing)

                        Button {
                            Task {
                                await viewModel.processArticle()
                            }
                        } label: {
                            Label("Process", systemImage: "arrow.right.circle.fill")
                        }
                        .buttonStyle(.modernPrimary)
                        .disabled(viewModel.urlInput.isEmpty || viewModel.processingState.isProcessing)
                        .keyboardShortcut(.return, modifiers: .command)
                    }

                    Text("Paste a URL from any blog post, news article, or web page")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(.regularMaterial)
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
                    ArticleResultsSection(
                        articleInfo: viewModel.articleInfo,
                        summary: viewModel.summary,
                        onExportContent: {
                            if let content = viewModel.exportArticleContent() {
                                saveToFile(content: content, filename: "article_content")
                            }
                        },
                        onExportSummary: {
                            if let content = viewModel.exportSummary() {
                                saveToFile(content: content, filename: "article_summary")
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

// MARK: - Article Results Section
struct ArticleResultsSection: View {
    let articleInfo: ArticleInfo?
    let summary: Summary?
    let onExportContent: () -> Void
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
                .buttonStyle(.modernSecondary)
            }

            // Article Info
            if let articleInfo = articleInfo {
                ArticleInfoCard(articleInfo: articleInfo)
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

            // Article Content
            if let articleInfo = articleInfo {
                ArticleContentCard(
                    content: articleInfo.content,
                    onExport: onExportContent
                )
            }
        }
    }
}

// MARK: - Article Info Card
struct ArticleInfoCard: View {
    let articleInfo: ArticleInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Article Information", systemImage: "info.circle.fill")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                if let title = articleInfo.title {
                    HStack(alignment: .top) {
                        Text("Title:")
                            .foregroundStyle(.secondary)
                            .frame(width: 80, alignment: .leading)
                        Text(title)
                    }
                }

                HStack(alignment: .top) {
                    Text("URL:")
                        .foregroundStyle(.secondary)
                        .frame(width: 80, alignment: .leading)
                    Link(articleInfo.url, destination: URL(string: articleInfo.url)!)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                if let publishedDate = articleInfo.publishedDate {
                    HStack(alignment: .top) {
                        Text("Published:")
                            .foregroundStyle(.secondary)
                            .frame(width: 80, alignment: .leading)
                        Text(publishedDate.formatted(date: .long, time: .omitted))
                    }
                }

                HStack(alignment: .top) {
                    Text("Word Count:")
                        .foregroundStyle(.secondary)
                        .frame(width: 80, alignment: .leading)
                    Text("\(articleInfo.content.split(separator: " ").count)")
                }
            }
            .font(.body)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
        .cornerRadius(12)
    }
}

// MARK: - Article Content Card
struct ArticleContentCard: View {
    let content: String
    let onExport: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Full Content", systemImage: "doc.plaintext")
                    .font(.headline)

                Spacer()

                Button {
                    onExport()
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.modernSecondary)

                Button {
                    copyToClipboard(content)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .buttonStyle(.modernSecondary)
            }

            ScrollView {
                Text(content)
                    .textSelection(.enabled)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 400)
            .background(Color(nsColor: .textBackgroundColor))
            .cornerRadius(8)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
        .cornerRadius(12)
    }

    private func copyToClipboard(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }
}

#Preview {
    ArticleView(viewModel: ArticleViewModel(apiKeyManager: APIKeyManager()))
        .frame(width: 800, height: 900)
}
