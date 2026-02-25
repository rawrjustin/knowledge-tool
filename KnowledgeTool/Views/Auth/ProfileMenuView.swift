import SwiftUI

struct ProfileMenuView: View {
    @Bindable var authViewModel: AuthViewModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var showingProfilePopover = false
    @State private var isHovered = false
    @State private var showCopiedToast = false
    @State private var copiedField: String?

    var body: some View {
        Button {
            showingProfilePopover.toggle()
        } label: {
            profileIcon
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(DesignSystem.Animation.quick) {
                isHovered = hovering
            }
        }
        .help("Account (\(authViewModel.userEmail ?? ""))")
        .popover(isPresented: $showingProfilePopover, arrowEdge: .bottom) {
            profilePopoverContent
        }
    }

    // MARK: - Profile Icon (Toolbar)

    private var profileIcon: some View {
        ZStack(alignment: .bottomTrailing) {
            // Avatar circle with gradient
            ZStack {
                Circle()
                    .fill(
                        DesignSystem.Colors.gradient(from: authViewModel.userEmail ?? "user")
                    )
                    .frame(width: 26, height: 26)

                Text(authViewModel.userInitials)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
            .overlay(
                Circle()
                    .strokeBorder(
                        isHovered ? Color.accentColor.opacity(0.4) : Color.primary.opacity(0.08),
                        lineWidth: isHovered ? 1.5 : 1
                    )
            )
            .scaleEffect(isHovered ? 1.08 : 1.0)

            // Online status dot
            Circle()
                .fill(DesignSystem.Colors.success)
                .frame(width: 7, height: 7)
                .overlay(
                    Circle()
                        .strokeBorder(Color(nsColor: .windowBackgroundColor), lineWidth: 1.5)
                )
                .offset(x: 1, y: 1)
        }
    }

    // MARK: - Popover Content

    private var profilePopoverContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // User identity header
            HStack(spacing: DesignSystem.Spacing.md) {
                // Large avatar
                ZStack {
                    Circle()
                        .fill(
                            DesignSystem.Colors.gradient(from: authViewModel.userEmail ?? "user")
                        )
                        .frame(width: 44, height: 44)
                        .shadow(color: DesignSystem.Colors.solid(from: authViewModel.userEmail ?? "user").opacity(0.3), radius: 6, y: 2)

                    Text(authViewModel.userInitials)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(authViewModel.displayName)
                        .font(.headline)
                        .lineLimit(1)

                    Text(authViewModel.userEmail ?? "")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                // Status badge
                HStack(spacing: 4) {
                    Circle()
                        .fill(DesignSystem.Colors.success)
                        .frame(width: 6, height: 6)
                    Text("Active")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(DesignSystem.Colors.success)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(DesignSystem.Colors.successBackground)
                .clipShape(Capsule())
            }
            .padding(DesignSystem.Spacing.lg)

            Divider()
                .padding(.horizontal, DesignSystem.Spacing.md)

            // Account details section
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                Text("ACCOUNT DETAILS")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.bottom, 2)

                if let orgId = authViewModel.organizationId, !orgId.isEmpty {
                    detailRow(icon: "building.2", label: "Organization", value: orgId, copyKey: "org")
                }

                if let userId = authViewModel.userId, !userId.isEmpty {
                    detailRow(icon: "person.text.rectangle", label: "User ID", value: userId, copyKey: "user")
                }
            }
            .padding(DesignSystem.Spacing.lg)

            Divider()
                .padding(.horizontal, DesignSystem.Spacing.md)

            // Sign out
            Button {
                showingProfilePopover = false
                Task { await authViewModel.logout() }
            } label: {
                HStack(spacing: DesignSystem.Spacing.sm) {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(.subheadline)
                        .frame(width: 16)

                    Text("Sign Out")
                        .font(.subheadline)

                    Spacer()

                    KeyboardShortcutHint(keys: "")
                        .hidden() // Placeholder for alignment
                }
                .foregroundStyle(DesignSystem.Colors.error)
                .padding(.horizontal, DesignSystem.Spacing.lg)
                .padding(.vertical, DesignSystem.Spacing.md)
                .contentShape(Rectangle())
            }
            .buttonStyle(PopoverRowButtonStyle())
        }
        .frame(width: 300)
        .background(.ultraThinMaterial)
    }

    // MARK: - Detail Row

    private func detailRow(icon: String, label: String, value: String, copyKey: String) -> some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                Text(truncatedId(value))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(value, forType: .string)
                withAnimation(DesignSystem.Animation.quick) {
                    copiedField = copyKey
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    withAnimation(DesignSystem.Animation.quick) {
                        if copiedField == copyKey { copiedField = nil }
                    }
                }
            } label: {
                Image(systemName: copiedField == copyKey ? "checkmark" : "doc.on.doc")
                    .font(.caption2)
                    .foregroundStyle(copiedField == copyKey ? DesignSystem.Colors.success : Color.secondary)
            }
            .buttonStyle(.plain)
            .help("Copy to clipboard")
        }
        .padding(.vertical, 2)
    }

    private func truncatedId(_ id: String) -> String {
        if id.count > 20 {
            return String(id.prefix(8)) + "..." + String(id.suffix(4))
        }
        return id
    }
}

// MARK: - Popover Row Button Style

private struct PopoverRowButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                isHovered ? Color.red.opacity(0.06) : Color.clear
            )
            .onHover { hovering in
                isHovered = hovering
            }
            .opacity(configuration.isPressed ? 0.7 : 1.0)
    }
}
