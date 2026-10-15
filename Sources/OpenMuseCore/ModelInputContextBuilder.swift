import Foundation

struct ModelInputContextSnapshot: Sendable {
    let messages: [TranscriptMessage]
    let estimatedInputTokens: Int
    let inputBudgetTokens: Int
    let truncated: Bool
    let currentMessageTruncated: Bool
    let referenceDataTruncated: Bool
    let parentContextTruncated: Bool
    let historyTruncated: Bool
}

enum ModelPromptEnvelope {
    static let referenceOpen = "<openmuse-reference-data>"
    static let referenceClose = "</openmuse-reference-data>"
    static let currentOpen = "<openmuse-current-message>"
    static let currentClose = "</openmuse-current-message>"
    static let parentOpen = "<openmuse-parent-conversation>"
    static let parentClose = "</openmuse-parent-conversation>"
    static let attachmentOpen = "<openmuse-attachment"
    static let attachmentClose = "</openmuse-attachment>"

    private static let boundaryMarkers = [
        referenceOpen, referenceClose, currentOpen, currentClose,
    ]

    private static let allEnvelopeMarkers = boundaryMarkers + [
        parentOpen, parentClose, attachmentOpen, attachmentClose,
        "<!-- OPENMUSE_USER_MEMORY_BEGIN -->",
        "<!-- OPENMUSE_USER_MEMORY_END -->",
        "<!-- OPENMUSE_MEMORY_LEDGER_BEGIN -->",
        "<!-- OPENMUSE_MEMORY_LEDGER_END -->",
        "<!-- OPENMUSE_GLOBAL_MEMORY_INDEX_BEGIN -->",
        "<!-- OPENMUSE_GLOBAL_MEMORY_INDEX_END -->",
        "<!-- OPENMUSE_HEARTBEAT_PLAN_BEGIN -->",
        "<!-- OPENMUSE_HEARTBEAT_PLAN_END -->",
        "<!-- openmuse-memory-claim:"
    ]

    static func currentMessage(from content: String) -> String {
        guard let opening = content.range(of: currentOpen),
              let closing = content.range(of: currentClose, range: opening.upperBound..<content.endIndex) else {
            return content
        }
        return String(content[opening.upperBound..<closing.lowerBound])
    }

    static func currentRequest(from messages: [TranscriptMessage]) -> String? {
        guard let content = messages.last(where: { $0.role == "user" })?.content else { return nil }
        return currentMessage(from: content)
    }

    static func escapingEnvelopeMarkers(in content: String) -> String {
        allEnvelopeMarkers.reduce(content) { result, marker in
            let escaped = marker
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
            return result.replacingOccurrences(of: marker, with: escaped, options: .caseInsensitive)
        }
    }

    static func escapingCurrentMessageMarkers(in content: String) -> String {
        boundaryMarkers.reduce(content) { result, marker in
            let escaped = marker
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
            return result.replacingOccurrences(of: marker, with: escaped, options: .caseInsensitive)
        }
    }
}

/// Fits all user-controlled context into one estimated model window. The estimate is
/// intentionally conservative and provider-independent; it is not a tokenizer.
enum ModelInputContextBuilder {
    static func outputTokenLimit(contextWindow: Int) -> Int {
        min(4_096, max(64, max(1, contextWindow) / 8))
    }

    static func inputBudget(contextWindow: Int) -> Int {
        let window = max(1, contextWindow)
        let outputReserve = outputTokenLimit(contextWindow: window)
        let requestOverhead = min(256, max(32, window / 64))
        return max(1, window - outputReserve - requestOverhead)
    }

