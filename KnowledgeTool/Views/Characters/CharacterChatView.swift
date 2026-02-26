import SwiftUI

struct CharacterChatView: View {
    @State private var viewModelState: CharacterChatViewModel
    let character: Character
    @State private var showingClearConfirmation = false
    @State private var showingPublishSheet = false
    @Environment(\.colorScheme) private var colorScheme

    private let repository: CombinedCharacterRepository

    private var viewModel: CharacterChatViewModel {
        viewModelState
    }

    init(character: Character, repository: CombinedCharacterRepository) {
        self.character = character
        self.repository = repository
        self._viewModelState = State(initialValue: CharacterChatViewModel(
            character: character,
            repository: repository
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            chatHeader

            // Error banner
            if let error = viewModel.error {
                ErrorBanner(
                    message: error,
                    onDismiss: { viewModel.error = nil },
                    onRetry: {
                        Task {
                            await viewModel.loadChat()
                        }
                    }
                )
                .padding(.horizontal, DesignSystem.Spacing.lg)
                .padding(.vertical, DesignSystem.Spacing.sm)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            // Loading chat indicator
            if viewModel.isLoadingChat {
                loadingChatBanner
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            // Main content: unpublished gate or chat
            if !viewModel.isPublished && !viewModel.isLoadingChat {
                unpublishedGate
            } else {
                // Chat messages area
                chatMessagesArea

                Divider()

                // Input area
                inputArea
            }
        }
        .animation(DesignSystem.Animation.smooth, value: viewModel.error != nil)
        .animation(DesignSystem.Animation.smooth, value: viewModel.isLoadingChat)
        .animation(DesignSystem.Animation.smooth, value: viewModel.isPublished)
        .onAppear {
            Task {
                await viewModel.loadChat()
            }
        }
        .onChange(of: character.id) { _, _ in
            viewModel.updateCharacter(character)
        }
        .onChange(of: character.sha) { _, _ in
            viewModel.updateCharacter(character)
        }
        .confirmationDialog("Clear Chat", isPresented: $showingClearConfirmation) {
            Button("Clear All Messages", role: .destructive) {
                withAnimation(DesignSystem.Animation.smooth) {
                    viewModel.clearChat()
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will remove all messages from this conversation.")
        }
        .sheet(isPresented: $showingPublishSheet) {
            PublishSheet(
                character: character,
                repository: repository,
                publishViewModel: PublishViewModel(),
                onDismiss: {
                    showingPublishSheet = false
                    // Reload chat state after publish
                    Task {
                        await viewModel.loadChat()
                    }
                }
            )
        }
    }

    // MARK: - Unpublished Gate

    private var unpublishedGate: some View {
        VStack(spacing: DesignSystem.Spacing.xl) {
            Spacer()

            Image(systemName: "icloud.and.arrow.up")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)

            VStack(spacing: DesignSystem.Spacing.sm) {
                Text("Not Published")
                    .font(.title2.weight(.semibold))

                Text("This character hasn't been published to the Genies dev environment yet. Publish it to start chatting.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
            }

            Button {
                showingPublishSheet = true
            } label: {
                Label("Publish Now", systemImage: "arrow.up.circle.fill")
            }
            .buttonStyle(.modernPrimary)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }

    // MARK: - Header

    private var chatHeader: some View {
        HStack(spacing: DesignSystem.Spacing.lg) {
            // Character info with avatar
            HStack(spacing: DesignSystem.Spacing.md) {
                CharacterAvatar(name: character.name, size: 36)

                VStack(alignment: .leading, spacing: 0) {
                    Text(character.name)
                        .font(.headline)

                    if viewModel.isPublished {
                        Text("Genies Chat")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Not published")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }

            Spacer()

            // Config ID badge (if published)
            if let configId = viewModel.configId {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(configId, forType: .string)
                } label: {
                    HStack(spacing: DesignSystem.Spacing.xs) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 6, height: 6)
                        Text(String(configId.prefix(8)))
                            .font(.caption.monospaced())
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.1))
                    .foregroundStyle(.green)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("Copy config ID")
            }

            // Clear chat button
            Button {
                showingClearConfirmation = true
            } label: {
                Image(systemName: "trash")
                    .font(.subheadline)
            }
            .buttonStyle(.modernSecondary)
            .tint(.red)
            .help("Clear conversation")
            .disabled(viewModel.messages.isEmpty || !viewModel.isPublished)
        }
        .padding(DesignSystem.Spacing.lg)
        .background(.regularMaterial)
    }

    // MARK: - Loading Chat Banner

    private var loadingChatBanner: some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            ProgressView()
                .controlSize(.small)

            Text("Connecting to Genies...")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(DesignSystem.Spacing.md)
        .background(DesignSystem.Colors.infoBackground)
    }

    // MARK: - Chat Messages Area

    private var chatMessagesArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: DesignSystem.Spacing.lg) {
                    // Spacing top
                    Color.clear.frame(height: DesignSystem.Spacing.md)

                    // Messages
                    ForEach(viewModel.messages) { message in
                        MessageBubbleView(message: message, characterName: character.name)
                            .id(message.id)
                            .transition(.asymmetric(
                                insertion: .move(edge: .bottom).combined(with: .opacity),
                                removal: .opacity
                            ))
                    }

                    // Loading indicator for response
                    if viewModel.isLoading {
                        HStack {
                            TypingIndicatorView(characterName: character.name)
                            Spacer()
                        }
                        .padding(.horizontal)
                        .id("typing")
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    // Spacing bottom
                    Color.clear.frame(height: DesignSystem.Spacing.md)
                }
                .padding(.horizontal, DesignSystem.Spacing.lg)
                .animation(DesignSystem.Animation.spring, value: viewModel.messages.count)
            }
            .onChange(of: viewModel.messages.count) { _, _ in
                if let lastMessage = viewModel.messages.last {
                    withAnimation(DesignSystem.Animation.smooth) {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
            .onChange(of: viewModel.isLoading) { _, isLoading in
                if isLoading {
                    withAnimation(DesignSystem.Animation.smooth) {
                        proxy.scrollTo("typing", anchor: .bottom)
                    }
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    // MARK: - Input Area

    private var inputArea: some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            // Input field
            HStack(spacing: DesignSystem.Spacing.sm) {
                TextField("Type a message...", text: $viewModelState.inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...5)
                    .onSubmit {
                        Task {
                            await viewModel.sendMessage()
                        }
                    }

                // Keyboard hint (shows when focused and can send)
                if canSend {
                    KeyboardShortcutHint(keys: "⏎")
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, DesignSystem.Spacing.md)
            .padding(.vertical, DesignSystem.Spacing.sm)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(DesignSystem.Colors.inputBorder, lineWidth: 1)
            )
            .animation(DesignSystem.Animation.quick, value: canSend)

            // Send button
            Button {
                Task {
                    await viewModel.sendMessage()
                }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: 32))
                    .foregroundStyle(canSend ? Color.accentColor : Color.secondary.opacity(0.3))
            }
            .buttonStyle(PressableButtonStyle())
            .disabled(!canSend)
            .help("Send message (⏎)")
        }
        .padding(DesignSystem.Spacing.lg)
        .background(.bar)
    }

    private var canSend: Bool {
        !viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !viewModel.isLoading &&
        viewModel.isPublished &&
        viewModel.configId != nil
    }
}

// MARK: - Message Bubble View

struct MessageBubbleView: View {
    let message: ChatMessage
    let characterName: String
    @State private var isHovered = false
    @Environment(\.colorScheme) private var colorScheme

    private var isUser: Bool {
        message.role == .user
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: DesignSystem.Spacing.sm) {
            if isUser {
                Spacer(minLength: 60)
            } else {
                // Character avatar
                CharacterAvatar(name: characterName, size: 28)
            }

            VStack(alignment: isUser ? .trailing : .leading, spacing: DesignSystem.Spacing.xxs) {
                // Sender label (for character)
                if !isUser {
                    Text(characterName)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.leading, DesignSystem.Spacing.xs)
                }

                // Message bubble
                VStack(alignment: .leading, spacing: 0) {
                    Text(message.content)
                        .font(.body)
                        .textSelection(.enabled)
                        .padding(.horizontal, DesignSystem.Spacing.md)
                        .padding(.vertical, DesignSystem.Spacing.sm)
                }
                .background(
                    isUser
                        ? LinearGradient(
                            colors: [Color.accentColor, Color.accentColor.opacity(0.9)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        : LinearGradient(
                            colors: [Color(nsColor: .controlBackgroundColor), Color(nsColor: .controlBackgroundColor)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                )
                .foregroundStyle(isUser ? .white : .primary)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .shadow(
                    color: .black.opacity(colorScheme == .dark ? 0.3 : 0.08),
                    radius: isHovered ? 8 : 4,
                    y: isHovered ? 4 : 2
                )

                // Timestamp on hover
                if isHovered {
                    Text(message.timestamp.formatted(date: .omitted, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, DesignSystem.Spacing.xs)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .animation(DesignSystem.Animation.quick, value: isHovered)
            .onHover { hovering in
                isHovered = hovering
            }

            if !isUser {
                Spacer(minLength: 60)
            }
        }
    }
}

// MARK: - Typing Indicator View

struct TypingIndicatorView: View {
    let characterName: String
    @State private var dotOffsets: [CGFloat] = [0, 0, 0]

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            // Character avatar
            CharacterAvatar(name: characterName, size: 28)

            // Typing bubble
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(Color.secondary)
                        .frame(width: 7, height: 7)
                        .offset(y: dotOffsets[index])
                }
            }
            .padding(.horizontal, DesignSystem.Spacing.md)
            .padding(.vertical, DesignSystem.Spacing.sm)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
        }
        .onAppear {
            animateDots()
        }
    }

    private func animateDots() {
        for index in 0..<3 {
            withAnimation(
                .easeInOut(duration: 0.4)
                .repeatForever(autoreverses: true)
                .delay(Double(index) * 0.15)
            ) {
                dotOffsets[index] = -5
            }
        }
    }
}

// MARK: - Avatar View (Legacy - keeping for compatibility)
struct AvatarView: View {
    let name: String
    let color: Color

    var body: some View {
        CharacterAvatar(name: name, size: 28)
    }
}

#Preview {
    CharacterChatView(
        character: Character(
            name: "Jake Paul",
            directoryPath: "Personas/Jake Paul",
            personaFileName: "jakepaul.md",
            markdownContent: "# Jake Paul\n\nA famous YouTuber and boxer."
        ),
        repository: CombinedCharacterRepository(
            localBaseURL: URL(fileURLWithPath: "/tmp"),
            syncConfig: SupabaseSyncConfig(supabaseURL: "", supabaseAnonKey: "", syncEnabled: false)
        )
    )
    .frame(width: 800, height: 600)
}
