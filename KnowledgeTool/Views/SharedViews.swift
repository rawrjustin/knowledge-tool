import SwiftUI

// MARK: - Toast Notification
enum ToastStyle {
    case success
    case error
    case info

    var icon: String {
        switch self {
        case .success: return "checkmark.circle.fill"
        case .error: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .success: return DesignSystem.Colors.success
        case .error: return DesignSystem.Colors.error
        case .info: return DesignSystem.Colors.info
        }
    }

    var backgroundColor: Color {
        switch self {
        case .success: return DesignSystem.Colors.successBackground
        case .error: return DesignSystem.Colors.errorBackground
        case .info: return DesignSystem.Colors.infoBackground
        }
    }
}

struct ToastView: View {
    let message: String
    let style: ToastStyle
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            Image(systemName: style.icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(style.color)

            Text(message)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, DesignSystem.Spacing.lg)
        .padding(.vertical, DesignSystem.Spacing.md)
        .background(.ultraThickMaterial)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.4 : 0.15), radius: 16, x: 0, y: 8)
        .overlay(
            Capsule()
                .stroke(style.color.opacity(0.2), lineWidth: 1)
        )
    }
}

struct ToastModifier: ViewModifier {
    @Binding var isShowing: Bool
    let message: String
    let style: ToastStyle
    let duration: Double

    func body(content: Content) -> some View {
        ZStack {
            content

            if isShowing {
                VStack {
                    ToastView(message: message, style: style)
                        .transition(
                            .asymmetric(
                                insertion: .move(edge: .top).combined(with: .opacity).combined(with: .scale(scale: 0.9)),
                                removal: .move(edge: .top).combined(with: .opacity)
                            )
                        )
                        .padding(.top, DesignSystem.Spacing.xl)

                    Spacer()
                }
                .animation(DesignSystem.Animation.spring, value: isShowing)
                .onAppear {
                    Task {
                        try? await Task.sleep(for: .seconds(duration))
                        await MainActor.run {
                            withAnimation(DesignSystem.Animation.smooth) {
                                isShowing = false
                            }
                        }
                    }
                }
            }
        }
    }
}

extension View {
    func toast(isShowing: Binding<Bool>, message: String, style: ToastStyle = .success, duration: Double = 2.5) -> some View {
        modifier(ToastModifier(isShowing: isShowing, message: message, style: style, duration: duration))
    }
}

// MARK: - Header View
struct HeaderView: View {
    let title: String
    let subtitle: String
    var icon: String? = nil

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                Text(title)
                    .font(DesignSystem.Typography.title2)
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(DesignSystem.Typography.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.bottom, DesignSystem.Spacing.sm)
    }
}

