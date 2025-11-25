import SwiftUI

struct CharacterChatView: View {
    @State private var viewModel: CharacterChatViewModel
    let character: Character

    init(character: Character, apiKeyManager: APIKeyManager) {
        self.character = character
        self._viewModel = State(initialValue: CharacterChatViewModel(
            character: character,
            apiKeyManager: apiKeyManager
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header with prompt type selector
            chatHeader

            Divider()

            // Error banner
            if let error = viewModel.error {
                errorBanner(error)
            }

            // Loading system prompt indicator
            if viewModel.isLoadingSystemPrompt {
                loadingSystemPromptBanner
            }

            // Chat messages area
            chatMessagesArea

            Divider()

            // Input area
            inputArea
        }
        .onAppear {
            Task {
                await viewModel.loadSystemPrompt()
            }
        }
        .onChange(of: character.id) { _, _ in
            viewModel.updateCharacter(character)
        }
    }

    // MARK: - Header

    private var chatHeader: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Chat with \(character.name)")
                    .font(.headline)

                Text("Test how the character responds using different system prompts")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // System prompt type picker
            HStack(spacing: 8) {
                Text("Mode:")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Picker("System Prompt", selection: $viewModel.selectedPromptType) {
                    ForEach(SystemPromptType.allCases, id: \.self) { type in
                        Text(type.rawValue)
                            .tag(type)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
                .onChange(of: viewModel.selectedPromptType) { _, _ in
                    Task {
                        await viewModel.loadSystemPrompt()
                    }
                }
            }

            // Clear chat button
            Button {
                viewModel.clearChat()
            } label: {
                Label("Clear", systemImage: "trash")
                    .font(.subheadline)
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.messages.isEmpty)
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Error Banner

    private func errorBanner(_ error: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)

            Text(error)
                .font(.subheadline)

            Spacer()

            Button("Dismiss") {
                viewModel.error = nil
            }
            .font(.subheadline)
        }
        .padding()
        .background(Color.red.opacity(0.1))
    }

    // MARK: - Loading System Prompt Banner

    private var loadingSystemPromptBanner: some View {
        HStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)

            Text("Loading \(viewModel.selectedPromptType.displayName)...")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding()
        .background(Color.blue.opacity(0.1))
    }

    // MARK: - Chat Messages Area

    private var chatMessagesArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 16) {
                    // Messages
                    ForEach(viewModel.messages) { message in
                        MessageBubbleView(message: message, characterName: character.name)
                            .id(message.id)
                    }

                    // Loading indicator for response (including initial greeting)
                    if viewModel.isLoading {
                        HStack {
                            TypingIndicatorView()
                            Spacer()
                        }
                        .padding(.horizontal)
                        .id("typing")
                    }
                }
                .padding()
            }
            .onChange(of: viewModel.messages.count) { _, _ in
                if let lastMessage = viewModel.messages.last {
                    withAnimation {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
            .onChange(of: viewModel.isLoading) { _, isLoading in
                if isLoading {
                    withAnimation {
                        proxy.scrollTo("typing", anchor: .bottom)
                    }
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    // MARK: - Input Area

    private var inputArea: some View {
        HStack(spacing: 12) {
            TextField("Type a message...", text: $viewModel.inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .padding(12)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)
                .lineLimit(1...5)
                .onSubmit {
                    Task {
                        await viewModel.sendMessage()
                    }
                }

            Button {
                Task {
                    await viewModel.sendMessage()
                }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(canSend ? .blue : .gray)
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
        }
        .padding()
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var canSend: Bool {
        !viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !viewModel.isLoading &&
        viewModel.systemPromptLoaded
    }
}

// MARK: - Message Bubble View

struct MessageBubbleView: View {
    let message: ChatMessage
    let characterName: String

    private var isUser: Bool {
        message.role == .user
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if isUser {
                Spacer(minLength: 60)
            } else {
                // Character avatar
                Circle()
                    .fill(Color.blue.gradient)
                    .frame(width: 32, height: 32)
                    .overlay {
                        Text(characterName.prefix(1))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                    }
            }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                // Sender label
                Text(isUser ? "You" : characterName)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                // Message content
                Text(message.content)
                    .font(.body)
                    .padding(12)
                    .background(isUser ? Color.blue : Color(nsColor: .controlBackgroundColor))
                    .foregroundStyle(isUser ? .white : .primary)
                    .cornerRadius(16)

                // Timestamp
                Text(message.timestamp.formatted(date: .omitted, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            if !isUser {
                Spacer(minLength: 60)
            } else {
                // User avatar
                Circle()
                    .fill(Color.gray.gradient)
                    .frame(width: 32, height: 32)
                    .overlay {
                        Image(systemName: "person.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.white)
                    }
            }
        }
    }
}

// MARK: - Typing Indicator View

struct TypingIndicatorView: View {
    @State private var animationPhase = 0

    var body: some View {
        HStack(spacing: 12) {
            // Avatar placeholder
            Circle()
                .fill(Color.blue.gradient)
                .frame(width: 32, height: 32)
                .overlay {
                    Image(systemName: "sparkles")
                        .font(.system(size: 14))
                        .foregroundStyle(.white)
                }

            // Typing dots
            HStack(spacing: 4) {
                ForEach(0..<3) { index in
                    Circle()
                        .fill(Color.secondary)
                        .frame(width: 8, height: 8)
                        .opacity(animationPhase == index ? 1 : 0.3)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(16)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.5).repeatForever()) {
                animationPhase = (animationPhase + 1) % 3
            }
        }
    }
}

// MARK: - Preview

#Preview {
    CharacterChatView(
        character: Character(
            name: "Jake Paul",
            directoryPath: "Personas/Jake Paul",
            personaFileName: "jakepaul.md",
            markdownContent: "# Jake Paul\n\nA famous YouTuber and boxer."
        ),
        apiKeyManager: APIKeyManager()
    )
    .frame(width: 800, height: 600)
}
