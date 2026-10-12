import CryptoKit
import Foundation

/// Builds the three editable Markdown views from the same structured memory claims.
/// Claim records remain the only source of truth; generated blocks are projections.
enum MemoryDocumentProjection {
    static let userBegin = "<!-- OPENMUSE_USER_MEMORY_BEGIN -->"
    static let userEnd = "<!-- OPENMUSE_USER_MEMORY_END -->"
    static let memoryBegin = "<!-- OPENMUSE_MEMORY_LEDGER_BEGIN -->"
    static let memoryEnd = "<!-- OPENMUSE_MEMORY_LEDGER_END -->"
    static let globalBegin = "<!-- OPENMUSE_GLOBAL_MEMORY_INDEX_BEGIN -->"
    static let globalEnd = "<!-- OPENMUSE_GLOBAL_MEMORY_INDEX_END -->"

    static func user(_ document: WorkspaceDocument, claims: [MemoryClaimRecord], asOf: Date = .now) -> String {
        let profileClaims = currentClaims(claims, asOf: asOf)
            .filter { $0.scope == "user" && isProfileCategory($0.category) }
            .sorted(by: claimOrder)
        let entries = profileClaims.map { claim in
            "\(claimMarker(claim.id))\n- \(safeValue(claim.value))\(annotation(for: claim, detailed: false))"
        }.joined(separator: "\n")
        return replacingManagedBlock(
            in: document.content,
            begin: userBegin,
            end: userEnd,
            heading: "## OpenMuse 自动维护的当前用户摘要",
            generated: entries,
            removesLegacyClaimEntries: true
        )
    }

