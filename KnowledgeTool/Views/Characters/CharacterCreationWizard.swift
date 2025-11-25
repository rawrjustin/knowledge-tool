import SwiftUI

struct CharacterCreationWizard: View {
    @State private var viewModel: CharacterCreationViewModel
    let onComplete: (Character) -> Void
    let onCancel: () -> Void

    init(
        localRepository: LocalCharacterRepository,
        apiKeyManager: APIKeyManager,
        onComplete: @escaping (Character) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self._viewModel = State(initialValue: CharacterCreationViewModel(
            localRepository: localRepository,
            apiKeyManager: apiKeyManager
        ))
        self.onComplete = onComplete
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Create New Character")
                    .font(.title.bold())

                Spacer()

                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            // Wizard content
            Group {
                switch viewModel.currentStep {
                case .pathSelection:
                    PathSelectionView(viewModel: viewModel)

                case .wikipediaInput:
                    WikipediaInputView(viewModel: viewModel)

                case .wikipediaPreview:
                    WikipediaPreviewView(viewModel: viewModel)

                case .originalInput:
                    OriginalInputView(viewModel: viewModel)

                case .generating:
                    GeneratingView(viewModel: viewModel)

                case .review:
                    ReviewView(viewModel: viewModel, onComplete: onComplete)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 800, minHeight: 600)
    }
}

// MARK: - Path Selection
struct PathSelectionView: View {
    @Bindable var viewModel: CharacterCreationViewModel

    var body: some View {
        VStack(spacing: 40) {
            Spacer()

            VStack(spacing: 16) {
                Image(systemName: "person.badge.plus")
                    .font(.system(size: 72))
                    .foregroundStyle(.blue)

                Text("How would you like to create this character?")
                    .font(.title2)
            }

            HStack(spacing: 24) {
                // Wikipedia path
                Button {
                    viewModel.selectPath(.wikipedia)
                } label: {
                    VStack(spacing: 12) {
                        Image(systemName: "globe")
                            .font(.system(size: 48))
                            .foregroundStyle(.blue)

                        Text("From Wikipedia")
                            .font(.headline)

                        Text("Create from an existing\ncharacter or celebrity")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(width: 200, height: 180)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(12)
                }
                .buttonStyle(.plain)

                // Original path
                Button {
                    viewModel.selectPath(.original)
                } label: {
                    VStack(spacing: 12) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 48))
                            .foregroundStyle(.purple)

                        Text("Original Character")
                            .font(.headline)

                        Text("Start from scratch with\nAI creative expansion")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(width: 200, height: 180)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(12)
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
        .padding()
    }
}

// MARK: - Wikipedia Input
struct WikipediaInputView: View {
    @Bindable var viewModel: CharacterCreationViewModel

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 24) {
                Image(systemName: "globe")
                    .font(.system(size: 64))
                    .foregroundStyle(.blue)

                Text("Enter Wikipedia URL")
                    .font(.title2.bold())

                VStack(alignment: .leading, spacing: 12) {
                    TextField("https://en.wikipedia.org/wiki/...", text: $viewModel.wikipediaURL)
                        .textFieldStyle(.roundedBorder)
                        .font(.body)

                    Text("Paste the Wikipedia URL for the character or celebrity")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: 500)

                if let error = viewModel.error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                HStack(spacing: 12) {
                    Button("Back") {
                        viewModel.goBack()
                    }

                    Button("Preview Character") {
                        Task {
                            await viewModel.fetchWikipediaPreview()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.wikipediaURL.isEmpty)
                }
            }

            Spacer()
        }
        .padding()
    }
}

// MARK: - Wikipedia Preview
struct WikipediaPreviewView: View {
    @Bindable var viewModel: CharacterCreationViewModel

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 24) {
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.blue)

                if let characterName = viewModel.previewCharacterName {
                    Text(characterName)
                        .font(.title.bold())
                }

