import SwiftUI

struct LoginView: View {
    @Bindable var authViewModel: AuthViewModel
    @Environment(\.colorScheme) private var colorScheme

    @FocusState private var isEmailFocused: Bool
    @FocusState private var isCodeFocused: Bool
    @State private var appeared = false
    @State private var meshPhase: CGFloat = 0

    var body: some View {
        ZStack {
            // Animated mesh gradient background
            backgroundMesh
                .ignoresSafeArea()

            // Content card
            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 0) {
                    // Header
                    headerSection
                        .padding(.bottom, 28)

                    // Animated step content
                    VStack(spacing: DesignSystem.Spacing.xl) {
                        switch authViewModel.loginStep {
                        case .enterEmail:
                            emailStep
                                .transition(.asymmetric(
                                    insertion: .move(edge: .leading).combined(with: .opacity),
                                    removal: .move(edge: .leading).combined(with: .opacity)
                                ))
                        case .enterCode:
                            codeStep
                                .transition(.asymmetric(
                                    insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .move(edge: .trailing).combined(with: .opacity)
                                ))
                        }
                    }
                    .animation(DesignSystem.Animation.smooth, value: authViewModel.loginStep)
                    .frame(width: 340)

                    // Error message
                    if let error = authViewModel.errorMessage {
                        errorBanner(error)
                            .padding(.top, DesignSystem.Spacing.lg)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .padding(DesignSystem.Spacing.xxxl)
                .padding(.horizontal, DesignSystem.Spacing.lg)
                .background {
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.xl)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.xl)
                                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(colorScheme == .dark ? 0.5 : 0.1), radius: 40, y: 12)
                }
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 16)

                Spacer()

                // Footer
                HStack(spacing: DesignSystem.Spacing.xs) {
                    Image(systemName: "lock.shield.fill")
                        .font(.caption2)
                    Text("Secured by Genies authentication")
                        .font(.caption2)
                }
                .foregroundStyle(.secondary.opacity(0.6))
                .padding(.bottom, DesignSystem.Spacing.xl)
                .opacity(appeared ? 1 : 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(DesignSystem.Animation.standard, value: authViewModel.errorMessage != nil)
        .onAppear {
            withAnimation(.easeOut(duration: 0.6).delay(0.1)) {
                appeared = true
            }
            withAnimation(.linear(duration: 20).repeatForever(autoreverses: true)) {
                meshPhase = 1
            }
        }
    }

    // MARK: - Background

    private var backgroundMesh: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)

            // Soft gradient orbs
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.blue.opacity(0.08), Color.clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 300
                    )
                )
                .frame(width: 600, height: 600)
                .offset(
                    x: -120 + 60 * sin(meshPhase * .pi * 2),
                    y: -200 + 40 * cos(meshPhase * .pi * 2)
                )

            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.purple.opacity(0.06), Color.clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 250
                    )
                )
                .frame(width: 500, height: 500)
                .offset(
                    x: 180 + 50 * cos(meshPhase * .pi * 2),
                    y: 120 + 30 * sin(meshPhase * .pi * 2)
                )

            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.cyan.opacity(0.05), Color.clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 200
                    )
                )
                .frame(width: 400, height: 400)
                .offset(
                    x: -60 + 40 * cos(meshPhase * .pi * 2 + 1),
                    y: 200 + 50 * sin(meshPhase * .pi * 2 + 1)
                )
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            // App icon from bundle
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 80, height: 80)
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.4 : 0.15), radius: 12, y: 4)

            VStack(spacing: DesignSystem.Spacing.xs) {
                Text("Knowledge Tool")
                    .font(.title2.weight(.bold))

                Text("Sign in with your Genies account")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Email Step

    private var emailStep: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                Text("Email")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)

                TextField("you@genies.com", text: $authViewModel.email)
                    .textFieldStyle(.plain)
                    .textContentType(.emailAddress)
                    .font(.body)
                    .padding(.horizontal, DesignSystem.Spacing.md)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                            .stroke(
                                isEmailFocused ? Color.accentColor.opacity(0.5) : DesignSystem.Colors.inputBorder,
                                lineWidth: isEmailFocused ? 1.5 : 1
                            )
                    )
                    .focused($isEmailFocused)
                    .onSubmit {
                        Task { await authViewModel.requestMagicLink() }
                    }
                    .disabled(authViewModel.isLoading)
            }

            Button {
                Task { await authViewModel.requestMagicLink() }
            } label: {
                HStack(spacing: DesignSystem.Spacing.sm) {
                    if authViewModel.isLoading {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                    } else {
                        Image(systemName: "paperplane.fill")
                            .font(.subheadline)
                    }
                    Text(authViewModel.isLoading ? "Sending..." : "Continue")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
            .buttonStyle(.modernPrimary)
            .controlSize(.large)
            .disabled(authViewModel.email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || authViewModel.isLoading)
        }
        .onAppear { isEmailFocused = true }
    }

    // MARK: - Code Step

    private var codeStep: some View {
        VStack(spacing: DesignSystem.Spacing.xl) {
            // Sent indicator
            VStack(spacing: DesignSystem.Spacing.sm) {
                ZStack {
                    Circle()
                        .fill(DesignSystem.Colors.infoBackground)
                        .frame(width: 44, height: 44)

                    Image(systemName: "envelope.open.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(DesignSystem.Colors.info)
                }

                Text("Check your inbox")
                    .font(.headline)

                Text("We sent a 6-digit code to")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text(authViewModel.email)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
            }

            // Code input
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                Text("Verification code")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)

                TextField("000000", text: $authViewModel.verificationCode)
                    .textFieldStyle(.plain)
                    .font(.system(size: 22, weight: .semibold, design: .monospaced))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, DesignSystem.Spacing.md)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                            .stroke(
                                isCodeFocused ? Color.accentColor.opacity(0.5) : DesignSystem.Colors.inputBorder,
                                lineWidth: isCodeFocused ? 1.5 : 1
                            )
                    )
                    .focused($isCodeFocused)
                    .onSubmit {
                        Task { await authViewModel.verifyCode() }
                    }
                    .disabled(authViewModel.isLoading)
            }

            // Verify button
            Button {
                Task { await authViewModel.verifyCode() }
            } label: {
                HStack(spacing: DesignSystem.Spacing.sm) {
                    if authViewModel.isLoading {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                    } else {
                        Image(systemName: "checkmark.shield.fill")
                            .font(.subheadline)
                    }
                    Text(authViewModel.isLoading ? "Verifying..." : "Sign In")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
            .buttonStyle(.modernPrimary)
            .controlSize(.large)
            .disabled(authViewModel.verificationCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || authViewModel.isLoading)

            // Secondary actions
            HStack(spacing: 0) {
                Button {
                    withAnimation(DesignSystem.Animation.smooth) {
                        authViewModel.goBackToEmail()
                    }
                } label: {
                    HStack(spacing: DesignSystem.Spacing.xs) {
                        Image(systemName: "chevron.left")
                            .font(.caption2.weight(.semibold))
                        Text("Change email")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    Task { await authViewModel.requestMagicLink() }
                } label: {
                    Text("Resend code")
                        .font(.subheadline)
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
                .disabled(authViewModel.isLoading)
            }
        }
        .onAppear { isCodeFocused = true }
    }

    // MARK: - Error Banner

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.subheadline)
                .foregroundStyle(DesignSystem.Colors.error)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(DesignSystem.Colors.error)
                .lineLimit(2)

            Spacer(minLength: 0)
        }
        .padding(DesignSystem.Spacing.md)
        .frame(maxWidth: 340)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                .fill(DesignSystem.Colors.errorBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                        .stroke(DesignSystem.Colors.error.opacity(0.2), lineWidth: 1)
                )
        )
    }
}
