import SwiftUI
import AppKit

@MainActor @Observable
final class ChatLogViewModel {
    var rawText: String = ""
    var messages: [ChatLogMessage] = []
    var isParsed: Bool = false
    var isExporting: Bool = false
    var exportScale: CGFloat = 2.0
    var showExportSuccess: Bool = false
    var title: String = "Chat Log"

    func parseInput() {
        guard !rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        messages = ChatLogParser.parse(rawText)
        isParsed = true

        // Auto-detect title from first assistant message sender
        if let firstAssistant = messages.first(where: { !$0.isUser }) {
            title = "\(firstAssistant.sender) Chat"
        }
    }

    func reset() {
        rawText = ""
        messages = []
        isParsed = false
        title = "Chat Log"
    }

    @MainActor
    func exportAsPNG(chatView: some View, width: CGFloat) {
        isExporting = true
        defer { isExporting = false }

        let renderer = ImageRenderer(content: chatView)
        renderer.scale = exportScale
        renderer.proposedSize = ProposedViewSize(width: width, height: nil)

        guard let nsImage = renderer.nsImage else { return }

        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.png]
        savePanel.nameFieldStringValue = "\(title.replacingOccurrences(of: " ", with: "_")).png"
        savePanel.canCreateDirectories = true

        guard savePanel.runModal() == .OK, let url = savePanel.url else { return }

        guard let tiffData = nsImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:])
        else { return }

        do {
            try pngData.write(to: url)
            showExportSuccess = true
            // Auto-dismiss success after 2 seconds
            Task {
                try? await Task.sleep(for: .seconds(2))
                showExportSuccess = false
            }
        } catch {
            NSLog("[ChatLogExport] Failed to write PNG: %@", error.localizedDescription)
        }
    }
}
