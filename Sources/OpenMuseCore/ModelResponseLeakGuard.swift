import Foundation

/// Blocks unmistakable OpenMuse prompt/reference artifacts and removes a small,
/// explicitly observed model self-narration sentence without discarding the
/// useful answer around it. The overlap buffer prevents either pattern from
/// appearing when a streaming provider splits it across chunks.
struct ModelResponseLeakGuard: Sendable {
    struct SanitizedResponse: Sendable {
        let text: String
        let didDetectInternalMarker: Bool
        let didRemoveLeakNarration: Bool
    }

    private(set) var didDetectInternalMarker = false
    private(set) var didRemoveLeakNarration = false
    private var pending = ""

    /// These are protocol envelopes and exact internal metadata labels. A hit
    /// means the model returned OpenMuse's serialized context, so the response
    /// must not be shown or saved.
    private static let internalMarkers = [
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

    /// Exact, previously observed self-narration sentences. They do not expose
    /// private context by themselves; remove them and keep the actual answer.
    /// Keep this list narrow so ordinary discussion of prompts or memories is
    /// not treated as an internal-context leak.
    private static let leakNarrationSentences = [
        "那段内部资料又漏出来了，忽略。",
        "那段内部资料又漏出来了，先忽略。",
        "那段内部资料又漏出来了。",
        "内部资料又漏出来了，忽略。",
        "内部资料又漏出来了。",
        "内部资料漏出来了，忽略。",
        "内部资料漏出来了。",
        "内部内容又漏出来了，忽略。",
        "内部上下文又漏出来了，忽略。",
        "提示词又漏出来了，忽略。",
        "系统提示又漏出来了，忽略。"
    ].map { $0.lowercased() }

    private static var allPatterns: [String] {
        internalMarkers + leakNarrationSentences
    }

    mutating func append(_ fragment: String) -> String {
        guard !didDetectInternalMarker else { return "" }
        pending += fragment
        return drain(final: false)
    }

    mutating func finish() -> String {
        guard !didDetectInternalMarker else {
            pending = ""
            return ""
        }
        return drain(final: true)
    }

    private mutating func drain(final: Bool) -> String {
        var output = ""
        var remaining = pending
        pending = ""

        while !remaining.isEmpty {
            let normalized = remaining.lowercased()
            if Self.internalMarkers.contains(where: { normalized.contains($0) }) {
                didDetectInternalMarker = true
                pending = ""
                return ""
            }

            if let match = Self.earliestMatch(in: remaining, patterns: Self.leakNarrationSentences) {
                output += String(remaining[..<match.lowerBound])
                remaining = String(remaining[match.upperBound...])
                didRemoveLeakNarration = true
                continue
            }

            guard !final else {
                output += remaining
                break
            }

            let withheldCharacters = Self.maximumPossiblePatternOverlap(in: normalized)
            let safeCount = remaining.count - withheldCharacters
            output += String(remaining.prefix(safeCount))
            pending = String(remaining.suffix(withheldCharacters))
            break
        }

        return output
    }

    static func sanitize(_ text: String) -> SanitizedResponse {
        var guardrail = ModelResponseLeakGuard()
        let safeText = guardrail.append(text) + guardrail.finish()
        return SanitizedResponse(
            text: safeText,
            didDetectInternalMarker: guardrail.didDetectInternalMarker,
            didRemoveLeakNarration: guardrail.didRemoveLeakNarration
        )
    }

    static func containsInternalMarker(_ text: String) -> Bool {
        let normalized = text.lowercased()
        return internalMarkers.contains(where: { normalized.contains($0) })
    }

    private static func earliestMatch(in text: String, patterns: [String]) -> Range<String.Index>? {
        patterns
            .compactMap { text.range(of: $0, options: [.caseInsensitive]) }
            .min { $0.lowerBound < $1.lowerBound }
    }

    private static func maximumPossiblePatternOverlap(in normalizedText: String) -> Int {
        allPatterns.reduce(into: 0) { withheldCharacters, pattern in
            let maximumOverlap = min(normalizedText.count, pattern.count - 1)
            guard maximumOverlap > withheldCharacters else { return }
            for overlap in stride(from: maximumOverlap, through: 1, by: -1) {
                if normalizedText.hasSuffix(String(pattern.prefix(overlap))) {
                    withheldCharacters = max(withheldCharacters, overlap)
                    break
                }
            }
        }
    }
}
