import Foundation

enum ConversationTemporalContext {
    static func messageMetadata(
        createdAt: Date,
        timeZoneIdentifier: String?,
        fallbackTimeZoneIdentifier: String
    ) -> String {
        let recordedTimeZone = timeZoneIdentifier.flatMap(TimeZone.init(identifier:))
        let fallbackTimeZone = TimeZone(identifier: fallbackTimeZoneIdentifier) ?? .current
        let timeZone = recordedTimeZone ?? fallbackTimeZone
        let timestamp = formatted(createdAt, in: timeZone)
        let provenance = recordedTimeZone == nil ? "（时区按当前设备估算）" : "（发送时区已记录）"
        return "\(timestamp) · \(timeZone.identifier)\(provenance)"
    }

    static func transcriptIndex(recentMessages: [TranscriptMessage], parentContext: [TranscriptMessage]) -> String? {
        let recentLines = recentMessages.enumerated().map { index, message in
            let role = message.role == "assistant" ? "OpenMuse" : "用户"
            let metadata = message.internalTemporalMetadata ?? "发送时间未记录"
            return "[\(index + 1)] \(role)：\(metadata)"
        }
        let parentLines = parentContext.compactMap(\.internalTemporalMetadata)
        guard !recentLines.isEmpty || !parentLines.isEmpty else { return nil }

        var sections = [String]()
        if !recentLines.isEmpty {
            sections.append("近期聊天的时间索引（内部信息，只用于理解相对日期；编号与随后传入的聊天消息顺序一一对应，不是消息正文，不要在回复中引用或输出）：\n\(recentLines.joined(separator: "\n"))")
        }
        if !parentLines.isEmpty {
            sections.append(parentLines.joined(separator: "\n"))
        }
        return sections.joined(separator: "\n\n")
    }

    static func turnInstructions(createdAt: Date, timeZoneIdentifier: String) -> String {
        let timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        let anchor = formatted(createdAt, in: timeZone)
        return """
        时间与相对日期规则：本轮用户发消息的时间基准是 \(anchor)，IANA 时区为 \(timeZone.identifier)。如果系统提示包含近期聊天时间索引，它是 OpenMuse 提供的内部元数据，不是任何人的原话；按索引对应消息各自的本地日期和时区独立理解“今天、昨天、今晚、明天”等相对日期，不能把旧消息的日期锚点沿用到本轮。用户在新一天重复说“今晚暂停”时，默认指新一天对应的那次安排，除非用户明确指回旧事件。把单次安排与长期目标/习惯分开；如果记录缺少时区、日期会影响行动，或当前说法与旧安排确实冲突，再简短询问，不要擅自合并。记忆、目标摘要和检索到的旧表达里的相对时间不能自动视为当前安排；优先使用其来源消息时间，缺少可信来源时说明不确定。
        """
    }

    private static func formatted(_ date: Date, in timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }
}