    static func build(
        systemPrompt: String,
        protectedSystemSuffix: String = "",
        referenceData: String,
        parentContext: [TranscriptMessage],
        recentMessages: [TranscriptMessage],
        contextWindow: Int
    ) -> ModelInputContextSnapshot {
        let budget = inputBudget(contextWindow: contextWindow)
        var remaining = budget
        var wasTruncated = false

        let systemCap = min(budget, max(128, budget * 2 / 5))
        let temporalReserve = min(640, systemCap / 4)
        let protectedSuffixBudget = max(0, systemCap - temporalReserve - min(128, systemCap / 4))
        let fittedProtectedSuffix = fit(
            protectedSystemSuffix,
            to: protectedSuffixBudget,
            marker: "\n[必要的本轮处理规则因模型上下文窗口限制已截短。]"
        )
        let protectedSuffixCost = PromptContextBuilder.estimateTokens(fittedProtectedSuffix.text)
        let fittedSystem = fit(
            systemPrompt,
            to: max(1, systemCap - temporalReserve - protectedSuffixCost),
            marker: "\n[系统提示按模型上下文窗口截短；保留了开头和结尾的行为边界。]"
        )
        wasTruncated = wasTruncated || fittedSystem.truncated
        wasTruncated = wasTruncated || fittedProtectedSuffix.truncated
        remaining = max(0, remaining - PromptContextBuilder.estimateTokens(fittedSystem.text) - protectedSuffixCost - temporalReserve)

        // PromptContextBuilder already limits reference data to at most a quarter of
        // the declared window. Parent-chat excerpts share the reference envelope so
        // they cannot become a separate user turn that looks like a new request.
        let referenceWrapper = "\(ModelPromptEnvelope.referenceOpen)\n\n\(ModelPromptEnvelope.referenceClose)"
        let referenceWrapperCost = PromptContextBuilder.estimateTokens(referenceWrapper)
        let referenceCap = min(max(64, budget / 4), remaining)
        let fittedReference = fit(
            ModelPromptEnvelope.escapingEnvelopeMarkers(in: referenceData),
            to: max(0, referenceCap - referenceWrapperCost),
            marker: "\n[部分记忆与资料因本轮总上下文预算未载入。]"
        )
        let referenceDataTruncated = fittedReference.truncated
        wasTruncated = wasTruncated || fittedReference.truncated
        var referenceSections = [String]()
        if !fittedReference.text.isEmpty { referenceSections.append(fittedReference.text) }
        let fittedMemoryEnvelopeCost = fittedReference.text.isEmpty
            ? 0
            : PromptContextBuilder.estimateTokens("\(ModelPromptEnvelope.referenceOpen)\n\(fittedReference.text)\n\(ModelPromptEnvelope.referenceClose)")
        remaining = max(0, remaining - fittedMemoryEnvelopeCost)

        let parentCap = min(remaining, max(0, budget / 6))
        var selectedParent = [TranscriptMessage]()
        var parentRemaining = parentCap
        var parentContextTruncated = false
        for message in parentContext.reversed() {
            guard parentRemaining > 0 else { wasTruncated = true; parentContextTruncated = true; break }
            let fitted = fit(
                ModelPromptEnvelope.escapingEnvelopeMarkers(in: message.content),
                to: parentRemaining,
                marker: "\n[主聊摘录因本轮总上下文预算已截短。]"
            )
            guard !fitted.text.isEmpty else { wasTruncated = true; parentContextTruncated = true; continue }
            selectedParent.append(TranscriptMessage(
                role: message.role,
                content: fitted.text,
                internalTemporalMetadata: message.internalTemporalMetadata
            ))
            let cost = PromptContextBuilder.estimateTokens(fitted.text)
            parentRemaining = max(0, parentRemaining - cost)
            wasTruncated = wasTruncated || fitted.truncated
            parentContextTruncated = parentContextTruncated || fitted.truncated
            if fitted.truncated { break }
        }
        selectedParent.reverse()
        if !selectedParent.isEmpty {
            let parentText = selectedParent.map { message in
                "\(message.role == "assistant" ? "OpenMuse" : "用户")：\(message.content)"
            }.joined(separator: "\n\n")
            referenceSections.append("\(ModelPromptEnvelope.parentOpen)\n\(parentText)\n\(ModelPromptEnvelope.parentClose)")
            remaining = max(0, remaining - (parentCap - parentRemaining))
        }
        let referenceEnvelope = referenceSections.isEmpty
            ? ""
            : "\(ModelPromptEnvelope.referenceOpen)\n\(referenceSections.joined(separator: "\n\n"))\n\(ModelPromptEnvelope.referenceClose)"
        // Account for the reference wrappers and the separator not counted above.
        if !referenceEnvelope.isEmpty {
            let alreadyAccountedFor = fittedMemoryEnvelopeCost + (parentCap - parentRemaining)
            let actualCost = PromptContextBuilder.estimateTokens(referenceEnvelope)
            remaining = max(0, remaining - max(0, actualCost - alreadyAccountedFor))
        }

        let current = recentMessages.last
        let older = Array(recentMessages.dropLast())
        var fittedCurrent: TranscriptMessage?
        var currentMessageTruncated = false
        if let current {
            let currentWrapper = "\(ModelPromptEnvelope.currentOpen)\n\n\(ModelPromptEnvelope.currentClose)"
            let currentPrefix = referenceEnvelope.isEmpty
                ? "\(ModelPromptEnvelope.currentOpen)\n"
                : "\(referenceEnvelope)\n\n\(ModelPromptEnvelope.currentOpen)\n"
            let currentSuffix = "\n\(ModelPromptEnvelope.currentClose)"
            let wrapperCost = PromptContextBuilder.estimateTokens(currentWrapper)
                + (referenceEnvelope.isEmpty ? 0 : PromptContextBuilder.estimateTokens("\n\n"))
            let fitted = fit(
                ModelPromptEnvelope.escapingCurrentMessageMarkers(in: current.content),
                to: max(0, remaining - wrapperCost),
                marker: "\n[本条消息因模型上下文窗口限制已截短。]"
            )
            fittedCurrent = TranscriptMessage(
                role: current.role,
                content: "\(currentPrefix)\(fitted.text)\(currentSuffix)",
                internalTemporalMetadata: current.internalTemporalMetadata
            )
            currentMessageTruncated = fitted.truncated
            wasTruncated = wasTruncated || fitted.truncated
            let embeddedReferenceCost = referenceEnvelope.isEmpty
                ? 0
                : PromptContextBuilder.estimateTokens(referenceEnvelope)
            let currentOnlyCost = max(
                0,
                PromptContextBuilder.estimateTokens(fittedCurrent?.content ?? "") - embeddedReferenceCost
            )
            remaining = max(0, remaining - currentOnlyCost)
        }

        var selectedOlder = [TranscriptMessage]()
        var historyTruncated = false
        for message in older.reversed() {
            guard remaining > 0 else { wasTruncated = true; historyTruncated = true; break }
            let fitted = fit(message.content, to: remaining, marker: "\n[较早聊天因本轮总上下文预算已截短。]")
            guard !fitted.text.isEmpty else { wasTruncated = true; historyTruncated = true; continue }
            selectedOlder.append(TranscriptMessage(
                role: message.role,
                content: fitted.text,
                internalTemporalMetadata: message.internalTemporalMetadata
            ))
            let cost = PromptContextBuilder.estimateTokens(fitted.text)
            remaining = max(0, remaining - cost)
            wasTruncated = wasTruncated || fitted.truncated
            historyTruncated = historyTruncated || fitted.truncated
            if fitted.truncated { break }
        }
        selectedOlder.reverse()

        let retainedConversation = selectedOlder + (fittedCurrent.map { [$0] } ?? [])
        let temporalIndex = ConversationTemporalContext.transcriptIndex(
            recentMessages: retainedConversation,
            parentContext: selectedParent
        )
        let fittedTemporalIndex: String
        if let temporalIndex {
            let fitted = fit(
                temporalIndex,
                to: temporalReserve,
                marker: "\n[部分聊天时间索引因上下文预算省略。]"
            )
            fittedTemporalIndex = fitted.text
            wasTruncated = wasTruncated || fitted.truncated
        } else {
            fittedTemporalIndex = ""
        }
        let systemSections = [fittedSystem.text, fittedProtectedSuffix.text, fittedTemporalIndex]
            .filter { !$0.isEmpty }
        let completeSystem = systemSections.joined(separator: "\n\n")
        var result = [TranscriptMessage(role: "system", content: completeSystem)]
        result += selectedOlder
        if let fittedCurrent { result.append(fittedCurrent) }

        let total = result.reduce(0) { $0 + PromptContextBuilder.estimateTokens($1.content) }
        return ModelInputContextSnapshot(
            messages: result,
            estimatedInputTokens: total,
            inputBudgetTokens: budget,
            truncated: wasTruncated || older.count != selectedOlder.count || parentContext.count != selectedParent.count,
            currentMessageTruncated: currentMessageTruncated,
            referenceDataTruncated: referenceDataTruncated,
            parentContextTruncated: parentContextTruncated || parentContext.count != selectedParent.count,
            historyTruncated: historyTruncated || older.count != selectedOlder.count
        )
    }

