import Foundation

struct SideConversationExcerpt: Sendable {
    let text: String
    let temporalIndex: String
}

enum SideConversationContext {
    static let maximumMessages = 4
    static let maximumCharactersPerMessage = 600

    static func excerpt(
        parentConversationID: String,
        messages: [MessageRecord],
        fallbackTimeZoneIdentifier: String = TimeZone.current.identifier
    ) -> String? {
        excerptWithTemporalIndex(
            parentConversationID: parentConversationID,
            messages: messages,
            fallbackTimeZoneIdentifier: fallbackTimeZoneIdentifier
        )?.text
    }

    static func excerptWithTemporalIndex(
        parentConversationID: String,
        messages: [MessageRecord],
        fallbackTimeZoneIdentifier: String = TimeZone.current.identifier
    ) -> SideConversationExcerpt? {
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
        let entries = recent.enumerated().map { index, message in
            let speaker = message.role == .user ? "用户" : "OpenMuse"
            let content = String(message.content.prefix(maximumCharactersPerMessage))
            let truncation = message.content.count > maximumCharactersPerMessage ? "…[已截短]" : ""
            let date = ConversationTemporalContext.messageMetadata(
                createdAt: message.createdAt,
                timeZoneIdentifier: message.timeZoneIdentifier,
                fallbackTimeZoneIdentifier: fallbackTimeZoneIdentifier
            )
            return (text: "[\(index + 1)] \(speaker)：\(content)\(truncation)", date: "[\(index + 1)] \(date)")
        }
        return SideConversationExcerpt(
            text: entries.map(\.text).joined(separator: "\n\n"),
            temporalIndex: "主聊摘录的时间索引（内部信息，编号对应引用内容中的 [n]，仅用于理解相对日期，不是消息正文，不要在回复中引用或输出）：\n\(entries.map(\.date).joined(separator: "\n"))"
        )
    }
}
