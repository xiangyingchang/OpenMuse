import Foundation

/// Produces the human-readable Markdown view without changing the saved source.
/// OpenMuse's HTML comments and claim anchors stay in the editable document because
/// memory projections use them to write changes back to their structured records.
enum MarkdownDocumentDisplaySource {
    static func readableMarkdown(from source: String) -> String {
        let sourceLines = source.components(separatedBy: .newlines)
        var visibleLines: [String] = []
        var insideHTMLComment = false
        var activeFence: MarkdownFence?

        for line in sourceLines {
            if let fence = activeFence {
                visibleLines.append(line)
                if fence.closes(line) { activeFence = nil }
                continue
            }

            if !insideHTMLComment, let fence = MarkdownFence.opening(in: line) {
                visibleLines.append(line)
                activeFence = fence
                continue
            }

            var visibleLine = removingHTMLComments(from: line, insideComment: &insideHTMLComment)
            visibleLine = removingClaimAnchors(from: visibleLine)
            visibleLines.append(visibleLine)
        }

        return joiningSoftWrappedLines(visibleLines)
    }

    static func memoryClaimDisplay(in line: String) -> (value: String, metadata: String)? {
        guard line.hasPrefix("- "),
              let opening = line.lastIndex(of: "（"),
              line.hasSuffix("）") else { return nil }

        let valueStart = line.index(line.startIndex, offsetBy: 2)
        let value = String(line[valueStart..<opening]).trimmingCharacters(in: .whitespaces)
        let annotation = String(line[line.index(after: opening)..<line.index(before: line.endIndex)])
        guard let separator = annotation.firstIndex(of: "，") else { return nil }
        let sourceLabel = String(annotation[..<separator])
        let knownLabels = ["明确表达", "用户编辑", "推断", "已确认资料"]
        guard knownLabels.contains(sourceLabel)
                || sourceLabel.hasPrefix("经你确认的回顾建议")
                || (sourceLabel.hasPrefix("来自其他 AI 的") && sourceLabel.contains("资料")) else { return nil }

        let dateStart = annotation.index(after: separator)
        let remaining = annotation[dateStart...]
        guard remaining.count >= 10 else { return nil }
        let dateEnd = remaining.index(dateStart, offsetBy: 10)
        let date = String(annotation[dateStart..<dateEnd])
        guard date.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else { return nil }

        let remainder = String(annotation[dateEnd...])
        let fields = remainder.split(separator: "；").map(String.init)
        let validity = fields.first(where: { $0.hasPrefix("有效期：") })
        let confidence = fields.first(where: { $0.hasPrefix("可信度：") })
            .flatMap { field -> String? in
                guard let raw = field.split(separator: "：").last,
                      let value = Double(raw) else { return nil }
                return "可信度：\(Int((value * 100).rounded()))%"
            }

        var source = "来源：\(sourceDisplayName(for: sourceLabel))"
        if sourceLabel.contains("推断") || sourceLabel == "推断" { source += " · 推断" }
        var metadata = [source, "记录于 \(date)"]
        if let validity { metadata.append(validity) }
        if let confidence { metadata.append(confidence) }
        return (value, metadata.joined(separator: " · "))
    }

    private static func sourceDisplayName(for label: String) -> String {
        if label.hasPrefix("明确表达") { return "明确表达" }
        if label.hasPrefix("用户编辑") { return "你修改的记录" }
        if label.hasPrefix("经你确认的回顾建议") { return "回顾建议" }
        if label.hasPrefix("来自其他 AI 的") { return "从其他 AI 导入" }
        if label == "推断" { return "模型推断" }
        return "已确认资料"
    }

    private static func removingHTMLComments(from line: String, insideComment: inout Bool) -> String {
        var result = ""
        var remaining = line[...]

        while !remaining.isEmpty {
            if insideComment {
                guard let close = remaining.range(of: "-->") else { return result }
                remaining = remaining[close.upperBound...]
                insideComment = false
                continue
            }

            guard let open = remaining.range(of: "<!--") else {
                result += remaining
                break
            }
            result += remaining[..<open.lowerBound]
            remaining = remaining[open.upperBound...]
            insideComment = true
        }

        return result
    }

    private static func removingClaimAnchors(from line: String) -> String {
        let pattern = #"<a\s+id\s*=\s*[\"']claim-[^\"']+[\"']\s*>\s*</a>"#
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return line }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        return expression.stringByReplacingMatches(in: line, range: range, withTemplate: "")
    }

    private static func joiningSoftWrappedLines(_ lines: [String]) -> String {
        var result: [String] = []
        var paragraph: [String] = []
        var activeFence: MarkdownFence?
        var index = 0

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            result.append(paragraph.joined(separator: " "))
            paragraph.removeAll(keepingCapacity: true)
        }

        while index < lines.count {
            let line = lines[index]

            if let fence = activeFence {
                result.append(line)
                if fence.closes(line) { activeFence = nil }
                index += 1
                continue
            }

            if let fence = MarkdownFence.opening(in: line) {
                flushParagraph()
                result.append(line)
                activeFence = fence
                index += 1
                continue
            }

            if let table = MarkdownTableParser.parse(lines: lines, startingAt: index) {
                flushParagraph()
                result.append(contentsOf: lines[index...table.lastLineIndex])
                index = table.lastLineIndex + 1
                continue
            }

            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                flushParagraph()
                if result.last?.isEmpty != true { result.append("") }
            } else if isBlockLine(trimmed) {
                flushParagraph()
                result.append(trimmed)
            } else if line.hasSuffix("  ") || trimmed.hasSuffix("\\") {
                flushParagraph()
                result.append(trimmed)
            } else {
                paragraph.append(trimmed)
            }

            index += 1
        }

        flushParagraph()
        while result.last?.isEmpty == true { result.removeLast() }
        return result.joined(separator: "\n")
    }

    private static func isBlockLine(_ line: String) -> Bool {
        if line.hasPrefix(">"), line == ">" || line.hasPrefix("> ") { return true }
        if ["---", "***", "___"].contains(line) { return true }
        if line.first == "#" {
            let hashes = line.prefix(while: { $0 == "#" }).count
            if (1...6).contains(hashes), line.dropFirst(hashes).first?.isWhitespace == true { return true }
        }
        if ["- ", "* ", "+ "].contains(where: line.hasPrefix) { return true }
        if let delimiter = line.firstIndex(where: { $0 == "." || $0 == ")" || $0 == "、" }),
           line[..<delimiter].allSatisfy(\.isNumber),
           line.index(after: delimiter) < line.endIndex,
           line[line.index(after: delimiter)].isWhitespace {
            return true
        }
        return false
    }
}

private struct MarkdownFence {
    let marker: Character
    let minimumLength: Int

    static func opening(in line: String) -> MarkdownFence? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let marker = trimmed.first, marker == "`" || marker == "~" else { return nil }
        let length = trimmed.prefix(while: { $0 == marker }).count
        guard length >= 3 else { return nil }
        return MarkdownFence(marker: marker, minimumLength: length)
    }

    func closes(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.prefix(while: { $0 == marker }).count >= minimumLength
    }
}
