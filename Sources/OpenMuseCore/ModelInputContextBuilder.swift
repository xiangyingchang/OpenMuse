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
        [referenceOpen, referenceClose, currentOpen, currentClose].reduce(content) { result, marker in
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
        referenceData: String,
        parentContext: [TranscriptMessage],
        recentMessages: [TranscriptMessage],
        contextWindow: Int
    ) -> ModelInputContextSnapshot {
        let budget = inputBudget(contextWindow: contextWindow)
        var remaining = budget
        var wasTruncated = false

        let systemCap = min(budget, max(128, budget * 2 / 5))
        let fittedSystem = fit(systemPrompt, to: systemCap, marker: "\n[系统提示按模型上下文窗口截短；保留了开头和结尾的行为边界。]")
        wasTruncated = wasTruncated || fittedSystem.truncated
        remaining = max(0, remaining - PromptContextBuilder.estimateTokens(fittedSystem.text))

        // PromptContextBuilder already limits reference data to at most a quarter of
        // the declared window. Keep that bound when recent chat is also present.
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
        let referenceEnvelope = fittedReference.text.isEmpty
            ? ""
            : "\(ModelPromptEnvelope.referenceOpen)\n\(fittedReference.text)\n\(ModelPromptEnvelope.referenceClose)"
        if !referenceEnvelope.isEmpty {
            remaining = max(0, remaining - PromptContextBuilder.estimateTokens(referenceEnvelope))
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
                ModelPromptEnvelope.escapingEnvelopeMarkers(in: current.content),
                to: max(0, remaining - wrapperCost),
                marker: "\n[本条消息因模型上下文窗口限制已截短。]"
            )
            fittedCurrent = TranscriptMessage(role: current.role, content: "\(currentPrefix)\(fitted.text)\(currentSuffix)")
            currentMessageTruncated = fitted.truncated
            wasTruncated = wasTruncated || fitted.truncated
            remaining = max(0, remaining - PromptContextBuilder.estimateTokens(fittedCurrent?.content ?? ""))
        }

        let parentCap = min(remaining, max(0, budget / 6))
        var selectedParent = [TranscriptMessage]()
        var parentRemaining = parentCap
        var parentContextTruncated = false
        for message in parentContext.reversed() {
            guard parentRemaining > 0 else { wasTruncated = true; parentContextTruncated = true; break }
            let fitted = fit(message.content, to: parentRemaining, marker: "\n[主聊摘录因本轮总上下文预算已截短。]")
            guard !fitted.text.isEmpty else { wasTruncated = true; parentContextTruncated = true; continue }
            selectedParent.append(TranscriptMessage(role: message.role, content: fitted.text))
            let cost = PromptContextBuilder.estimateTokens(fitted.text)
            parentRemaining = max(0, parentRemaining - cost)
            wasTruncated = wasTruncated || fitted.truncated
            parentContextTruncated = parentContextTruncated || fitted.truncated
            if fitted.truncated { break }
        }
        selectedParent.reverse()
        remaining = max(0, remaining - (parentCap - parentRemaining))

        var selectedOlder = [TranscriptMessage]()
        var historyTruncated = false
        for message in older.reversed() {
            guard remaining > 0 else { wasTruncated = true; historyTruncated = true; break }
            let fitted = fit(message.content, to: remaining, marker: "\n[较早聊天因本轮总上下文预算已截短。]")
            guard !fitted.text.isEmpty else { wasTruncated = true; historyTruncated = true; continue }
            selectedOlder.append(TranscriptMessage(role: message.role, content: fitted.text))
            let cost = PromptContextBuilder.estimateTokens(fitted.text)
            remaining = max(0, remaining - cost)
            wasTruncated = wasTruncated || fitted.truncated
            historyTruncated = historyTruncated || fitted.truncated
            if fitted.truncated { break }
        }
        selectedOlder.reverse()

        var result = [TranscriptMessage(role: "system", content: fittedSystem.text)]
        result += selectedParent
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
