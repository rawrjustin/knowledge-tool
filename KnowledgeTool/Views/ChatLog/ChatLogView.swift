import SwiftUI

struct ChatLogView: View {
    @State private var viewModel = ChatLogViewModel()
    @State private var exportWidth: CGFloat = 720

    var body: some View {
        Group {
            if viewModel.isParsed {
                previewMode
            } else {
                inputMode
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .bottom) {
            if viewModel.showExportSuccess {
                exportSuccessBanner
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(DesignSystem.Animation.standard, value: viewModel.showExportSuccess)
    }

    // MARK: - Input Mode

    private var inputMode: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxs) {
                    Text("Chat Log Visualizer")
                        .font(DesignSystem.Typography.title2)
                    Text("Paste a chat log to render it as a shareable image")
                        .font(DesignSystem.Typography.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(.horizontal, DesignSystem.Spacing.xxl)
            .padding(.top, DesignSystem.Spacing.xl)
            .padding(.bottom, DesignSystem.Spacing.lg)

            // Input area
            VStack(spacing: DesignSystem.Spacing.lg) {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                    Text("Chat Log")
                        .font(DesignSystem.Typography.headline)

                    TextEditor(text: $viewModel.rawText)
                        .font(.system(.body, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .padding(DesignSystem.Spacing.md)
                        .background(Color(nsColor: .textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
                        .overlay(
                            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                                .stroke(DesignSystem.Colors.inputBorder, lineWidth: 1)
                        )
                        .frame(minHeight: 300)

                    HelperText(
                        text: "Supports most formats: \"Name: message\", timestamps, markdown bold names, etc.",
                        icon: "info.circle"
                    )
                }

                HStack {
                    Spacer()

                    Button {
                        viewModel.rawText = sampleChat
                    } label: {
                        Label("Load Sample", systemImage: "doc.text")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)

                    Button {
                        viewModel.parseInput()
                    } label: {
                        Label("Render Chat", systemImage: "eye")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .disabled(viewModel.rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(.horizontal, DesignSystem.Spacing.xxl)
            .padding(.bottom, DesignSystem.Spacing.xxl)

            Spacer()
        }
    }

    // MARK: - Preview Mode

    private var previewMode: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: DesignSystem.Spacing.md) {
                Button {
                    withAnimation(DesignSystem.Animation.standard) {
                        viewModel.reset()
                    }
                } label: {
                    Label("Back", systemImage: "chevron.left")
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)

                Divider()
                    .frame(height: 20)

                // Editable title
                TextField("Title", text: $viewModel.title)
                    .textFieldStyle(.plain)
                    .font(DesignSystem.Typography.headline)
                    .frame(maxWidth: 300)

                Spacer()

                // Export scale picker
                Picker("Scale", selection: $viewModel.exportScale) {
                    Text("1x").tag(CGFloat(1.0))
                    Text("2x").tag(CGFloat(2.0))
                    Text("3x").tag(CGFloat(3.0))
                }
                .pickerStyle(.segmented)
                .frame(width: 120)

                Button {
                    let exportView = ChatLogExportView(
                        messages: viewModel.messages,
                        title: viewModel.title
                    )
                    viewModel.exportAsPNG(chatView: exportView, width: exportWidth)
                } label: {
                    Label("Export PNG", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(viewModel.isExporting)
            }
            .padding(.horizontal, DesignSystem.Spacing.xl)
            .padding(.vertical, DesignSystem.Spacing.md)
            .background(.regularMaterial)

            Divider()

            // Preview scroll area
            ScrollView {
                ChatLogExportView(
                    messages: viewModel.messages,
                    title: viewModel.title
                )
                .frame(width: exportWidth)
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large))
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large)
                        .stroke(DesignSystem.Colors.cardBorder, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.08), radius: 20, y: 8)
                .padding(DesignSystem.Spacing.xxxl)
            }
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.5))
        }
    }

    // MARK: - Export Success Banner

    private var exportSuccessBanner: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.white)
            Text("Image exported successfully")
                .font(DesignSystem.Typography.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.white)
        }
        .padding(.horizontal, DesignSystem.Spacing.xl)
        .padding(.vertical, DesignSystem.Spacing.md)
        .background(DesignSystem.Colors.success.gradient)
        .clipShape(Capsule())
        .padding(.bottom, DesignSystem.Spacing.xl)
    }

    // MARK: - Sample Data

    private var sampleChat: String {
        """
        User: Hey, can you help me understand how async/await works in Swift?
        Assistant: Of course! async/await in Swift is a way to write asynchronous code that looks and behaves like synchronous code. When you mark a function as `async`, you're telling the compiler that this function might suspend and resume later. The `await` keyword marks each point where suspension can happen.
        User: So it's similar to JavaScript's async/await?
        Assistant: Very similar in concept! The key difference is that Swift's implementation is built on top of structured concurrency with Tasks and task groups, which gives you better control over cancellation and error propagation. It's also type-safe and integrates with Swift's actor model for thread safety.
        User: That makes sense. Can you show me a quick example?
        Assistant: Here's a simple example of fetching data from a URL using async/await. Instead of completion handlers, you can write linear code that's much easier to read and maintain. The compiler ensures you handle errors properly at each await point.
        """
    }
}

