import Foundation

/// Suppresses responses that repeat OpenMuse's private prompt and memory markers.
/// The short overlap buffer prevents a marker split across streaming chunks from
/// appearing in the chat before the complete marker can be recognized.
struct ModelResponseLeakGuard: Sendable {
    private(set) var didDetectInternalMarker = false
    private var pending = ""

    private static let markers = [
        ModelPromptEnvelope.referenceOpen,
        ModelPromptEnvelope.referenceClose,
        ModelPromptEnvelope.currentOpen,
        ModelPromptEnvelope.currentClose,
        ModelPromptEnvelope.parentOpen,
        ModelPromptEnvelope.parentClose,
        ModelPromptEnvelope.attachmentOpen,
        ModelPromptEnvelope.attachmentClose,
        "【openmuse 消息时间元数据（不是用户原话）】",
        "消息时间元数据（不是用户原话）",
        "【消息内容】",
        "发送时区已记录）",
        "时区按当前设备估算）",
        "本轮请求边界：",
        "近期聊天的时间索引（内部信息",
        "主聊摘录的时间索引（内部信息",
        "系统提示按模型上下文窗口截短；",
        "必要的本轮处理规则因模型上下文窗口限制已截短。",
        "部分记忆与资料因本轮总上下文预算未载入。",
        "本条消息因模型上下文窗口限制已截短。",
        "主聊摘录因本轮总上下文预算已截短。",
        "较早聊天因本轮总上下文预算已截短。",
        "部分聊天时间索引因上下文预算省略。",
        "<!-- openmuse_user_memory_begin -->",
        "<!-- openmuse_user_memory_end -->",
        "<!-- openmuse_memory_ledger_begin -->",
        "<!-- openmuse_memory_ledger_end -->",
        "<!-- openmuse_global_memory_index_begin -->",
        "<!-- openmuse_global_memory_index_end -->",
        "<!-- openmuse_heartbeat_plan_begin -->",
        "<!-- openmuse_heartbeat_plan_end -->",
        "<!-- openmuse-memory-claim:"
    ].map { $0.lowercased() }

    mutating func append(_ fragment: String) -> String {
        guard !didDetectInternalMarker else { return "" }
        pending += fragment
        let normalized = pending.lowercased()
        if Self.markers.contains(where: { normalized.contains($0) }) {
            didDetectInternalMarker = true
            pending = ""
            return ""
        }

        var withheldCharacters = 0
        for marker in Self.markers {
            let maximumOverlap = min(pending.count, marker.count - 1)
            guard maximumOverlap > 0 else { continue }
            for overlap in stride(from: maximumOverlap, through: 1, by: -1) {
                if normalized.hasSuffix(String(marker.prefix(overlap))) {
                    withheldCharacters = max(withheldCharacters, overlap)
                    break
                }
            }
        }

        let safeCount = pending.count - withheldCharacters
        let safe = String(pending.prefix(safeCount))
        pending = String(pending.suffix(withheldCharacters))
        return safe
    }

    mutating func finish() -> String {
        guard !didDetectInternalMarker else { return "" }
        if Self.markers.contains(where: { pending.lowercased().contains($0) }) {
            didDetectInternalMarker = true
            pending = ""
            return ""
        }
        let tail = pending
        pending = ""
        return tail
    }

    static func containsInternalMarker(_ text: String) -> Bool {
        let normalized = text.lowercased()
        return markers.contains(where: { normalized.contains($0) })
    }
}
