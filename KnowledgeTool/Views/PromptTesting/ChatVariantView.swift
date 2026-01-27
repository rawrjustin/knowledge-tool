import SwiftUI

struct ChatVariantView: View {
    let variant: ChatVariant
    let variantIndex: Int
    let diffResult: DiffResult?
    let onSystemPromptChange: (String) -> Void
    let onLabelChange: (String) -> Void

    @State private var showingSystemPrompt = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                HStack {
                    TextField("Variant Label", text: Binding(
                        get: { variant.label },
                        set: { onLabelChange($0) }
                    ))
                    .textFieldStyle(.plain)
                    .font(.headline.bold())

                    Spacer()

                    Button {
                        showingSystemPrompt.toggle()
                    } label: {
                        Image(systemName: showingSystemPrompt ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.borderless)
                    .help("Toggle system prompt")
                }

                if let error = variant.error {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.caption)

                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .lineLimit(1)
                    }
                }
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor))

            // System prompt editor (collapsible)
            if showingSystemPrompt {
                TextEditor(text: Binding(
                    get: { variant.systemPrompt },
                    set: { onSystemPromptChange($0) }
                ))
                .font(.system(.caption, design: .monospaced))
                .frame(height: 100)
                .padding(8)
                .background(Color(nsColor: .textBackgroundColor))
            }

            Divider()

            // Messages
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(variant.messages.filter { $0.role != .system }) { message in
                        MessageBubble(message: message)
                    }

                    // Diff highlighting for latest assistant message
                    if let diff = diffResult, variantIndex > 0 {
                        DiffView(diffResult: diff)
                            .padding(.top, 8)
                    }

                    // Loading indicator
                    if variant.isExecuting {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Generating response...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding()
                    }
                }
                .padding(12)
            }
            .frame(maxHeight: .infinity)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }
}

// MARK: - Message Bubble

struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user {
                Spacer()
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                Text(message.content)
                    .font(.body)
                    .padding(10)
                    .background(message.role == .user ? Color.blue.opacity(0.1) : Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(12)

                Text(message.timestamp.formatted(date: .omitted, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: 400, alignment: message.role == .user ? .trailing : .leading)

            if message.role == .assistant {
                Spacer()
            }
        }
    }
}

// MARK: - Diff View

struct DiffView: View {
    let diffResult: DiffResult

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "arrow.left.arrow.right")
                    .foregroundStyle(.blue)
                    .font(.caption)

                Text("Differences from Variant A")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }

            FlowLayout(spacing: 4) {
                ForEach(diffResult.segments) { segment in
                    Text(segment.text)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(backgroundColor(for: segment.type))
                        .cornerRadius(4)
                }
            }
            .padding(8)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            .cornerRadius(8)
        }
    }

    private func backgroundColor(for type: DiffType) -> Color {
        switch type {
        case .unchanged:
            return Color.clear
        case .added:
            return Color.green.opacity(0.2)
        case .removed:
            return Color.red.opacity(0.2)
        case .modified:
            return Color.orange.opacity(0.2)
        }
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(
            in: proposal.replacingUnspecifiedDimensions().width,
            subviews: subviews,
            spacing: spacing
        )
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(
            in: bounds.width,
            subviews: subviews,
            spacing: spacing
        )
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x, y: bounds.minY + result.positions[index].y), proposal: .unspecified)
        }
    }

    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []

        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var lineHeight: CGFloat = 0

            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)

                if x + size.width > maxWidth && x > 0 {
                    x = 0
                    y += lineHeight + spacing
                    lineHeight = 0
                }

                positions.append(CGPoint(x: x, y: y))
                lineHeight = max(lineHeight, size.height)
                x += size.width + spacing
            }

            self.size = CGSize(width: maxWidth, height: y + lineHeight)
        }
    }
}