// MARK: - Export View (rendered to PNG)

struct ChatLogExportView: View {
    let messages: [ChatLogMessage]
    let title: String

    // Accent for user bubbles - a refined blue
    private let userBubbleColor = Color(red: 0.22, green: 0.45, blue: 0.95)
    private let assistantBubbleColor = Color(nsColor: .controlBackgroundColor)

    var body: some View {
        VStack(spacing: 0) {
            // Header bar
            headerBar

            // Messages
            VStack(spacing: DesignSystem.Spacing.xl) {
                ForEach(messages) { message in
                    chatBubble(for: message)
                }
            }
            .padding(.horizontal, DesignSystem.Spacing.xxl)
            .padding(.vertical, DesignSystem.Spacing.xl)

            // Footer
            footerBar
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var headerBar: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)

                    Text("\(messages.count) messages")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.tertiary)
                }

                Spacer()
            }
            .padding(.horizontal, DesignSystem.Spacing.xxl)
            .padding(.vertical, DesignSystem.Spacing.md)

            Rectangle()
                .fill(DesignSystem.Colors.divider)
                .frame(height: 1)
        }
    }

    private var footerBar: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(DesignSystem.Colors.divider)
                .frame(height: 1)

            HStack {
                Spacer()
                Text("Knowledge Tool")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.quaternary)
                Spacer()
            }
            .padding(.vertical, DesignSystem.Spacing.sm)
        }
    }

    @ViewBuilder
    private func chatBubble(for message: ChatLogMessage) -> some View {
        HStack(alignment: .top, spacing: 0) {
            if message.isUser { Spacer(minLength: 80) }

            VStack(alignment: message.isUser ? .trailing : .leading, spacing: DesignSystem.Spacing.xxs) {
                // Sender name
                Text(message.sender)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(message.isUser ? userBubbleColor : .secondary)
                    .padding(.horizontal, DesignSystem.Spacing.xs)

                // Message bubble
                Text(message.content)
                    .font(.system(size: 13.5, weight: .regular))
                    .lineSpacing(3)
                    .foregroundStyle(message.isUser ? .white : .primary)
                    .padding(.horizontal, DesignSystem.Spacing.lg)
                    .padding(.vertical, DesignSystem.Spacing.md)
                    .background(
                        message.isUser
                            ? AnyShapeStyle(userBubbleColor)
                            : AnyShapeStyle(Color(nsColor: .controlBackgroundColor))
                    )
                    .clipShape(
                        UnevenRoundedRectangle(
                            topLeadingRadius: message.isUser ? 16 : 4,
                            bottomLeadingRadius: 16,
                            bottomTrailingRadius: message.isUser ? 4 : 16,
                            topTrailingRadius: message.isUser ? 16 : 16
                        )
                    )
                    .overlay(
                        Group {
                            if !message.isUser {
                                UnevenRoundedRectangle(
                                    topLeadingRadius: 4,
                                    bottomLeadingRadius: 16,
                                    bottomTrailingRadius: 16,
                                    topTrailingRadius: 16
                                )
                                .stroke(DesignSystem.Colors.cardBorder, lineWidth: 0.5)
                            }
                        }
                    )
            }

            if !message.isUser { Spacer(minLength: 80) }
        }
    }
}
