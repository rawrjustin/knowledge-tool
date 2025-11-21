import SwiftUI

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