    private static func fit(_ text: String, to tokenBudget: Int, marker: String) -> (text: String, truncated: Bool) {
        guard tokenBudget > 0 else { return ("", !text.isEmpty) }
        let fullCost = PromptContextBuilder.estimateTokens(text)
        guard fullCost > tokenBudget else { return (text, false) }

        let markerCost = PromptContextBuilder.estimateTokens(marker)
        let contentBudget = max(0, tokenBudget - markerCost)
        let prefixAndSuffix = max(0, contentBudget)
        let prefixBudget = prefixAndSuffix * 2 / 3
        let suffixBudget = prefixAndSuffix - prefixBudget
        let prefix = fittingPrefix(text, tokenBudget: prefixBudget)
        let suffix = fittingSuffix(text, tokenBudget: suffixBudget)
        let fitted = prefix + marker + suffix
        if PromptContextBuilder.estimateTokens(fitted) <= tokenBudget { return (fitted, true) }
        return (fittingPrefix(text, tokenBudget: tokenBudget), true)
    }

    private static func fittingPrefix(_ text: String, tokenBudget: Int) -> String {
        guard tokenBudget > 0 else { return "" }
        let characters = Array(text)
        var low = 0
        var high = characters.count
        while low < high {
            let middle = (low + high + 1) / 2
            if PromptContextBuilder.estimateTokens(String(characters.prefix(middle))) <= tokenBudget { low = middle }
            else { high = middle - 1 }
        }
        return String(characters.prefix(low))
    }

    private static func fittingSuffix(_ text: String, tokenBudget: Int) -> String {
        guard tokenBudget > 0 else { return "" }
        let characters = Array(text)
        var low = 0
        var high = characters.count
        while low < high {
            let middle = (low + high + 1) / 2
            if PromptContextBuilder.estimateTokens(String(characters.suffix(middle))) <= tokenBudget { low = middle }
            else { high = middle - 1 }
        }
        return String(characters.suffix(low))
    }
}
