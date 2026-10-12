import Foundation

enum MemoryTransfer {
    static let prompt: String = {
        guard let url = Bundle.module.url(forResource: "memory-transfer.v1", withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        return text
    }()

    static func candidates(from rawText: String) -> [MemoryImportCandidate] {
        var section = "未分类"
        var candidates: [MemoryImportCandidate] = []
        for rawLine in rawText.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("## ") {
                section = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                continue
            }
            guard line.hasPrefix("- ") || line.hasPrefix("* ") else { continue }
            let value = String(line.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { continue }
            let lowered = (section + " " + value).lowercased()
            let inferred = lowered.contains("(inferred)")
            let sensitive = MemoryPrivacyPolicy.isSensitive(lowered)
            candidates.append(MemoryImportCandidate(
                category: section,
                value: value,
                sourceText: value,
                isInferred: inferred,
                isSensitive: sensitive,
                isSelected: !inferred && !sensitive
            ))
        }
        return candidates
    }

    static func normalizedKey(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

}