    static func memory(_ document: WorkspaceDocument, claims: [MemoryClaimRecord], asOf: Date = .now) -> String {
        let active = currentClaims(claims, asOf: asOf).sorted {
            let left = indexCategory($0.category)
            let right = indexCategory($1.category)
            return left == right ? claimOrder($0, $1) : left.localizedStandardCompare(right) == .orderedAscending
        }
        let groups = Dictionary(grouping: active, by: { indexCategory($0.category) })
        let entries = groups.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }.map { category in
            let lines = (groups[category] ?? []).sorted(by: claimOrder).map { claim in
                "<a id=\"claim-\(anchorID(claim.id))\"></a>\n\(claimMarker(claim.id))\n- \(safeValue(claim.value))\(annotation(for: claim, detailed: true))"
            }
            return "### \(safeMarkdownText(category))\n\(lines.joined(separator: "\n"))"
        }.joined(separator: "\n\n")
        return replacingManagedBlock(
            in: document.content,
            begin: memoryBegin,
            end: memoryEnd,
            heading: "## 当前有效的结构化记忆",
            generated: entries,
            removesLegacyClaimEntries: true
        )
    }

    static func global(_ document: WorkspaceDocument, claims: [MemoryClaimRecord], asOf: Date = .now) -> String {
        let active = currentClaims(claims, asOf: asOf)
        let groups = Dictionary(grouping: active, by: { indexCategory($0.category) })
        let entries = groups.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }.map { category in
            let links = (groups[category] ?? []).sorted(by: claimOrder).map { claim in
                let label = String(oneLine(claim.value).prefix(48))
                let suffix = oneLine(claim.value).count > 48 ? "…" : ""
                return "\(claimMarker(claim.id))\n- [\(safeMarkdownText(label))\(suffix)](MEMORY.md#claim-\(anchorID(claim.id)))"
            }
            return "### \(safeMarkdownText(category))\n\(links.joined(separator: "\n"))"
        }.joined(separator: "\n\n")
        return replacingManagedBlock(
            in: document.content,
            begin: globalBegin,
            end: globalEnd,
            heading: "## OpenMuse 自动维护的主题索引",
            generated: entries,
            removesLegacyClaimEntries: true
        )
    }

    static func claimMarker(_ id: String) -> String {
        "<!-- openmuse-memory-claim:\(id) -->"
    }

    private static func currentClaims(_ claims: [MemoryClaimRecord], asOf: Date) -> [MemoryClaimRecord] {
        claims.filter { $0.status == "active" && PromptContextBuilder.isWithinValidity($0, asOf: asOf) }
    }

    private static func claimOrder(_ lhs: MemoryClaimRecord, _ rhs: MemoryClaimRecord) -> Bool {
        if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
        return lhs.id < rhs.id
    }

    private static func isProfileCategory(_ raw: String) -> Bool {
        let category = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let profileTerms = [
            "identity", "location", "residence", "work", "profession", "job", "routine", "preference",
            "communication", "interest", "hobby", "health", "diet", "value", "fact", "durable", "偏好",
            "身份", "地点", "居住", "工作", "职业", "习惯", "沟通", "兴趣", "爱好", "健康", "饮食", "事实", "长期"
        ]
        return profileTerms.contains(where: category.contains)
    }

    private static func indexCategory(_ raw: String) -> String {
        let category = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = category.lowercased()
        if ["identity", "location", "residence", "身份", "地点", "居住"].contains(where: lowered.contains) { return "身份与地点" }
        if ["work", "profession", "job", "project", "职业", "工作", "项目"].contains(where: lowered.contains) { return "工作与项目" }
        if ["preference", "communication", "interest", "hobby", "routine", "value", "偏好", "沟通", "兴趣", "爱好", "习惯", "价值"].contains(where: lowered.contains) { return "偏好、兴趣与习惯" }
        if ["relationship", "people", "关系", "人物"].contains(where: lowered.contains) { return "关系" }
        if ["health", "diet", "健康", "饮食"].contains(where: lowered.contains) { return "健康与饮食" }
        if ["tool", "environment", "工具", "环境"].contains(where: lowered.contains) { return "工具与环境" }
        return category.isEmpty ? "其他长期记忆" : "其他长期记忆 · \(category)"
    }

    private static func annotation(for claim: MemoryClaimRecord, detailed: Bool) -> String {
        let date = dateString(claim.createdAt)
        let validity = validitySuffix(for: claim)
        let label: String
        switch claim.sourceType {
        case "explicit-user-message": label = "明确表达"
        case "user-edit": label = "用户编辑"
        case "dreaming-approved": label = "经你确认的回顾建议；仍标记为模型推断"
        case "ai-memory-import": label = "来自其他 AI 的\(safeMarkdownText(claim.category))资料\(claim.isInferred == true ? "；推断" : "")"
        default: label = claim.isInferred == true ? "推断" : "已确认资料"
        }
        let confidence = detailed ? "；可信度：\(String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), claim.confidence))" : ""
        let scope = detailed ? "；范围：\(safeMarkdownText(claim.scope))" : ""
        let category = detailed ? "；类别：\(safeMarkdownText(claim.category))" : ""
        return "（\(label)，\(date)\(validity)\(confidence)\(scope)\(category)）"
    }

    private static func validitySuffix(for claim: MemoryClaimRecord) -> String {
        let start = claim.validFrom.map { "自\(dateString($0))起" }
        let end = claim.validUntil.map { "至\(dateString($0))" }
        guard start != nil || end != nil else { return "" }
        return "；有效期：\([start, end].compactMap { $0 }.joined(separator: " "))"
    }

    private static func dateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func oneLine(_ value: String) -> String {
        value.components(separatedBy: .newlines).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func safeValue(_ value: String) -> String {
        oneLine(value)
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func safeMarkdownText(_ value: String) -> String {
        oneLine(value)
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "[", with: "\\[")
            .replacingOccurrences(of: "]", with: "\\]")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func anchorID(_ id: String) -> String {
        SHA256.hash(data: Data(id.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func replacingManagedBlock(
        in original: String,
        begin: String,
        end: String,
        heading: String,
        generated: String,
        removesLegacyClaimEntries: Bool
    ) -> String {
        var content = original
        if let start = content.range(of: begin),
           let finish = content.range(of: end, range: start.upperBound..<content.endIndex) {
            content.replaceSubrange(start.lowerBound..<finish.upperBound, with: "")
        }
        if removesLegacyClaimEntries {
            content = removingLegacyClaimEntries(from: content)
        }
        content = content.trimmingCharacters(in: .newlines)
        guard !generated.isEmpty else { return content + (content.isEmpty ? "" : "\n") }

        let block = "\(begin)\n\(generated)\n\(end)"
        if content.components(separatedBy: .newlines).contains(heading) {
            return content + "\n" + block + "\n"
        }
        return (content.isEmpty ? "" : content + "\n\n") + heading + "\n" + block + "\n"
    }

    private static func removingLegacyClaimEntries(from content: String) -> String {
        let lines = content.components(separatedBy: .newlines)
        var result = [String]()
        var index = 0
        while index < lines.count {
            if lines[index].hasPrefix("<!-- openmuse-memory-claim:"), lines[index].hasSuffix(" -->") {
                index += 1
                if index < lines.count, lines[index].hasPrefix("- ") { index += 1 }
                continue
            }
            result.append(lines[index])
            index += 1
        }
        return result.joined(separator: "\n")
    }
}
