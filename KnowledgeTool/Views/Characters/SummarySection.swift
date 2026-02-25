import SwiftUI

// MARK: - Summary Section

/// Expandable view showing a source's summary with key points, themes, and quotes
struct SummarySection: View {
    let source: KnowledgeSource
    let characterName: String
    let apiKeyManager: APIKeyManager
    let onSummaryGenerated: (SourceSummary) -> Void

    @State private var viewModel: SourceSummaryViewModel
    @State private var isExpanded: Bool = true
    @State private var copiedToClipboard: Bool = false

    init(
        source: KnowledgeSource,
        characterName: String,
        apiKeyManager: APIKeyManager,
        onSummaryGenerated: @escaping (SourceSummary) -> Void
    ) {
        self.source = source
        self.characterName = characterName
        self.apiKeyManager = apiKeyManager
        self.onSummaryGenerated = onSummaryGenerated
        self._viewModel = State(initialValue: SourceSummaryViewModel(
            source: source,
            characterName: characterName,
            apiKeyManager: apiKeyManager
        ))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            Button {
                withAnimation(DesignSystem.Animation.quick) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: "doc.text")
                        .foregroundStyle(.orange)

                    Text("Summary")
                        .font(.subheadline.weight(.semibold))

                    if viewModel.hasSummary {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                    }

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(DesignSystem.Spacing.md)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider()

                if viewModel.isGenerating {
                    // Progress view
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text(viewModel.progressMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(DesignSystem.Spacing.md)
                } else if let summary = viewModel.summary {
                    // Summary content
                    summaryContent(summary)
                } else {
                    // Generate button
                    generateButton
                }

                // Error display
                if let error = viewModel.error {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    .padding(DesignSystem.Spacing.md)
                }
            }
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
    }

    // MARK: - Generate Button

    private var generateButton: some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            Image(systemName: "sparkles")
                .font(.title2)
                .foregroundStyle(.tertiary)

            Text("No summary generated yet")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button {
                Task {
                    await viewModel.generateSummary()
                    if let summary = viewModel.summary {
                        onSummaryGenerated(summary)
                    }
                }
            } label: {
                Label("Generate Summary", systemImage: "sparkles")
            }
            .buttonStyle(.modernSecondary)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(DesignSystem.Spacing.lg)
    }

    // MARK: - Summary Content

    @ViewBuilder
    private func summaryContent(_ summary: SourceSummary) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
                // Overview
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                    Text("OVERVIEW")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Text(summary.overview)
                        .font(.callout)
                        .textSelection(.enabled)
                }

                // Key Points
                if !summary.keyPoints.isEmpty {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                        Text("KEY POINTS")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        ForEach(summary.keyPoints) { point in
                            KeyPointRow(point: point)
                        }
                    }
                }

                // Themes
                if !summary.themes.isEmpty {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                        Text("THEMES")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        FlowLayout(spacing: DesignSystem.Spacing.xs) {
                            ForEach(summary.themes, id: \.self) { theme in
                                Text(theme)
                                    .font(.caption)
                                    .padding(.horizontal, DesignSystem.Spacing.sm)
                                    .padding(.vertical, DesignSystem.Spacing.xs)
                                    .background(Color.blue.opacity(0.1))
                                    .foregroundStyle(.blue)
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }

                // Notable Quotes
                if !summary.notableQuotes.isEmpty {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                        Text("NOTABLE QUOTES")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        ForEach(summary.notableQuotes, id: \.self) { quote in
                            HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
                                Image(systemName: "quote.opening")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)

                                Text(quote)
                                    .font(.callout)
                                    .italic()
                                    .textSelection(.enabled)
                            }
                            .padding(DesignSystem.Spacing.sm)
                            .background(Color.purple.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small))
                        }
                    }
                }

                // Export actions
                HStack {
                    Button {
                        viewModel.copyToClipboard()
                        copiedToClipboard = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            copiedToClipboard = false
                        }
                    } label: {
                        Label(
                            copiedToClipboard ? "Copied!" : "Copy as Markdown",
                            systemImage: copiedToClipboard ? "checkmark" : "doc.on.doc"
                        )
                    }
                    .buttonStyle(.modernSecondary)
                    .controlSize(.small)

                    Spacer()

                    Text("Generated \(summary.generatedAt.formatted(.relative(presentation: .named)))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(DesignSystem.Spacing.md)
        }
        .frame(maxHeight: 400)
    }
}

// MARK: - Key Point Row

struct KeyPointRow: View {
    let point: KeyPoint

    var body: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
            // Importance indicator
            Circle()
                .fill(importanceColor)
                .frame(width: 8, height: 8)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(point.topic)
                        .font(.subheadline.weight(.medium))

                    if let timestamp = point.timestamp {
                        Text(formatTime(timestamp))
                            .font(.caption2)
                            .foregroundStyle(.blue)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.1))
                            .clipShape(Capsule())
                    }
                }

                Text(point.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(DesignSystem.Spacing.xs)
    }

    private var importanceColor: Color {
        switch point.importance {
        case .high: return .red
        case .medium: return .orange
        case .low: return .gray
        }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let totalSeconds = Int(seconds)
        let minutes = totalSeconds / 60
        let secs = totalSeconds % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}
