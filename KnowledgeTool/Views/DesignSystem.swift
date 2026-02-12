import SwiftUI

// MARK: - Design Tokens

/// Centralized design system for consistent styling across the app
enum DesignSystem {

    // MARK: - Corner Radii
    enum CornerRadius {
        static let small: CGFloat = 6      // Buttons, inputs, small chips
        static let medium: CGFloat = 8     // Tags, badges, small cards
        static let large: CGFloat = 12     // Cards, containers, modals
        static let xl: CGFloat = 16        // Large cards, panels
        static let pill: CGFloat = 100     // Pill buttons, avatars
    }

    // MARK: - Spacing
    enum Spacing {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 24
        static let xxxl: CGFloat = 32
    }

    // MARK: - Shadows
    enum Shadow {
        static func small(_ colorScheme: ColorScheme) -> some View {
            Color.black
                .opacity(colorScheme == .dark ? 0.3 : 0.06)
                .blur(radius: 4)
                .offset(y: 1)
        }

        static func medium(_ colorScheme: ColorScheme) -> some View {
            Color.black
                .opacity(colorScheme == .dark ? 0.4 : 0.08)
                .blur(radius: 8)
                .offset(y: 2)
        }

        static func large(_ colorScheme: ColorScheme) -> some View {
            Color.black
                .opacity(colorScheme == .dark ? 0.5 : 0.12)
                .blur(radius: 16)
                .offset(y: 4)
        }
    }

    // MARK: - Colors
    enum Colors {
        // Semantic colors
        static let success = Color.green
        static let warning = Color.orange
        static let error = Color.red
        static let info = Color.blue

        // Background opacities for status
        static let successBackground = Color.green.opacity(0.12)
        static let warningBackground = Color.orange.opacity(0.12)
        static let errorBackground = Color.red.opacity(0.12)
        static let infoBackground = Color.blue.opacity(0.12)

        // Border colors
        static let cardBorder = Color.primary.opacity(0.08)
        static let inputBorder = Color.primary.opacity(0.12)
        static let divider = Color.primary.opacity(0.06)

        /// Generate a consistent gradient color from a string (e.g., character name)
        static func gradient(from string: String) -> LinearGradient {
            let hash = abs(string.hashValue)
            let hue = Double(hash % 360) / 360.0

            return LinearGradient(
                colors: [
                    Color(hue: hue, saturation: 0.6, brightness: 0.9),
                    Color(hue: (hue + 0.1).truncatingRemainder(dividingBy: 1.0), saturation: 0.7, brightness: 0.8)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }

        /// Solid color from string for simpler uses
        static func solid(from string: String) -> Color {
            let hash = abs(string.hashValue)
            let hue = Double(hash % 360) / 360.0
            return Color(hue: hue, saturation: 0.6, brightness: 0.85)
        }
    }

    // MARK: - Animation
    enum Animation {
        static let quick = SwiftUI.Animation.easeOut(duration: 0.15)
        static let standard = SwiftUI.Animation.easeInOut(duration: 0.25)
        static let smooth = SwiftUI.Animation.easeInOut(duration: 0.35)
        static let spring = SwiftUI.Animation.spring(response: 0.4, dampingFraction: 0.75)
        static let bouncy = SwiftUI.Animation.spring(response: 0.35, dampingFraction: 0.6)
    }

    // MARK: - Typography
    enum Typography {
        static let largeTitle = Font.largeTitle.weight(.bold)
        static let title = Font.title.weight(.semibold)
        static let title2 = Font.title2.weight(.semibold)
        static let title3 = Font.title3.weight(.medium)
        static let headline = Font.headline
        static let body = Font.body
        static let callout = Font.callout
        static let subheadline = Font.subheadline
        static let footnote = Font.footnote
        static let caption = Font.caption
        static let caption2 = Font.caption2

        static let monoBody = Font.system(.body, design: .monospaced)
        static let monoSmall = Font.system(.caption, design: .monospaced)
    }
}

// MARK: - View Modifiers

/// Standard card styling
struct CardStyle: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    var padding: CGFloat = DesignSystem.Spacing.lg

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large))
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large)
                    .stroke(DesignSystem.Colors.cardBorder, lineWidth: 1)
            )
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.06), radius: 8, y: 2)
    }
}

/// Subtle card (no shadow)
struct SubtleCardStyle: ViewModifier {
    var padding: CGFloat = DesignSystem.Spacing.lg

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large))
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large)
                    .stroke(DesignSystem.Colors.cardBorder, lineWidth: 1)
            )
    }
}

