import Foundation

struct ChatLogMessage: Identifiable, Sendable {
    let id = UUID()
    let sender: String
    let content: String
    let isUser: Bool
    let timestamp: Date?
}

enum ChatLogParser {

    // Common user-side names to detect which side of the conversation is "user"
    private static let userIdentifiers: Set<String> = [
        "you", "me", "user", "human", "justin", "j"
    ]

    // Common AI/assistant names
    private static let assistantIdentifiers: Set<String> = [
        "assistant", "ai", "bot", "chatgpt", "gpt", "claude", "gemini",
        "copilot", "system", "siri", "alexa", "bard"
    ]

    /// Parse raw text into structured chat messages
    static func parse(_ rawText: String) -> [ChatLogMessage] {
        let lines = rawText.components(separatedBy: "\n")
        var messages: [ChatLogMessage] = []
        var currentSender: String?
        var currentContent: [String] = []
        var senderSet: Set<String> = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Skip empty lines within a message block
            if trimmed.isEmpty {
                if currentSender != nil {
                    currentContent.append("")
                }
                continue
            }

            // Try to detect a new speaker line
            if let (sender, content) = parseSpeakerLine(trimmed) {
                // Flush previous message
                if let prevSender = currentSender {
                    let text = currentContent.joined(separator: "\n")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !text.isEmpty {
                        let isUser = classifyAsUser(prevSender, allSenders: senderSet)
                        messages.append(ChatLogMessage(
                            sender: prevSender,
                            content: text,
                            isUser: isUser,
                            timestamp: nil
                        ))
                    }
                }

                currentSender = sender
                senderSet.insert(sender)
                currentContent = content.isEmpty ? [] : [content]
            } else {
                // Continuation of the current message
                if currentSender != nil {
                    currentContent.append(trimmed)
                } else {
                    // No sender detected yet - try to treat as first user message
                    currentSender = "User"
                    senderSet.insert("User")
                    currentContent = [trimmed]
                }
            }
        }

        // Flush last message
        if let prevSender = currentSender {
            let text = currentContent.joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                let isUser = classifyAsUser(prevSender, allSenders: senderSet)
                messages.append(ChatLogMessage(
                    sender: prevSender,
                    content: text,
                    isUser: isUser,
                    timestamp: nil
                ))
            }
        }

        // If we only found one sender, alternate user classification
        if senderSet.count == 1 {
            return alternateUserClassification(messages)
        }

        // Re-classify based on full conversation context
        return reclassifyMessages(messages, senderSet: senderSet)
    }

    /// Try to detect "SenderName: message" or "SenderName\nmessage" patterns
    private static func parseSpeakerLine(_ line: String) -> (sender: String, content: String)? {
        // Pattern 1: "Name: message" (with optional timestamp prefix)
        // Handles: "ChatGPT: Hello", "User: Hi", "**Claude**: text", "[10:30] Alice: hey"
        let patterns: [String] = [
            // Markdown bold: **Name**: message
            #"^\*\*(.+?)\*\*\s*:\s*(.*)"#,
            // Timestamp prefix: [HH:MM] Name: message or [HH:MM:SS] Name: message
            #"^\[[\d:]+\]\s*(.+?)\s*:\s*(.*)"#,
            // Timestamp prefix: HH:MM Name: message
            #"^\d{1,2}:\d{2}(?::\d{2})?\s+(.+?)\s*:\s*(.*)"#,
            // Standard: Name: message (name must be 1-40 chars, no colons)
            #"^([^:\n]{1,40}?)\s*:\s*(.*)"#,
        ]

        for pattern in patterns {
            if let match = line.range(of: pattern, options: .regularExpression) {
                let matchStr = String(line[match])
                if let result = extractSenderContent(from: matchStr, pattern: pattern) {
                    let sender = result.sender
                        .trimmingCharacters(in: .whitespaces)
                        .replacingOccurrences(of: "**", with: "")

                    // Validate sender name - must look like a name/role, not a sentence
                    if sender.count <= 40 && !sender.contains("  ") && sender.split(separator: " ").count <= 4 {
                        return (sender, result.content.trimmingCharacters(in: .whitespaces))
                    }
                }
            }
        }

        return nil
    }

    private static func extractSenderContent(from text: String, pattern: String) -> (sender: String, content: String)? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range) else { return nil }

        let senderRange = match.range(at: 1)
        guard let swiftSenderRange = Range(senderRange, in: text) else { return nil }
        let sender = String(text[swiftSenderRange])

        var content = ""
        if match.numberOfRanges > 2 {
            let contentRange = match.range(at: 2)
            if let swiftContentRange = Range(contentRange, in: text) {
                content = String(text[swiftContentRange])
            }
        }

        return (sender, content)
    }

    private static func classifyAsUser(_ sender: String, allSenders: Set<String>) -> Bool {
        let lower = sender.lowercased().trimmingCharacters(in: .whitespaces)
        if userIdentifiers.contains(lower) { return true }
        if assistantIdentifiers.contains(lower) { return false }

        // If there are exactly 2 senders, the one that appears to be more "human" is the user
        if allSenders.count == 2 {
            let otherSender = allSenders.first(where: { $0.lowercased() != lower })?.lowercased() ?? ""
            if assistantIdentifiers.contains(otherSender) { return true }
            if userIdentifiers.contains(otherSender) { return false }
        }

        return false
    }

    private static func alternateUserClassification(_ messages: [ChatLogMessage]) -> [ChatLogMessage] {
        messages.enumerated().map { index, msg in
            ChatLogMessage(
                sender: msg.sender,
                content: msg.content,
                isUser: index % 2 == 0,
                timestamp: msg.timestamp
            )
        }
    }

    private static func reclassifyMessages(_ messages: [ChatLogMessage], senderSet: Set<String>) -> [ChatLogMessage] {
        // If we have exactly 2 senders, figure out who's user vs assistant
        guard senderSet.count == 2 else { return messages }

        let senders = Array(senderSet)
        let first = senders[0].lowercased()
        let second = senders[1].lowercased()

        var firstIsUser: Bool?

        // Check explicit identifiers
        if userIdentifiers.contains(first) || assistantIdentifiers.contains(second) {
            firstIsUser = true
        } else if userIdentifiers.contains(second) || assistantIdentifiers.contains(first) {
            firstIsUser = false
        }

        // If still ambiguous, the first speaker is typically the user
        if firstIsUser == nil {
            if let firstMessage = messages.first {
                firstIsUser = firstMessage.sender == senders[0]
            } else {
                firstIsUser = true
            }
        }

        let userSender = firstIsUser! ? senders[0] : senders[1]

        return messages.map { msg in
            ChatLogMessage(
                sender: msg.sender,
                content: msg.content,
                isUser: msg.sender == userSender,
                timestamp: msg.timestamp
            )
        }
    }
}
