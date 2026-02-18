import SwiftUI

struct CharacterGeneratingView: View {
    let character: Character
    @Environment(BackgroundJobManager.self) private var backgroundJobManager

    private var activeJob: BackgroundJob? {
        backgroundJobManager.activeJob(for: character.name)
    }

    @State private var pulseScale: CGFloat = 1.0

    var body: some View {
        VStack(spacing: DesignSystem.Spacing.xl) {
            Spacer()

            // Pulsing avatar placeholder
            CharacterAvatar(name: character.name, size: 80)
                .scaleEffect(pulseScale)
                .animation(
                    .easeInOut(duration: 1.2).repeatForever(autoreverses: true),
                    value: pulseScale
                )
                .onAppear {
                    pulseScale = 1.08
                }

            Text(character.name)
                .font(.title.weight(.semibold))

            // Progress message
            if let job = activeJob {
                VStack(spacing: DesignSystem.Spacing.md) {
                    ProgressView()
                        .controlSize(.regular)

                    Text(job.progressMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .animation(.default, value: job.progressMessage)
                }
                .padding(.top, DesignSystem.Spacing.md)
            } else {
                VStack(spacing: DesignSystem.Spacing.md) {
                    ProgressView()
                        .controlSize(.regular)

                    Text("Generating character...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, DesignSystem.Spacing.md)
            }

            HelperText(text: "You can navigate to other characters while this runs.")
                .padding(.top, DesignSystem.Spacing.sm)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