/// Interactive card with hover state
struct InteractiveCardStyle: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false
    var padding: CGFloat = DesignSystem.Spacing.lg

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(isHovered ? Color.accentColor.opacity(0.05) : Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large))
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large)
                    .stroke(isHovered ? Color.accentColor.opacity(0.3) : DesignSystem.Colors.cardBorder, lineWidth: 1)
            )
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.06), radius: isHovered ? 12 : 8, y: isHovered ? 4 : 2)
            .scaleEffect(isHovered ? 1.005 : 1.0)
            .animation(DesignSystem.Animation.quick, value: isHovered)
            .onHover { hovering in
                isHovered = hovering
            }
    }
}

/// Button press animation
struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(DesignSystem.Animation.quick, value: configuration.isPressed)
    }
}

/// Keyboard shortcut hint badge
struct KeyboardShortcutHint: View {
    let keys: String

    var body: some View {
        Text(keys)
            .font(.system(size: 10, weight: .medium, design: .rounded))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small))
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small)
                    .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
            )
    }
}

// MARK: - View Extensions

extension View {
    /// Apply standard card styling
    func cardStyle(padding: CGFloat = DesignSystem.Spacing.lg) -> some View {
        modifier(CardStyle(padding: padding))
    }

    /// Apply subtle card styling (no shadow)
    func subtleCardStyle(padding: CGFloat = DesignSystem.Spacing.lg) -> some View {
        modifier(SubtleCardStyle(padding: padding))
    }

    /// Apply interactive card styling with hover effects
    func interactiveCardStyle(padding: CGFloat = DesignSystem.Spacing.lg) -> some View {
        modifier(InteractiveCardStyle(padding: padding))
    }

    /// Add a keyboard shortcut with visual hint
    func keyboardShortcutWithHint(_ key: KeyEquivalent, modifiers: EventModifiers = .command, hint: String) -> some View {
        self
            .keyboardShortcut(key, modifiers: modifiers)
            .help("\(hint) (\(modifiers.contains(.command) ? "⌘" : "")\(modifiers.contains(.shift) ? "⇧" : "")\(modifiers.contains(.option) ? "⌥" : "")\(String(key.character)))")
    }
}

// MARK: - Reusable Components

/// Character avatar with gradient background
struct CharacterAvatar: View {
    let name: String
    var size: CGFloat = 32

