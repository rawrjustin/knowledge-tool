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
        case .success: return .green
        case .error: return .red
        case .info: return .blue
        }
    }
}

struct ToastView: View {
    let message: String
    let style: ToastStyle

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: style.icon)
                .foregroundStyle(style.color)

            Text(message)
                .font(.subheadline)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .cornerRadius(8)
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
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
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .padding(.top, 8)

                    Spacer()
                }
                .animation(.easeInOut(duration: 0.3), value: isShowing)
                .onAppear {
                    Task {
                        try? await Task.sleep(for: .seconds(duration))
                        await MainActor.run {
                            withAnimation {
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
    func toast(isShowing: Binding<Bool>, message: String, style: ToastStyle = .success, duration: Double = 2.0) -> some View {
        modifier(ToastModifier(isShowing: isShowing, message: message, style: style, duration: duration))
    }
}

// MARK: - Header View
struct HeaderView: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.largeTitle.bold())

            Text(subtitle)
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Processing View
struct ProcessingView: View {
    let state: ProcessingState

    var body: some View {
        HStack(spacing: 16) {
            ProgressView()
                .controlSize(.regular)

            if case .processing(let message) = state {
                Text(message)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.1))
        .cornerRadius(12)
    }
}

// MARK: - Error Banner
struct ErrorBanner: View {
    let message: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .font(.title3)

            Text(message)
                .font(.body)
                .foregroundStyle(.primary)

            Spacer()
        }
        .padding()
        .background(Color.red.opacity(0.1))
        .cornerRadius(12)
    }
}

// MARK: - Success Banner
struct SuccessBanner: View {
    let message: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.title3)

            Text(message)
                .font(.body)
                .foregroundStyle(.primary)

            Spacer()
        }
        .padding()
        .background(Color.green.opacity(0.1))
        .cornerRadius(12)
    }
}

// MARK: - Result Card
struct ResultCard: View {
    let title: String
    let icon: String
    let content: String
    let onExport: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(title, systemImage: icon)
                    .font(.headline)

                Spacer()

                Button {
                    onExport()
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)

                Button {
                    copyToClipboard(content)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
            }

            ScrollView {
                Text(content)
                    .textSelection(.enabled)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 400)
            .background(Color(nsColor: .textBackgroundColor))
            .cornerRadius(8)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
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

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            Text(title)
                .font(.title2.bold())

            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
