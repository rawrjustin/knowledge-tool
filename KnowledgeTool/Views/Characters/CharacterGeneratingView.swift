import SwiftUI

struct CharacterGeneratingView: View {
    let character: Character
    var creationViewModel: CharacterCreationViewModel?
    @Environment(BackgroundJobManager.self) private var backgroundJobManager

    private var activeJob: BackgroundJob? {
        backgroundJobManager.activeJob(for: character.name)
    }

    @State private var pulseScale: CGFloat = 1.0

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Header with pulsing avatar
            VStack(spacing: DesignSystem.Spacing.md) {
                CharacterAvatar(name: character.name, size: 72)
                    .scaleEffect(pulseScale)
                    .animation(
                        .easeInOut(duration: 1.2).repeatForever(autoreverses: true),
                        value: pulseScale
                    )
                    .onAppear {
                        pulseScale = 1.08
                    }

                Text("Creating \(character.name)")
                    .font(.title2.weight(.semibold))
            }
            .padding(.bottom, DesignSystem.Spacing.xl)

            // Current status message
            if let job = activeJob {
                HStack(spacing: DesignSystem.Spacing.sm) {
                    ProgressView()
                        .controlSize(.small)
                    Text(job.progressMessage)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
                .animation(.default, value: job.progressMessage)
                .padding(.bottom, DesignSystem.Spacing.lg)
            } else {
                HStack(spacing: DesignSystem.Spacing.sm) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Generating character...")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, DesignSystem.Spacing.lg)
            }

            // Source statuses (per-source progress)
            if let vm = creationViewModel, !vm.unifiedSourceStatuses.isEmpty {
                sourceStatusSection(vm: vm)
                    .padding(.bottom, DesignSystem.Spacing.lg)
            }

            // Activity log
            if let vm = creationViewModel, !vm.progressLogs.isEmpty {
                activityLogSection(vm: vm)
            }

            Spacer()

            HelperText(text: "You can navigate to other characters while this runs.")
                .padding(.bottom, DesignSystem.Spacing.xl)
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Source Status Section

    @ViewBuilder
    private func sourceStatusSection(vm: CharacterCreationViewModel) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            Text("Sources")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
                .padding(.bottom, 2)

            let completedCount = vm.unifiedSourceStatuses.filter(\.isComplete).count
            let totalCount = vm.unifiedSourceStatuses.count

            // Overall progress bar
            VStack(alignment: .leading, spacing: 4) {
                ProgressView(value: Double(completedCount), total: Double(max(totalCount, 1)))
                    .tint(.accentColor)

                Text("\(completedCount) of \(totalCount) sources processed")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.bottom, DesignSystem.Spacing.xs)

            // Individual source items
            ForEach(vm.unifiedSourceStatuses) { status in
                sourceStatusRow(status)
            }
        }
        .padding(DesignSystem.Spacing.md)
        .frame(maxWidth: 420, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                .fill(Color(nsColor: .controlBackgroundColor))
        }
    }

    @ViewBuilder
    private func sourceStatusRow(_ status: CharacterCreationViewModel.UnifiedSourceStatus) -> some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            // Status icon
            Group {
                switch status {
                case .pending:
                    Image(systemName: "circle")
                        .foregroundStyle(.tertiary)
                case .processing:
                    ProgressView()
                        .controlSize(.mini)
                case .completed:
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                case .failed:
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.red)
                }
            }
            .frame(width: 16, height: 16)

            // Label
            Text(status.label)
                .font(.caption)
                .foregroundStyle(status.isComplete ? .secondary : .primary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            // Error detail for failed items
            if case .failed(_, _, let error) = status {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Activity Log Section

    @ViewBuilder
    private func activityLogSection(vm: CharacterCreationViewModel) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            Text("Activity")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
                .padding(.bottom, 2)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 3) {
                        ForEach(Array(vm.progressLogs.enumerated()), id: \.offset) { index, log in
                            Text(log)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(index == vm.progressLogs.count - 1 ? .primary : .secondary)
                                .id(index)
                        }
                    }
                    .padding(DesignSystem.Spacing.sm)
                }
                .frame(maxWidth: 420, maxHeight: 160)
                .background {
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                        .fill(Color(nsColor: .controlBackgroundColor))
                }
                .onChange(of: vm.progressLogs.count) {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(vm.progressLogs.count - 1, anchor: .bottom)
                    }
                }
            }
        }
        .frame(maxWidth: 420, alignment: .leading)
    }
}
