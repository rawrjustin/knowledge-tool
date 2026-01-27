import SwiftUI

struct CharacterOverviewView: View {
    let character: Character
    let localRepository: LocalCharacterRepository
    let apiKeyManager: APIKeyManager
    let onEdit: () -> Void
    let onCharacterUpdated: (Character) -> Void

    @State private var isGeneratingMemories = false
    @State private var isUploadingToRAG = false
    @State private var ragProgress: String = ""
    @State private var ragError: String?
    @State private var ragSuccess: String?
    @State private var showNamespaceInput = false
    @State private var pineconeNamespace: String = ""
    @State private var namespaceVectorCount: Int?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header with stats
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(character.name)
                            .font(.largeTitle.bold())

                        HStack(spacing: 16) {
                            // Version badge
                            Label(character.versionDisplay, systemImage: "number")
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.purple.opacity(0.1))
                                .foregroundStyle(.purple)
                                .cornerRadius(4)

                            // System prompt type badge
                            Label(character.systemPromptType.rawValue, systemImage: "doc.text.fill")
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.blue.opacity(0.1))
                                .foregroundStyle(.blue)
                                .cornerRadius(4)

                            // Knowledge base indicator
                            if character.hasKnowledgeBase {
                                Label("\(character.knowledgeFiles.count) knowledge files", systemImage: "books.vertical.fill")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            // Created date
                            Label("Created: \(character.createdAt.formatted(date: .abbreviated, time: .omitted))", systemImage: "calendar")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            // Last modified
                            Label(character.lastModified.formatted(date: .abbreviated, time: .shortened), systemImage: "clock")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    // Edit button
                    Button {
                        onEdit()
                    } label: {
                        Label("Edit", systemImage: "square.and.pencil")
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(12)

                // Persona markdown preview
                VStack(alignment: .leading, spacing: 12) {
                    Text("Persona Definition")
                        .font(.headline)

                    // Markdown content in scrollable view
                    ScrollView {
                        Text(character.markdownContent)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }
                    .frame(maxHeight: 500)
                    .background(Color(nsColor: .textBackgroundColor))
                    .cornerRadius(8)
                }
                .padding()
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(12)

                // Knowledge base section (if exists)
                if character.hasKnowledgeBase {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Knowledge Base")
                                .font(.headline)

                            Spacer()

                            Text("\(character.totalKnowledgeWords) total words")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        // Knowledge files list
                        ForEach(character.knowledgeFiles.prefix(5)) { knowledgeFile in
                            HStack(spacing: 12) {
                                Image(systemName: "doc.text.fill")
                                    .foregroundStyle(.blue)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(knowledgeFile.displayName)
                                        .font(.subheadline)

                                    Text("\(knowledgeFile.wordCount) words • \(knowledgeFile.createdAt.formatted(date: .abbreviated, time: .omitted))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()
                            }
                            .padding()
                            .background(Color(nsColor: .textBackgroundColor))
                            .cornerRadius(8)
                        }

                        if character.knowledgeFiles.count > 5 {
                            Text("+ \(character.knowledgeFiles.count - 5) more files")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.top, 4)
                        }
                    }
                    .padding()
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(12)
                }

                // RAG Section
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "brain.head.profile")
                            .foregroundStyle(.purple)
                        Text("RAG Knowledge Base")
                            .font(.headline)

                        Spacer()

                        if let count = namespaceVectorCount {
                            Text("\(count) vectors in Pinecone")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    // Status messages
                    if let error = ragError {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                            Spacer()
                            Button("Dismiss") {
                                ragError = nil
                            }
                            .font(.caption)
                        }
                        .padding(8)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(6)
                    }

                    if let success = ragSuccess {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text(success)
                                .font(.caption)
                                .foregroundStyle(.green)
                            Spacer()
                            Button("Dismiss") {
                                ragSuccess = nil
                            }
                            .font(.caption)
                        }
                        .padding(8)
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(6)
                    }

                    if !ragProgress.isEmpty {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text(ragProgress)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    // Check for existing memories
                    let hasMemories = character.knowledgeFiles.contains { $0.fileName == "character_memories.jsonl" }
                    let hasVideoKnowledge = character.knowledgeFiles.contains { $0.fileName == "structured_knowledge_base.jsonl" }

                    HStack(spacing: 12) {
                        // Generate Memories button
                        Button {
                            Task {
                                await generateMemories()
                            }
                        } label: {
                            HStack {
                                Image(systemName: "sparkles")
                                Text(hasMemories ? "Regenerate Memories" : "Generate Memories")
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(isGeneratingMemories || isUploadingToRAG)

                        // Upload to RAG button
                        Button {
                            showNamespaceInput = true
                        } label: {
                            HStack {
                                Image(systemName: "icloud.and.arrow.up")
                                Text("Upload to Pinecone")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isGeneratingMemories || isUploadingToRAG || (!hasMemories && !hasVideoKnowledge))
                    }

                    // Info text
                    VStack(alignment: .leading, spacing: 4) {
                        if hasMemories {
                            Label("Character memories ready", systemImage: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.green)
                        } else {
                            Label("Generate memories from persona to enable RAG", systemImage: "info.circle")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if hasVideoKnowledge {
                            Label("Video knowledge base ready", systemImage: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                    }
                }
                .padding()
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(12)

                // Quick stats
                VStack(alignment: .leading, spacing: 12) {
                    Text("Details")
                        .font(.headline)

                    VStack(alignment: .leading, spacing: 8) {
                        DetailRow(label: "File", value: character.personaFileName)
                        DetailRow(label: "Directory", value: character.directoryPath)
                        DetailRow(label: "Word Count", value: "\(wordCount(character.markdownContent))")
                        DetailRow(label: "Status", value: character.isLocalOnly ? "Local Only" : "Synced")
                    }
                }
                .padding()
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(12)
            }
            .padding(24)
        }
        .sheet(isPresented: $showNamespaceInput) {
            PineconeUploadSheet(
                characterName: character.name,
                namespace: $pineconeNamespace,
                onUpload: {
                    showNamespaceInput = false
                    Task {
                        await uploadToRAG()
                    }
                },
                onCancel: {
                    showNamespaceInput = false
                }
            )
        }
    }

    // MARK: - RAG Actions

    private func generateMemories() async {
        guard let openAIKey = apiKeyManager.getAPIKey(for: .openAI) else {
            ragError = "OpenAI API key not configured. Please add it in Settings."
            return
        }

        isGeneratingMemories = true
        ragError = nil
        ragSuccess = nil
        ragProgress = "Generating memories from persona..."

        do {
            let service = MemoryGenerationService(openAIApiKey: openAIKey)
            let memories = try await service.generateMemories(
                characterName: character.name,
                personaContent: character.markdownContent,
                onProgress: { message in
                    Task { @MainActor in
                        ragProgress = message
                    }
                }
            )

            // Convert to JSONL
            let jsonlContent = await service.memoriesToJSONL(memories)

            // Save as knowledge file
            ragProgress = "Saving memories..."
            let knowledgeFile = try await localRepository.createKnowledgeFile(
                for: character,
                fileName: "character_memories.jsonl",
                content: jsonlContent
            )

            // Update character with new knowledge file
            var updatedCharacter = character
            if let existingIndex = updatedCharacter.knowledgeFiles.firstIndex(where: { $0.fileName == "character_memories.jsonl" }) {
                updatedCharacter.knowledgeFiles[existingIndex] = knowledgeFile
            } else {
                updatedCharacter.knowledgeFiles.append(knowledgeFile)
            }

            ragProgress = ""
            ragSuccess = "Generated \(memories.count) memory entries"
            onCharacterUpdated(updatedCharacter)

        } catch {
            ragError = error.localizedDescription
            ragProgress = ""
        }

        isGeneratingMemories = false
    }

    private func uploadToRAG() async {
        guard let pineconeKey = apiKeyManager.getAPIKey(for: .pinecone) else {
            ragError = "Pinecone API key not configured. Please add it in Settings."
            return
        }

        guard let openAIKey = apiKeyManager.getAPIKey(for: .openAI) else {
            ragError = "OpenAI API key not configured. Please add it in Settings."
            return
        }

        guard !pineconeNamespace.isEmpty else {
            ragError = "Please enter a namespace (Character ID)"
            return
        }

        isUploadingToRAG = true
        ragError = nil
        ragSuccess = nil
        ragProgress = "Preparing documents..."

        do {
            // Parse knowledge files
            let documents = try PineconeService.parseCharacterKnowledge(knowledgeFiles: character.knowledgeFiles)

            guard !documents.isEmpty else {
                ragError = "No JSONL knowledge files found to upload"
                isUploadingToRAG = false
                ragProgress = ""
                return
            }

            let service = PineconeService(
                apiKey: pineconeKey,
                openAIApiKey: openAIKey,
                indexName: apiKeyManager.pineconeIndexName
            )

            let result = try await service.uploadKnowledge(
                documents: documents,
                namespace: pineconeNamespace,
                clearExisting: true,
                onProgress: { message in
                    Task { @MainActor in
                        ragProgress = message
                    }
                }
            )

            ragProgress = ""
            ragSuccess = "Uploaded \(result.documentsUploaded) documents to \(result.namespace)"
            namespaceVectorCount = result.documentsUploaded

        } catch {
            ragError = error.localizedDescription
            ragProgress = ""
        }

        isUploadingToRAG = false
    }

    private func wordCount(_ text: String) -> Int {
        text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .count
    }
}

// MARK: - Detail Row
struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)

            Text(value)
                .font(.caption)
                .textSelection(.enabled)

            Spacer()
        }
    }
}

#Preview {
    CharacterOverviewView(
        character: Character(
            name: "Sample Character",
            directoryPath: "Characters/Sample",
            personaFileName: "sample.md",
            markdownContent: """
            # Your Persona: Sample Character

            ## Identity & Origins
            A sample character for preview purposes...

            ## Current Situation
            Currently in a preview...
            """,
            knowledgeFiles: []
        ),
        localRepository: LocalCharacterRepository(baseURL: FileManager.default.temporaryDirectory),
        apiKeyManager: APIKeyManager(),
        onEdit: {},
        onCharacterUpdated: { _ in }
    )
    .frame(width: 800, height: 900)
}