    var body: some View {
        ZStack {
            Circle()
                .fill(DesignSystem.Colors.gradient(from: name))

            Text(name.prefix(1).uppercased())
                .font(.system(size: size * 0.45, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .shadow(color: DesignSystem.Colors.solid(from: name).opacity(0.3), radius: 4, y: 2)
    }
}

/// Status badge with icon and text
struct StatusBadge: View {
    enum Status {
        case success, warning, error, info, neutral

        var color: Color {
            switch self {
            case .success: return DesignSystem.Colors.success
            case .warning: return DesignSystem.Colors.warning
            case .error: return DesignSystem.Colors.error
            case .info: return DesignSystem.Colors.info
            case .neutral: return .secondary
            }
        }

        var backgroundColor: Color {
            switch self {
            case .success: return DesignSystem.Colors.successBackground
            case .warning: return DesignSystem.Colors.warningBackground
            case .error: return DesignSystem.Colors.errorBackground
            case .info: return DesignSystem.Colors.infoBackground
            case .neutral: return Color.secondary.opacity(0.12)
            }
        }

        var icon: String {
            switch self {
            case .success: return "checkmark.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .error: return "xmark.circle.fill"
            case .info: return "info.circle.fill"
            case .neutral: return "circle.fill"
            }
        }
    }

    let text: String
    let status: Status
    var showIcon: Bool = true

    var body: some View {
        HStack(spacing: 4) {
            if showIcon {
                Image(systemName: status.icon)
                    .font(.caption2)
            }
            Text(text)
                .font(.caption)
                .fontWeight(.medium)
        }
        .foregroundStyle(status.color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(status.backgroundColor)
        .clipShape(Capsule())
    }
}

/// Activity dot indicator
struct ActivityDot: View {
    let isActive: Bool
    var color: Color = DesignSystem.Colors.warning
    var size: CGFloat = 8

    var body: some View {
        Circle()
            .fill(isActive ? color : Color.clear)
            .frame(width: size, height: size)
            .overlay(
                Circle()
                    .stroke(isActive ? color.opacity(0.3) : Color.clear, lineWidth: 2)
            )
    }
}

/// Section header with icon
struct SectionHeader: View {
    let title: String
    var icon: String? = nil
    var action: (() -> Void)? = nil
    var actionLabel: String? = nil
    var actionIcon: String? = nil

    var body: some View {
        HStack {
            if let icon = icon {
                Image(systemName: icon)
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            }

            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)

            Spacer()

            if let action = action {
                Button {
                    action()
                } label: {
                    if let actionIcon = actionIcon {
                        Label(actionLabel ?? "", systemImage: actionIcon)
                    } else {
                        Text(actionLabel ?? "")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }
}

/// Inline loading indicator with message
struct InlineLoader: View {
    let message: String
    var showProgress: Bool = true

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            if showProgress {
                ProgressView()
                    .controlSize(.small)
            }

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

/// Tooltip-style helper text
struct HelperText: View {
    let text: String
    var icon: String? = "info.circle"

    var body: some View {
        HStack(spacing: 4) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.caption2)
            }
            Text(text)
                .font(.caption)
        }
        .foregroundStyle(.secondary)
    }
}

// MARK: - Sync Status Indicator

/// Shows cloud sync status using SyncManager from the environment
struct SyncStatusIndicator: View {
    @Environment(SyncManager.self) private var syncManager

    /// Compact mode shows just the icon (for toolbar use)
    var compact: Bool = false

    var body: some View {
        if compact {
            compactView
        } else {
            labelView
        }
    }

    private var compactView: some View {
        Group {
            if syncManager.isSyncing {
                ProgressView()
                    .controlSize(.small)
                    .help("Syncing to cloud...")
            } else if let error = syncManager.syncError {
                Image(systemName: "exclamationmark.icloud.fill")
                    .foregroundStyle(DesignSystem.Colors.error)
                    .help("Sync error: \(error)")
            } else if !syncManager.canSync {
                Image(systemName: "icloud.slash")
                    .foregroundStyle(.secondary)
                    .help("Cloud sync not configured")
            } else if let lastSync = syncManager.lastSyncDate {
                Image(systemName: "checkmark.icloud.fill")
                    .foregroundStyle(DesignSystem.Colors.success)
                    .help("Last synced \(lastSync.formatted(.relative(presentation: .named)))")
            } else {
                Image(systemName: "icloud.fill")
                    .foregroundStyle(.secondary)
                    .help("Cloud sync enabled")
            }
        }
        .font(.system(size: 14))
    }

    private var labelView: some View {
        HStack(spacing: 4) {
            if syncManager.isSyncing {
                ProgressView()
                    .controlSize(.mini)
                Image(systemName: "icloud.and.arrow.up")
                    .font(.caption2)
                Text("Syncing...")
                    .font(.caption)
                    .fontWeight(.medium)
            } else if syncManager.syncError != nil {
                Image(systemName: "exclamationmark.icloud.fill")
                    .font(.caption2)
                Text("Sync error")
                    .font(.caption)
                    .fontWeight(.medium)
            } else if !syncManager.canSync {
                Image(systemName: "icloud.slash")
                    .font(.caption2)
                Text("Offline")
                    .font(.caption)
                    .fontWeight(.medium)
            } else {
                Image(systemName: "checkmark.icloud.fill")
                    .font(.caption2)
                Text("Synced")
                    .font(.caption)
                    .fontWeight(.medium)
            }
        }
        .foregroundStyle(labelColor)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(labelBackground)
        .clipShape(Capsule())
    }

    private var labelColor: Color {
        if syncManager.isSyncing {
            return DesignSystem.Colors.info
        } else if syncManager.syncError != nil {
            return DesignSystem.Colors.error
        } else if !syncManager.canSync {
            return .secondary
        } else {
            return DesignSystem.Colors.success
        }
    }

    private var labelBackground: Color {
        if syncManager.isSyncing {
            return DesignSystem.Colors.infoBackground
        } else if syncManager.syncError != nil {
            return DesignSystem.Colors.errorBackground
        } else if !syncManager.canSync {
            return Color.secondary.opacity(0.12)
        } else {
            return DesignSystem.Colors.successBackground
        }
    }
}

// MARK: - Animated Components

/// Animated typing indicator with smoother animation
struct AnimatedTypingIndicator: View {
    @State private var animationOffset: CGFloat = 0

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(Color.secondary)
                    .frame(width: 6, height: 6)
                    .offset(y: animationOffset(for: index))
            }
        }
        .onAppear {
            withAnimation(
                .easeInOut(duration: 0.5)
                .repeatForever(autoreverses: true)
            ) {
                animationOffset = 1
            }
        }
    }

    private func animationOffset(for index: Int) -> CGFloat {
        let delay = Double(index) * 0.15
        let progress = (animationOffset + CGFloat(delay)).truncatingRemainder(dividingBy: 1.0)
        return -4 * sin(progress * .pi)
    }
}

/// Shimmer loading effect
struct ShimmerEffect: ViewModifier {
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geometry in
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0),
                            Color.white.opacity(0.3),
                            Color.white.opacity(0)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geometry.size.width * 2)
                    .offset(x: -geometry.size.width + (geometry.size.width * 2 * phase))
                }
            )
            .mask(content)
            .onAppear {
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }
}

extension View {
    func shimmer() -> some View {
        modifier(ShimmerEffect())
    }
}

