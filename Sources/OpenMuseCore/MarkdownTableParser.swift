import Foundation

struct ParsedMarkdownTable: Identifiable, Equatable {
    let id: Int
    let rows: [[String]]

    var columnCount: Int { rows.map(\.count).max() ?? 0 }
}

enum MarkdownTableParser {
    struct ParsedBlock {
        let table: ParsedMarkdownTable
        let lastLineIndex: Int
    }

    static func parse(lines: [String], startingAt index: Int) -> ParsedBlock? {
        guard index >= 0, index + 1 < lines.count else { return nil }
        let header = cells(in: lines[index])
        let separator = cells(in: lines[index + 1])
        guard !header.isEmpty,
              !separator.isEmpty,
              hasUnescapedPipe(in: lines[index]) || hasUnescapedPipe(in: lines[index + 1]),
              separator.allSatisfy(isSeparatorCell),
              separator.count == header.count else { return nil }

        var rows = [header]
        var lastLineIndex = index + 1
        var cursor = index + 2
        while cursor < lines.count {
            let line = lines[cursor]
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty,
                  hasUnescapedPipe(in: line) else { break }
            let row = cells(in: line)
            guard !row.isEmpty else { break }
            rows.append(row)
            lastLineIndex = cursor
            cursor += 1
        }

        let columnCount = rows.map(\.count).max() ?? header.count
        let rectangularRows = rows.map { row in
            row + Array(repeating: "", count: max(0, columnCount - row.count))
        }
        return ParsedBlock(
            table: ParsedMarkdownTable(id: index, rows: rectangularRows),
            lastLineIndex: lastLineIndex
        )
    }

    static func cells(in line: String) -> [String] {
        let characters = Array(line.trimmingCharacters(in: .whitespaces))
        guard !characters.isEmpty else { return [] }

        var result: [String] = []
        var cell = ""
        var index = 0
        var activeCodeDelimiterLength = 0

        while index < characters.count {
            let character = characters[index]

            if character == "\\", index + 1 < characters.count, characters[index + 1] == "|" {
                cell.append("|")
                index += 2
                continue
            }

            if character == "`" {
                var delimiterLength = 1
                while index + delimiterLength < characters.count,
                      characters[index + delimiterLength] == "`" {
                    delimiterLength += 1
                }
                if activeCodeDelimiterLength == 0 {
                    activeCodeDelimiterLength = delimiterLength
                } else if activeCodeDelimiterLength == delimiterLength {
                    activeCodeDelimiterLength = 0
                }
                cell += String(repeating: "`", count: delimiterLength)
                index += delimiterLength
                continue
            }

            if character == "|", activeCodeDelimiterLength == 0 {
                result.append(cell.trimmingCharacters(in: .whitespaces))
                cell = ""
            } else {
                cell.append(character)
            }
            index += 1
        }
        result.append(cell.trimmingCharacters(in: .whitespaces))

        if characters.first == "|", result.first?.isEmpty == true { result.removeFirst() }
        if characters.last == "|", result.last?.isEmpty == true { result.removeLast() }
        return result
    }

    private static func hasUnescapedPipe(in line: String) -> Bool {
        let characters = Array(line)
        var index = 0
        var activeCodeDelimiterLength = 0
        while index < characters.count {
            if characters[index] == "\\", index + 1 < characters.count, characters[index + 1] == "|" {
                index += 2
                continue
            }
            if characters[index] == "`" {
                var delimiterLength = 1
                while index + delimiterLength < characters.count,
                      characters[index + delimiterLength] == "`" {
                    delimiterLength += 1
                }
                if activeCodeDelimiterLength == 0 {
                    activeCodeDelimiterLength = delimiterLength
                } else if activeCodeDelimiterLength == delimiterLength {
                    activeCodeDelimiterLength = 0
                }
                index += delimiterLength
                continue
            }
            if characters[index] == "|", activeCodeDelimiterLength == 0 { return true }
            index += 1
        }
        return false
    }

    private static func isSeparatorCell(_ value: String) -> Bool {
        var characters = Array(value.trimmingCharacters(in: .whitespaces))
        if characters.first == ":" { characters.removeFirst() }
        if characters.last == ":" { characters.removeLast() }
        return characters.count >= 3 && characters.allSatisfy { $0 == "-" }
    }
}
