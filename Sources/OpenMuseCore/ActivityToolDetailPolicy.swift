import Foundation

/// Keeps inspectable tool-call details useful while preventing common
/// credential fields and unbounded payloads from being written to activity history.
public enum ActivityToolDetailPolicy {
    public static let maximumInputBytes = 8_192
    public static let maximumOutputBytes = 16_384
    public static let maximumErrorBytes = 2_048

    public static func input(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        return bounded(redact(raw), limit: maximumInputBytes)
    }

    public static func output(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        return bounded(redact(raw), limit: maximumOutputBytes)
    }

    public static func error(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        return bounded(redact(raw), limit: maximumErrorBytes)
    }

    public static func display(_ raw: String) -> String {
        let scalars = Array(raw.unicodeScalars)
        var cleaned = String.UnicodeScalarView()
        var index = 0
        while index < scalars.count {
            let scalar = scalars[index]
            if scalar.value == 0x1B {
                index += 1
                guard index < scalars.count else { continue }
                let marker = scalars[index].value
                index += 1
                if marker == 0x5B {
                    while index < scalars.count {
                        let value = scalars[index].value
                        index += 1
                        if (0x40...0x7E).contains(value) { break }
                    }
                } else if marker == 0x5D {
                    while index < scalars.count {
                        let value = scalars[index].value
                        index += 1
                        if value == 0x07 { break }
                        if value == 0x1B, index < scalars.count, scalars[index].value == 0x5C {
                            index += 1
                            break
                        }
                    }
                }
                continue
            }
            if scalar.value == 0x0A || scalar.value == 0x09 || scalar.value >= 0x20 {
                cleaned.append(scalar)
            } else {
                cleaned.append("�")
            }
            index += 1
        }
        return String(cleaned).components(separatedBy: "\n").map { line in
            guard line.count > 2_000 else { return line }
            return stride(from: 0, to: line.count, by: 2_000).map { start in
                let from = line.index(line.startIndex, offsetBy: start)
                let to = line.index(from, offsetBy: min(2_000, line.distance(from: from, to: line.endIndex)))
                return String(line[from..<to])
            }.joined(separator: "\n")
        }.joined(separator: "\n")
    }

    private static func redact(_ raw: String) -> String {
        if let data = raw.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data),
           let redacted = try? JSONSerialization.data(
               withJSONObject: redactJSON(object),
               options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed]
           ),
           let value = String(data: redacted, encoding: .utf8) {
            return redactInlineSecrets(value)
        }
        return redactInlineSecrets(raw)
    }

    private static func redactJSON(_ value: Any, key: String? = nil) -> Any {
        if let key, isSensitiveKey(key) { return "[已隐藏]" }
        if let dictionary = value as? [String: Any] {
            return dictionary.reduce(into: [String: Any]()) { result, pair in
                result[pair.key] = redactJSON(pair.value, key: pair.key)
            }
        }
        if let array = value as? [Any] { return array.map { redactJSON($0) } }
        if let string = value as? String { return redactInlineSecrets(string) }
        return value
    }

    private static func isSensitiveKey(_ key: String) -> Bool {
        let normalized = key.lowercased().filter(\.isLetterOrNumber)
        return normalized == "key" ||
            ["apikey", "accesstoken", "refreshtoken", "password", "passwd", "secret", "authorization", "cookie", "credential", "privatekey"]
                .contains(where: normalized.contains)
    }

    private static func redactInlineSecrets(_ value: String) -> String {
        let replacements: [(pattern: String, template: String)] = [
            (#"(?i)(Bearer\s+)[A-Za-z0-9._~+/=-]+"#, "$1[已隐藏]"),
            (#"(?i)\bsk-[A-Za-z0-9_-]{8,}\b"#, "[已隐藏 API 密钥]"),
            (#"(?i)((?:--?)?(?:api[_-]?key|access[_-]?token|refresh[_-]?token|password|passwd|secret|authorization|cookie)\s*(?:=|:)\s*)(?:\"[^\"]*\"|'[^']*'|[^\s,;&]+)"#, "$1[已隐藏]")
        ]
        return replacements.reduce(value) { result, replacement in
            result.replacingOccurrences(
                of: replacement.pattern,
                with: replacement.template,
                options: .regularExpression
            )
        }
    }

    private static func bounded(_ value: String, limit: Int) -> String {
        let data = Data(value.utf8)
        guard data.count > limit else { return value }
        let marker = "\n[详情已截断]"
        let prefixLimit = max(0, limit - marker.utf8.count)
        return String(decoding: data.prefix(prefixLimit), as: UTF8.self) + marker
    }
}

private extension Character {
    var isLetterOrNumber: Bool { isLetter || isNumber }
}