// MARK: - Processing View
struct ProcessingView: View {
    let state: ProcessingState
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.lg) {
            // Animated progress indicator
            ZStack {
                Circle()
                    .stroke(DesignSystem.Colors.info.opacity(0.2), lineWidth: 3)
                    .frame(width: 32, height: 32)

                ProgressView()
                    .controlSize(.regular)
            }

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxs) {
                if case .processing(let message) = state {
                    Text(message)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)

                    Text("Please wait...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding(DesignSystem.Spacing.lg)
        .background(DesignSystem.Colors.infoBackground)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large))
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large)
                .stroke(DesignSystem.Colors.info.opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - Error Banner
struct ErrorBanner: View {
    let message: String
    var onDismiss: (() -> Void)? = nil
    var onRetry: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(DesignSystem.Colors.error)
                .font(.system(size: 18, weight: .semibold))

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(2)

            Spacer()

            HStack(spacing: DesignSystem.Spacing.sm) {
                if let onRetry = onRetry {
                    Button("Retry") {
                        onRetry()
                    }
                    .buttonStyle(.modernSecondary)
                    .controlSize(.small)
                }

                if let onDismiss = onDismiss {
                    Button {
                        onDismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .padding(DesignSystem.Spacing.md)
        .background(DesignSystem.Colors.errorBackground)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large))
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large)
                .stroke(DesignSystem.Colors.error.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Success Banner
struct SuccessBanner: View {
    let message: String
    var onDismiss: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(DesignSystem.Colors.success)
                .font(.system(size: 18, weight: .semibold))

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.primary)

            Spacer()

            if let onDismiss = onDismiss {
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .padding(DesignSystem.Spacing.md)
        .background(DesignSystem.Colors.successBackground)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large))
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large)
                .stroke(DesignSystem.Colors.success.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Warning Banner
struct WarningBanner: View {
    let message: String
    var actionLabel: String? = nil
    var onAction: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(DesignSystem.Colors.warning)
                .font(.system(size: 18, weight: .semibold))

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.primary)

            Spacer()

            if let actionLabel = actionLabel, let onAction = onAction {
                Button(actionLabel) {
                    onAction()
                }
                .buttonStyle(.modernSecondary)
                .controlSize(.small)
            }
        }
        .padding(DesignSystem.Spacing.md)
        .background(DesignSystem.Colors.warningBackground)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large))
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large)
                .stroke(DesignSystem.Colors.warning.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Info Banner
struct InfoBanner: View {
    let title: String?
    let message: String
    var icon: String = "info.circle.fill"

    var body: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
            Image(systemName: icon)
                .foregroundStyle(DesignSystem.Colors.info)
                .font(.system(size: 18, weight: .semibold))

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxs) {
                if let title = title {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                }

                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(DesignSystem.Spacing.md)
        .background(DesignSystem.Colors.infoBackground)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large))
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large)
                .stroke(DesignSystem.Colors.info.opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - Result Card
struct ResultCard: View {
    let title: String
    let icon: String
    let content: String
    let onExport: () -> Void
    var onCopy: ((String) -> Void)? = nil
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Label(title, systemImage: icon)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Spacer()

                HStack(spacing: DesignSystem.Spacing.sm) {
                    Button {
                        copyToClipboard(content)
                        onCopy?("Copied to clipboard")
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.modernSecondary)
                    .controlSize(.small)
                    .help("Copy to clipboard (⌘C)")

                    Button {
                        onExport()
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.modernSecondary)
                    .controlSize(.small)
                    .help("Export to file")
                }
            }
            .padding(DesignSystem.Spacing.md)
            .background(.ultraThinMaterial)

            Divider()

            // Content
            ScrollView {
                Text(content)
                    .font(.system(.body, design: .rounded))
                    .textSelection(.enabled)
                    .padding(DesignSystem.Spacing.lg)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineSpacing(4)
            }
            .frame(maxHeight: 400)
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large))
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.06), radius: 8, y: 2)
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large)
                .stroke(DesignSystem.Colors.cardBorder, lineWidth: 1)
        )
    }

    private func copyToClipboard(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }
}

// MARK: - Empty State View
struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    var actionLabel: String? = nil
    var action: (() -> Void)? = nil
    var secondaryActionLabel: String? = nil
    var secondaryAction: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: DesignSystem.Spacing.xl) {
            // Icon with gradient background
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.accentColor.opacity(0.1),
                                Color.accentColor.opacity(0.05)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 100, height: 100)

                Image(systemName: icon)
                    .font(.system(size: 40, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.secondary, .secondary.opacity(0.6)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }

            VStack(spacing: DesignSystem.Spacing.sm) {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }

            // Action buttons
            if actionLabel != nil || secondaryActionLabel != nil {
                HStack(spacing: DesignSystem.Spacing.md) {
                    if let secondaryActionLabel = secondaryActionLabel, let secondaryAction = secondaryAction {
                        Button(secondaryActionLabel) {
                            secondaryAction()
                        }
                        .buttonStyle(.modernSecondary)
                    }

                    if let actionLabel = actionLabel, let action = action {
                        Button(actionLabel) {
                            action()
                        }
                        .buttonStyle(.modernPrimary)
                    }
                }
                .padding(.top, DesignSystem.Spacing.sm)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(DesignSystem.Spacing.xxxl)
    }
}

// MARK: - Loading State View
struct LoadingStateView: View {
    let message: String
    var detail: String? = nil

    var body: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            ProgressView()
                .controlSize(.large)

            VStack(spacing: DesignSystem.Spacing.xs) {
                Text(message)
                    .font(.headline)
                    .foregroundStyle(.primary)

                if let detail = detail {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(DesignSystem.Spacing.xxxl)
    }
}
