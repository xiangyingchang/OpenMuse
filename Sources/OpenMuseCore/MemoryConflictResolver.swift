import Foundation

enum MemoryConflictResolver {
    private static let replacementPhrases = ["更喜欢", "现在偏好", "目前偏好", "现在喜欢", "目前喜欢", "改成", "改为", "调整为", "不再", "其实", "更新为"]
    private static let removablePhrases = [
        "以后请记得", "以后请", "记住", "我目前更喜欢", "我现在更喜欢", "我更喜欢", "我不喜欢", "我喜欢", "我偏好", "我目前喜欢", "我现在喜欢", "我通常", "我平时"
    ]
    private static let genericWords: Set<String> = ["旅行", "旅游", "计划", "目标", "事情", "内容", "偏好", "喜欢", "我", "你", "他们", "现在", "目前", "以后"]
    private static let genericCharacters = Set("旅行计划目标事情内容偏好喜欢我你他她它们的和与".map(String.init))
    private static let latinStopWords: Set<String> = ["the", "and", "for", "with", "prefer", "like", "likes", "now", "currently", "user"]

    /// Only explicit correction language can supersede a prior preference. Similarity alone
    /// is never enough to rewrite a user's history. A direct current-residence statement or
    /// relocation can also supersede an older residence, but never a place-of-origin record.
    static func claimsToSupersede(for newValue: String, among claims: [MemoryClaimRecord], asOf: Date = .now) -> [MemoryClaimRecord] {
        let normalized = normalize(newValue)
        let newCategory = IntentCapture.explicitMemoryCategory(for: newValue)
        if newCategory == "location", locationField(normalized) == .residence {
            return claims.filter { claim in
                claim.status == "active" && claim.category == "location" && claim.scope == "user" &&
                PromptContextBuilder.isWithinValidity(claim, asOf: asOf) && locationField(normalize(claim.value)) == .residence
            }
        }
        guard newCategory == "preference", replacementPhrases.contains(where: normalized.contains) else { return [] }
        let newTerms = topicTerms(normalized)
        guard !newTerms.isEmpty else { return [] }

        return claims.filter { claim in
            guard claim.status == "active", claim.category == "preference", claim.scope == "user",
                  PromptContextBuilder.isWithinValidity(claim, asOf: asOf) else { return false }
            let overlap = newTerms.intersection(topicTerms(claim.value))
            return !overlap.isEmpty
        }
    }

    private enum LocationField {
        case residence
        case origin
        case other
    }

    private static func locationField(_ text: String) -> LocationField? {
        if IntentCapture.hasExplicitCurrentResidence(text) { return .residence }
        let hasRelocation = ["搬到", "搬去", "迁到"].contains(where: text.contains)
        if hasRelocation && !IntentCapture.hasPlannedRelocation(text) { return .residence }
        if ["来自", "老家", "籍贯", "出生于"].contains(where: text.contains) { return .origin }
        return nil
    }

    private static func topicTerms(_ rawValue: String) -> Set<String> {
        var text = normalize(rawValue)
        for phrase in removablePhrases { text = text.replacingOccurrences(of: phrase, with: " ") }
        var terms = Set(text.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init).filter {
            $0.count >= 3 && !latinStopWords.contains($0)
        })
        let cjk = Array(text).filter { character in
            character.unicodeScalars.contains { (0x4E00...0x9FFF).contains(Int($0.value)) }
        }
        if cjk.count >= 2 {
            for index in 0..<(cjk.count - 1) {
                let term = String(cjk[index...index + 1])
                guard !term.contains(where: { genericCharacters.contains(String($0)) }) else { continue }
                if !genericWords.contains(term) { terms.insert(term) }
            }
        }
        return terms
    }

    private static func normalize(_ value: String) -> String {
        value.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
