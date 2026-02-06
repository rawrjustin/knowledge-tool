import SwiftUI

// MARK: - Source Deletion Sheet

/// Confirmation sheet for deleting a knowledge source
struct SourceDeletionSheet: View {
    let source: KnowledgeSource
    let character: Character
    let repository: CombinedCharacterRepository
    let onDelete: (Character) -> Void
    let onCancel: () -> Void

    @State private var deletionPreview: SourceDeletionResult?
    @State private var isDeleting: Bool = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            // Header
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title2)
                    .foregroundStyle(.red)

                Text("Delete Source")
                    .font(.title3.weight(.semibold))

                Spacer()
            }

            // Warning message
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                Text("You are about to delete:")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack {
                    Image(systemName: source.sourceType.icon)
                        .foregroundStyle(.blue)
                    Text(source.title)
                        .font(.headline)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()

            // Impact preview
            if let preview = deletionPreview {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                    Text("IMPACT")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    HStack(spacing: DesignSystem.Spacing.lg) {
                        ImpactStat(
                            icon: "brain",
                            value: "\(preview.entriesRemoved)",
                            label: "memories"
                        )

                        ImpactStat(
                            icon: "folder",
                            value: "\(preview.affectedSections.count)",
                            label: "sections"
                        )

                        if preview.knowledgeFileDeleted != nil {
                            ImpactStat(
                                icon: "doc.text",
                                value: "1",
                                label: "file"
                            )
                        }
                    }

                    if !preview.affectedSections.isEmpty {
                        Text("Affected sections: \(preview.affectedSections.joined(separator: ", "))")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(DesignSystem.Spacing.md)
                .background(Color.red.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
            }

            // Error display
            if let error = error {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                .padding(DesignSystem.Spacing.sm)
                .background(Color.red.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small))
            }

            Spacer()

            // Warning text
            Text("This action cannot be undone. The knowledge file and all associated memories will be permanently deleted.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            // Actions
            HStack {
                Button("Cancel") {
                    onCancel()
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button(role: .destructive) {
                    Task {
                        await performDeletion()
                    }
                } label: {
                    if isDeleting {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Label("Delete Source", systemImage: "trash")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(isDeleting)
            }
        }
        .padding(DesignSystem.Spacing.xl)
        .frame(width: 450)
        .onAppear {
            loadPreview()
        }
    }

    // MARK: - Private Methods

    private func loadPreview() {
        let service = SourceDeletionService()
        deletionPreview = service.previewDeletion(sourceId: source.id, character: character)
    }

    private func performDeletion() async {
        isDeleting = true
        error = nil

        do {
            let service = SourceDeletionService()
            let (_, updatedCharacter) = try await service.deleteSourceEntries(
                sourceId: source.id,
                from: character,
                using: repository
            )

            onDelete(updatedCharacter)

        } catch {
            self.error = error.localizedDescription
        }

        isDeleting = false
    }
}

// MARK: - Impact Stat

struct ImpactStat: View {
    let icon: String
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption)
                Text(value)
                    .font(.title3.weight(.bold))
            }
            .foregroundStyle(.red)

            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
