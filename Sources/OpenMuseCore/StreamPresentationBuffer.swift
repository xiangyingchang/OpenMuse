import Foundation

struct StreamPresentationUnit: Equatable {
    let text: String
    let delayNanoseconds: UInt64
}

/// Separates the provider's token rate from the pace at which a reply appears on screen.
/// Chinese characters are revealed at about 300 characters per minute; Latin text is
/// revealed one word at a time. The full response remains available to fast-forward.
struct StreamPresentationBuffer {
    static let baseDelayNanoseconds: UInt64 = 200_000_000
    static let commaPauseNanoseconds: UInt64 = 100_000_000
    static let sentencePauseNanoseconds: UInt64 = 220_000_000

    private var characters: [Character] = []
    private var readIndex = 0

    var hasPendingText: Bool { readIndex < characters.count }

    mutating func append(_ text: String) {
        guard !text.isEmpty else { return }
        characters.append(contentsOf: text)
    }

    mutating func takeNextUnit(streamIsFinished: Bool) -> StreamPresentationUnit? {
        guard readIndex < characters.count else { return nil }
        let startIndex = readIndex
        var text = ""

        while readIndex < characters.count, characters[readIndex].isWhitespace {
            text.append(characters[readIndex])
            readIndex += 1
        }
        guard readIndex < characters.count else {
            if !streamIsFinished {
                readIndex = startIndex
                return nil
            }
            compactIfNeeded()
            return text.isEmpty ? nil : StreamPresentationUnit(text: text, delayNanoseconds: Self.baseDelayNanoseconds)
        }

        let first = characters[readIndex]
        if Self.isCJK(first) {
            text.append(first)
            readIndex += 1
            while readIndex < characters.count, Self.isAttachablePunctuation(characters[readIndex]) {
                text.append(characters[readIndex])
                readIndex += 1
            }
        } else if Self.isWordCharacter(first) {
            while readIndex < characters.count, Self.isWordCharacter(characters[readIndex]) {
                text.append(characters[readIndex])
                readIndex += 1
            }
            if readIndex == characters.count, !streamIsFinished {
                readIndex = startIndex
                return nil
            }
            if readIndex < characters.count, Self.isAttachablePunctuation(characters[readIndex]) {
                while readIndex < characters.count, Self.isAttachablePunctuation(characters[readIndex]) {
                    text.append(characters[readIndex])
                    readIndex += 1
                }
            }
            if readIndex < characters.count, characters[readIndex].isWhitespace {
                text.append(characters[readIndex])
                readIndex += 1
            }
        } else {
            text.append(first)
            readIndex += 1
            while readIndex < characters.count,
                  !Self.isCJK(characters[readIndex]),
                  !Self.isWordCharacter(characters[readIndex]),
                  !characters[readIndex].isWhitespace {
                text.append(characters[readIndex])
                readIndex += 1
            }
        }

        let delay = Self.baseDelayNanoseconds + Self.punctuationPause(for: text)
        compactIfNeeded()
        return StreamPresentationUnit(text: text, delayNanoseconds: delay)
    }

    mutating func drain() -> String {
        guard readIndex < characters.count else { return "" }
        let result = String(characters[readIndex...])
        characters.removeAll(keepingCapacity: false)
        readIndex = 0
        return result
    }

    private mutating func compactIfNeeded() {
        guard readIndex == characters.count else {
            if readIndex >= 1_024, readIndex * 2 >= characters.count {
                characters.removeFirst(readIndex)
                readIndex = 0
            }
            return
        }
        characters.removeAll(keepingCapacity: true)
        readIndex = 0
    }

    private static func isCJK(_ character: Character) -> Bool {
        guard let scalar = character.unicodeScalars.first else { return false }
        switch scalar.value {
        case 0x2E80...0x2FFF, 0x3000...0x30FF, 0x3100...0x31FF,
             0x3400...0x4DBF, 0x4E00...0x9FFF, 0xAC00...0xD7AF,
             0xF900...0xFAFF, 0x20000...0x3134F:
            return true
        default:
            return false
        }
    }

    private static func isWordCharacter(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { scalar in
            CharacterSet.alphanumerics.contains(scalar) || scalar == "'" || scalar == "’" || scalar == "-"
        }
    }

    private static func isAttachablePunctuation(_ character: Character) -> Bool {
        let punctuation = CharacterSet(charactersIn: ".,!?;:。！？；：，、)]}）】」』”’\"'…—–")
        return character.unicodeScalars.allSatisfy(punctuation.contains)
    }

    private static func punctuationPause(for text: String) -> UInt64 {
        let terminal = CharacterSet(charactersIn: ".!?。！？…")
        let pause = CharacterSet(charactersIn: ",;:，、；：")
        if text.unicodeScalars.contains(where: terminal.contains) { return sentencePauseNanoseconds }
        if text.unicodeScalars.contains(where: pause.contains) { return commaPauseNanoseconds }
        return 0
    }
}
