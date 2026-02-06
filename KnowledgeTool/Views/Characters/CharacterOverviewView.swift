import SwiftUI

struct CharacterOverviewView: View {
    let character: Character
    let repository: CombinedCharacterRepository
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
    @State private var showAugmentationSheet = false

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

                    // Action buttons
                    HStack(spacing: 8) {
                        // Augment Brain button
                        Button {
                            showAugmentationSheet = true
                        } label: {
                            Label("Augment", systemImage: "sparkles")
                        }
                        .buttonStyle(.bordered)
                        .help("Add source content to enhance this persona")

                        // Edit button
                        Button {
                            onEdit()
                        } label: {
                            Label("Edit", systemImage: "square.and.pencil")
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding()
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(12)

                // Persona markdown preview with knowledge indicators
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Persona Definition")
                            .font(.headline)

                        Spacer()

                        if character.hasKnowledgeBase {
                            HStack(spacing: 4) {
                                Image(systemName: "brain.head.profile")
                                    .font(.caption)
                                Text("\(character.knowledgeSources.count) knowledge sources")
                                    .font(.caption)
                            }
                            .foregroundStyle(.purple)
                        }
                    }

                    // Sectioned persona view with knowledge indicators
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            ForEach(parsePersonaSections(), id: \.title) { section in
                                PersonaSectionWithKnowledge(
                                    section: section,
                                    knowledgeSources: character.sectionsWithKnowledge[section.title] ?? []
                                )
                            }
                        }
                        .padding()
                    }
                    .frame(maxHeight: 500)
                    .background(Color(nsColor: .textBackgroundColor))
                    .cornerRadius(8)
                }
                .padding()
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(12)

                // Knowledge Sources section (if exists)
                if character.hasKnowledgeBase {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            HStack(spacing: 8) {
                                Image(systemName: "brain.head.profile")
                                    .foregroundStyle(.purple)
                                Text("Knowledge Sources")
                                    .font(.headline)
                            }

                            Spacer()

                            Text("\(character.totalKnowledgeEntries) memories • \(character.totalKnowledgeWords) words")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        // Knowledge sources by type
                        ForEach(KnowledgeSourceType.allCases, id: \.self) { type in
                            let sources = character.knowledgeSources.filter { $0.sourceType == type }
                            if !sources.isEmpty {
                                KnowledgeSourceTypeRow(type: type, sources: sources)
                            }
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
        .sheet(isPresented: $showAugmentationSheet) {
            BrainAugmentationView(
                character: character,
                repository: repository,
                apiKeyManager: apiKeyManager,
                onComplete: { updatedCharacter in
                    showAugmentationSheet = false
                    onCharacterUpdated(updatedCharacter)
                },
                onCancel: {
                    showAugmentationSheet = false
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
            let knowledgeFile = try await repository.createKnowledgeFile(
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

    // MARK: - Persona Section Parsing

    private func parsePersonaSections() -> [OverviewPersonaSection] {
        var sections: [OverviewPersonaSection] = []

        let pattern = "##\\s*([^\\n]+)\\n([\\s\\S]*?)(?=\\n##|\\z)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return sections
        }

        let nsString = character.markdownContent as NSString
        let matches = regex.matches(in: character.markdownContent, range: NSRange(location: 0, length: nsString.length))

        for match in matches {
            if match.numberOfRanges >= 3 {
                let titleRange = match.range(at: 1)
                let contentRange = match.range(at: 2)

                let title = nsString.substring(with: titleRange).trimmingCharacters(in: .whitespaces)
                let content = nsString.substring(with: contentRange).trimmingCharacters(in: .whitespacesAndNewlines)

                sections.append(OverviewPersonaSection(title: title, content: content))
            }
        }

        return sections
    }
}

// MARK: - Overview Persona Section

struct OverviewPersonaSection {
    let title: String
    let content: String
}

// MARK: - Persona Section With Knowledge

struct PersonaSectionWithKnowledge: View {
    let section: OverviewPersonaSection
    let knowledgeSources: [KnowledgeSource]

    @State private var isExpanded = true
    @State private var showingKnowledgeDetail = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Section header with knowledge indicator
            HStack {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 12)

                        Text(section.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                // Knowledge indicator
                if !knowledgeSources.isEmpty {
                    Button {
                        showingKnowledgeDetail.toggle()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "brain.head.profile")
                                .font(.caption2)
                            Text("\(totalKnowledgeEntries) memories")
                                .font(.caption2)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.purple.opacity(0.1))
                        .foregroundStyle(.purple)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showingKnowledgeDetail) {
                        KnowledgePopover(sources: knowledgeSources)
                    }
                }
            }

            // Section content
            if isExpanded {
                Text(section.content)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .padding(.leading, 20)
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var totalKnowledgeEntries: Int {
        knowledgeSources.reduce(0) { $0 + $1.entryCount }
    }
}

// MARK: - Knowledge Popover

struct KnowledgePopover: View {
    let sources: [KnowledgeSource]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Knowledge Sources")
                .font(.headline)

            ForEach(sources) { source in
                HStack(spacing: 8) {
                    Image(systemName: source.sourceType.icon)
                        .font(.subheadline)
                        .foregroundStyle(colorFor(source.sourceType))
                        .frame(width: 20)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(source.title)
                            .font(.subheadline)
                            .lineLimit(1)

                        Text("\(source.entryCount) memories")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
            }

            Divider()

            HStack {
                Text("Total: \(totalEntries) memories from \(sources.count) sources")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(width: 280)
    }

    private var totalEntries: Int {
        sources.reduce(0) { $0 + $1.entryCount }
    }

    private func colorFor(_ type: KnowledgeSourceType) -> Color {
        switch type.color {
        case "red": return .red
        case "blue": return .blue
        case "purple": return .purple
        case "orange": return .orange
        case "green": return .green
        default: return .secondary
        }
    }
}

// MARK: - Knowledge Source Type Row

struct KnowledgeSourceTypeRow: View {
    let type: KnowledgeSourceType
    let sources: [KnowledgeSource]

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Type header
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: type.icon)
                        .font(.subheadline)
                        .foregroundStyle(colorFor(type))
                        .frame(width: 20)

                    Text(type.displayName)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)

                    Text("(\(sources.count))")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text("\(totalEntries) memories")
                        .font(.caption)
                        .foregroundStyle(.tertiary)

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(10)
                .background(Color(nsColor: .textBackgroundColor))
                .cornerRadius(8)
            }
            .buttonStyle(.plain)

            // Expanded sources
            if isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(sources) { source in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(uploadStatusColor(source.uploadStatus))
                                .frame(width: 6, height: 6)

                            Text(source.title)
                                .font(.caption)
                                .lineLimit(1)

                            Spacer()

                            Text("\(source.entryCount) memories")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                    }
                }
                .padding(.leading, 30)
            }
        }
    }

    private var totalEntries: Int {
        sources.reduce(0) { $0 + $1.entryCount }
    }

    private func colorFor(_ type: KnowledgeSourceType) -> Color {
        switch type.color {
        case "red": return .red
        case "blue": return .blue
        case "purple": return .purple
        case "orange": return .orange
        case "green": return .green
        default: return .secondary
        }
    }

    private func uploadStatusColor(_ status: KnowledgeUploadStatus) -> Color {
        switch status {
        case .uploaded: return .green
        case .uploading: return .blue
        case .pending: return .orange
        case .failed: return .red
        }
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
        repository: CombinedCharacterRepository(
            localBaseURL: FileManager.default.temporaryDirectory,
            syncConfig: SupabaseSyncConfig(supabaseURL: "", supabaseAnonKey: "", syncEnabled: false)
        ),
        apiKeyManager: APIKeyManager(),
        onEdit: {},
        onCharacterUpdated: { _ in }
    )
    .frame(width: 800, height: 900)
}