                if let snippet = viewModel.previewSnippet {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Preview")
                            .font(.headline)
                            .foregroundStyle(.secondary)

                        ScrollView {
                            Text(snippet)
                                .font(.body)
                                .foregroundStyle(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(height: 200)
                        .padding()
                        .background(Color(nsColor: .controlBackgroundColor))
                        .cornerRadius(8)
                    }
                    .frame(maxWidth: 500)
                }

                Text("This character will be generated using the ASP-1 template")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                // High effort research toggle
                VStack(spacing: 4) {
                    Toggle(isOn: $viewModel.useHighEffort) {
                        HStack(spacing: 4) {
                            Text("Deep Research Mode")
                                .font(.subheadline)
                            Image(systemName: "sparkles")
                                .foregroundStyle(.orange)
                        }
                    }
                    .toggleStyle(.checkbox)

                    if viewModel.useHighEffort {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .font(.caption)
                            Text("May take 5-30+ minutes for exhaustive research")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    } else {
                        Text("Standard research typically takes 2-5 minutes")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 8)

                if let error = viewModel.error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                HStack(spacing: 12) {
                    Button("Back") {
                        viewModel.goBackFromPreview()
                    }

                    Button("Generate Character") {
                        Task {
                            await viewModel.generateFromWikipedia()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            Spacer()
        }
        .padding()
    }
}

// MARK: - Original Input
struct OriginalInputView: View {
    @Bindable var viewModel: CharacterCreationViewModel

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 24) {
                Image(systemName: "sparkles")
                    .font(.system(size: 64))
                    .foregroundStyle(.purple)

                Text("Describe Your Character")
                    .font(.title2.bold())

                VStack(alignment: .leading, spacing: 12) {
                    TextEditor(text: $viewModel.originalDescription)
                        .font(.body)
                        .frame(height: 200)
                        .border(Color(nsColor: .separatorColor))

                    Text("Describe the character in a few sentences. AI will creatively expand this into a full persona.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: 500)

                // High effort research toggle (shown for real person detection)
                VStack(spacing: 4) {
                    Toggle(isOn: $viewModel.useHighEffort) {
                        HStack(spacing: 4) {
                            Text("Deep Research Mode")
                                .font(.subheadline)
                            Image(systemName: "sparkles")
                                .foregroundStyle(.orange)
                        }
                    }
                    .toggleStyle(.checkbox)

                    if viewModel.useHighEffort {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .font(.caption)
                            Text("May take 5-30+ minutes for exhaustive research")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    } else {
                        Text("For real people, enables deeper research (2-5 min standard)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 8)

                if let error = viewModel.error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                HStack(spacing: 12) {
                    Button("Back") {
                        viewModel.goBack()
                    }

                    Button("Generate Character") {
                        Task {
                            await viewModel.generateOriginal()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.originalDescription.isEmpty)
                }
            }

            Spacer()
        }
        .padding()
    }
}

// MARK: - Generating View
struct GeneratingView: View {
    @Bindable var viewModel: CharacterCreationViewModel

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            ProgressView()
                .scaleEffect(1.5)

            Text("Generating Character...")
                .font(.title2.bold())

            // Progress logs
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(viewModel.progressLogs, id: \.self) { log in
                        HStack(alignment: .top, spacing: 8) {
                            Text("•")
                                .foregroundStyle(.secondary)

                            Text(log)
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Spacer()
                        }
                    }
                }
                .frame(maxWidth: 600)
                .padding()
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)
            }
            .frame(maxWidth: 600, maxHeight: 300)

            Spacer()
        }
        .padding()
    }
}

// MARK: - Review View
struct ReviewView: View {
    @Bindable var viewModel: CharacterCreationViewModel
    let onComplete: (Character) -> Void

    @State private var editedContent: String

    init(viewModel: CharacterCreationViewModel, onComplete: @escaping (Character) -> Void) {
        self.viewModel = viewModel
        self.onComplete = onComplete
        self._editedContent = State(initialValue: viewModel.generatedContent)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header with actions
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Review Character")
                        .font(.title2.bold())

                    Text("\(editedContent.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count) words")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 12) {
                    Button("Discard") {
                        viewModel.discard()
                    }

                    Button("Save Character") {
                        Task {
                            await viewModel.saveCharacter(content: editedContent)
                            if let character = viewModel.savedCharacter {
                                onComplete(character)
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()

            Divider()

            // Content editor
            TextEditor(text: $editedContent)
                .font(.system(.body, design: .monospaced))
                .padding()
        }
    }
}
