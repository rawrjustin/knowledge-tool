import SwiftUI

// MARK: - Publish Status Badge (for dashboard header)

struct PublishStatusBadge: View {
    let character: Character
    let repository: CombinedCharacterRepository
    @State private var publishViewModel = PublishViewModel()
    @State private var showingPublishSheet = false

    var body: some View {
        Group {
            switch publishViewModel.publishState {
            case .unpublished:
                Button {
                    showingPublishSheet = true
                } label: {
                    HStack(spacing: DesignSystem.Spacing.xs) {
                        Circle()
                            .fill(Color.gray)
                            .frame(width: 8, height: 8)
                        Text("Unpublished")
                            .font(.caption.weight(.medium))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.gray.opacity(0.15))
                    .foregroundStyle(.secondary)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("Publish to Genies dev environment")

            case .clean(let configId, _):
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(configId, forType: .string)
                } label: {
                    HStack(spacing: DesignSystem.Spacing.xs) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                        Text(String(configId.prefix(8)) + "...")
                            .font(.caption.weight(.medium).monospaced())
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.green.opacity(0.15))
                    .foregroundStyle(.green)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("Published — click to copy config ID")

            case .dirtyEdits(_, _):
                Button {
                    showingPublishSheet = true
                } label: {
                    HStack(spacing: DesignSystem.Spacing.xs) {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 8, height: 8)
                        Text("Unpublished changes")
                            .font(.caption.weight(.medium))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.orange.opacity(0.15))
                    .foregroundStyle(.orange)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("Character has changed since last publish — click to update")
            }
        }
        .task {
            await publishViewModel.loadPublishState(for: character, repository: repository)
        }
        .onChange(of: character.markdownContent) { _, _ in
            Task {
                await publishViewModel.loadPublishState(for: character, repository: repository)
            }
        }
        .sheet(isPresented: $showingPublishSheet) {
            PublishSheet(
                character: character,
                repository: repository,
                publishViewModel: publishViewModel,
                onDismiss: { showingPublishSheet = false }
            )
        }
    }
}

// MARK: - Publish Sheet

struct PublishSheet: View {
    let character: Character
    let repository: CombinedCharacterRepository
    @Bindable var publishViewModel: PublishViewModel
    let onDismiss: () -> Void

    @State private var configDescription = ""
    @State private var greetingInstruction = ""
    @State private var dialogueStyle = ""
    @State private var behaviorControl = ""
    @State private var welcomeText = ""
    @State private var chatPrompt = ""
    @State private var llmModel = "gpt-5"
    @State private var linkConfigId = ""
    @State private var isLinking = false

    private var isUpdate: Bool {
        publishViewModel.configId != nil
    }

    private var configName: String {
        "[\(character.systemPromptType.shortDisplayName)] \(character.name)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
            // Header
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                Text(isUpdate ? "Update Config" : "Publish to Genies Dev")
                    .font(.title2.bold())

                Text(isUpdate ? "Update the character config on the dev environment." : "Create a new character config on the Genies dev environment.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Config name (auto-generated, read-only)
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                Text("Config Name")
                    .font(.headline)
                Text(configName)
                    .font(.body.monospaced())
                    .padding(DesignSystem.Spacing.sm)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(DesignSystem.CornerRadius.small)
            }

            // Editable fields
            ScrollView {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                    publishField("Description", text: $configDescription, placeholder: "Brief character description...")
                    publishField("Greeting Instruction", text: $greetingInstruction, placeholder: "How should the character greet users?")
                    publishField("Dialogue Style", text: $dialogueStyle, placeholder: "Casual, formal, playful...")
                    publishField("Behavior Control", text: $behaviorControl, placeholder: "Behavioral guidelines...")
                    publishField("Welcome Text", text: $welcomeText, placeholder: "Initial welcome message...")

                    // Chat prompt (auto-derived from prompt type, editable)
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                        Text("Chat Prompt Template")
                            .font(.subheadline.weight(.medium))
                        TextField("PromptLayer key...", text: $chatPrompt)
                            .polishedInput()
                        Text("Auto-derived from prompt type: \(character.systemPromptType.chatPromptKey)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    // LLM picker
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                        Text("LLM Model")
                            .font(.subheadline.weight(.medium))
                        Picker("Model", selection: $llmModel) {
                            Text("GPT-5").tag("gpt-5")
                        }
                        .labelsHidden()
                        .frame(width: 200)
                    }
                }
            }
            .frame(maxHeight: 300)

            // Link to existing (only for unpublished)
            if !isUpdate {
                Divider()

                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                    Text("Or Link to Existing Config")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)

                    HStack(spacing: DesignSystem.Spacing.sm) {
                        TextField("Paste config ID...", text: $linkConfigId)
                            .polishedInput()

                        Button("Link") {
                            Task {
                                isLinking = true
                                await publishViewModel.linkToExisting(
                                    character: character,
                                    existingConfigId: linkConfigId.trimmingCharacters(in: .whitespacesAndNewlines),
                                    repository: repository
                                )
                                isLinking = false
                                if publishViewModel.publishError == nil {
                                    onDismiss()
                                }
                            }
                        }
                        .buttonStyle(.modernSecondary)
                        .disabled(linkConfigId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLinking)
                    }
                }
            }

            // Error
            if let error = publishViewModel.publishError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(DesignSystem.Spacing.sm)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(DesignSystem.CornerRadius.small)
            }

            Divider()

            // Actions
            HStack {
                Button("Cancel") { onDismiss() }
                    .keyboardShortcut(.cancelAction)

                Spacer()

                if let configId = publishViewModel.configId {
                    Text("Config: \(String(configId.prefix(12)))...")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                Button(publishViewModel.isPublishing ? (isUpdate ? "Updating..." : "Publishing...") : (isUpdate ? "Update" : "Publish")) {
                    Task {
                        let overrides = GeniesConfigOverrides(
                            llmModel: llmModel,
                            description: configDescription.isEmpty ? nil : configDescription,
                            dialogueStyle: dialogueStyle.isEmpty ? nil : dialogueStyle,
                            behaviorControl: behaviorControl.isEmpty ? nil : behaviorControl,
                            greetingInstruction: greetingInstruction.isEmpty ? nil : greetingInstruction,
                            welcomeText: welcomeText.isEmpty ? nil : welcomeText,
                            chatPrompt: chatPrompt.isEmpty ? nil : chatPrompt
                        )

                        if isUpdate {
                            await publishViewModel.update(character: character, overrides: overrides, repository: repository)
                        } else {
                            await publishViewModel.publish(character: character, overrides: overrides, repository: repository)
                        }

                        if publishViewModel.publishError == nil {
                            onDismiss()
                        }
                    }
                }
                .buttonStyle(.modernPrimary)
                .disabled(publishViewModel.isPublishing)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(DesignSystem.Spacing.xl)
        .frame(width: 560, height: 620)
    }

    private func publishField(_ title: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            Text(title)
                .font(.subheadline.weight(.medium))
            TextField(placeholder, text: text, axis: .vertical)
                .polishedInput()
                .lineLimit(2...4)
        }
    }
}
