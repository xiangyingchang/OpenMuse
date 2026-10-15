import Foundation

/// Coalesces provider deltas for rendering without imposing a reading-speed delay.
struct StreamPresentationBuffer {
    static let shortReplyRefreshNanoseconds: UInt64 = 48_000_000
    static let mediumReplyRefreshNanoseconds: UInt64 = 64_000_000
    static let longReplyRefreshNanoseconds: UInt64 = 96_000_000
    static let paragraphFlushMinimumCharacters = 50
    static let paragraphFlushMaximumPresentedCharacters = 5_000

    private var pendingText = ""
    private(set) var pendingCharacterCount = 0

    var hasPendingText: Bool { !pendingText.isEmpty }

    mutating func append(_ text: String) {
        guard !text.isEmpty else { return }
        pendingText.append(contentsOf: text)
        pendingCharacterCount += text.count
    }

    func shouldFlushAtParagraphBoundary(presentedCharacterCount: Int) -> Bool {
        guard presentedCharacterCount < Self.paragraphFlushMaximumPresentedCharacters,
              pendingCharacterCount >= Self.paragraphFlushMinimumCharacters else { return false }
        return pendingText.contains("\n")
    }

    mutating func drain() -> String {
        guard hasPendingText else { return "" }
        let result = pendingText
        pendingText.removeAll(keepingCapacity: true)
        pendingCharacterCount = 0
        return result
    }

    static func refreshIntervalNanoseconds(presentedCharacterCount: Int) -> UInt64 {
        switch presentedCharacterCount {
        case ..<1_000: shortReplyRefreshNanoseconds
        case ..<5_000: mediumReplyRefreshNanoseconds
        default: longReplyRefreshNanoseconds
        }
    }
}
