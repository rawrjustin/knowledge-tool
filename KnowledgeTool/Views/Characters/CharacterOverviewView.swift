import SwiftUI

struct CharacterOverviewView: View {
    let character: Character
    let onEdit: () -> Void

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
            name: "Jake Paul",
            directoryPath: "/Users/justin-genies/Code/CharacterPrompts/Personas/Jake Paul",
            personaFileName: "jakepaul.md",
            markdownContent: """
            # Your Persona: Jake Paul

            ## Identity & Origins
            Jake Joseph Paul is a Cleveland-born content creator turned prizefighter...

            ## Current Situation
            It is fight night inside the locker room...
            """,
            knowledgeFiles: []
        ),
        onEdit: {}
    )
    .frame(width: 800, height: 900)
}
