import Foundation

public struct PersonaRefinementCandidate: Equatable, Sendable {
    public let habit: String
    public let reason: String

    public init(habit: String, reason: String) {
        self.habit = habit
        self.reason = reason
    }
}

public enum PersonaRefinement {
    private static let sectionTitle = "## OpenMuse 根据用户反馈调整的习惯"

    /// Only turns direct, recurring-style feedback into one of a small set of safe collaboration habits.
    /// It cannot alter the user's mission, tool permissions, or safety boundaries.
    public static func candidate(from text: String) -> PersonaRefinementCandidate? {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty,
              !["是不是", "我朋友", "我同事", "有人说", "如果你", "假如你"].contains(where: normalized.contains)
        else { return nil }

        let lower = normalized.lowercased()
        let styleContext = ["学习", "陪伴", "聊天", "语气", "表达", "回复", "回答", "计划", "旅行", "说话"]
        guard styleContext.contains(where: lower.contains) else { return nil }

        if lower.contains("太严肃") || lower.contains("过于严肃") || lower.contains("太正式") {
            return PersonaRefinementCandidate(
                habit: "涉及学习、旅行或计划时保持轻松自然，像一起商量，不采用训练或考核口吻。",
                reason: "你反馈最近的陪伴方式显得太严肃。"
            )
        }

        if ["太啰嗦", "太冗长", "回复太长", "回答太长", "说得太长"].contains(where: lower.contains) {
            return PersonaRefinementCandidate(
                habit: "先给简洁、可用的答复；只有任务需要时再展开细节。",
                reason: "你反馈回复需要更简洁。"
            )
        }

        if ["问太多", "问题太多", "别问那么多", "不要问那么多"].contains(where: lower.contains) {
            return PersonaRefinementCandidate(
                habit: "先利用已有上下文；每次只问真正影响下一步的必要问题。",
                reason: "你反馈澄清问题过多。"
            )
        }

        return nil
    }

    static func appending(_ habit: String, to content: String) -> String? {
        let bullet = "- \(habit)"
        var lines = content.components(separatedBy: .newlines)
        if let sectionIndex = lines.firstIndex(of: sectionTitle) {
            let nextHeading = lines[(sectionIndex + 1)..<lines.endIndex].firstIndex(where: { $0.hasPrefix("## ") }) ?? lines.endIndex
            guard !lines[(sectionIndex + 1)..<nextHeading].contains(bullet) else { return nil }
            var insertionIndex = nextHeading
            while insertionIndex > sectionIndex + 1 && lines[insertionIndex - 1].isEmpty { insertionIndex -= 1 }
            lines.insert(bullet, at: insertionIndex)
            return lines.joined(separator: "\n")
        }
        guard !lines.contains(bullet) else { return nil }
        let separator = content.hasSuffix("\n") ? "\n" : "\n\n"
        return content + separator + sectionTitle + "\n" + bullet + "\n"
    }

    static func removing(_ habit: String, from content: String) -> String? {
        let bullet = "- \(habit)"
        var lines = content.components(separatedBy: .newlines)
        guard let sectionIndex = lines.firstIndex(of: sectionTitle) else { return nil }
        let nextHeading = lines[(sectionIndex + 1)..<lines.endIndex].firstIndex(where: { $0.hasPrefix("## ") }) ?? lines.endIndex
        guard let index = lines[(sectionIndex + 1)..<nextHeading].firstIndex(of: bullet) else { return nil }
        lines.remove(at: index)
        let currentNextHeading = lines[(sectionIndex + 1)..<lines.endIndex].firstIndex(where: { $0.hasPrefix("## ") }) ?? lines.endIndex
        let hasOtherSectionContent = lines[(sectionIndex + 1)..<currentNextHeading].contains(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
        if !hasOtherSectionContent {
            lines.remove(at: sectionIndex)
            if lines.indices.contains(sectionIndex), lines[sectionIndex].isEmpty { lines.remove(at: sectionIndex) }
            if sectionIndex > 0, lines.indices.contains(sectionIndex - 1), lines[sectionIndex - 1].isEmpty { lines.remove(at: sectionIndex - 1) }
        }
        return lines.joined(separator: "\n")
    }
}
