import Foundation

enum SideConversationContext {
    static let maximumMessages = 4
    static let maximumCharactersPerMessage = 600

    static func excerpt(
        parentConversationID: String,
        messages: [MessageRecord],
        fallbackTimeZoneIdentifier: String = TimeZone.current.identifier
    ) -> String? {
        let recent = messages
            .filter {
                $0.conversationID == parentConversationID &&
                $0.status == "complete" &&
                $0.importedFrom == nil &&
                !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            .sorted { $0.createdAt < $1.createdAt }
            .suffix(maximumMessages)
        guard !recent.isEmpty else { return nil }
        return recent.map { message in
            let speaker = message.role == .user ? "用户" : "OpenMuse"
            let content = String(message.content.prefix(maximumCharactersPerMessage))
            let truncation = message.content.count > maximumCharactersPerMessage ? "…[已截短]" : ""
            let date = ConversationTemporalContext.messageMetadata(
                createdAt: message.createdAt,
                timeZoneIdentifier: message.timeZoneIdentifier,
                fallbackTimeZoneIdentifier: fallbackTimeZoneIdentifier
            )
            return "[\(date)] \(speaker)：\(content)\(truncation)"
        }.joined(separator: "\n\n")
    }
}
