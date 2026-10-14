import Foundation

/// Suppresses responses that repeat OpenMuse's private prompt and memory markers.
/// The short overlap buffer prevents a marker split across streaming chunks from
/// appearing in the chat before the complete marker can be recognized.
struct ModelResponseLeakGuard: Sendable {
    private(set) var didDetectInternalMarker = false
    private var pending = ""

    private static let markers = [
        ModelPromptEnvelope.referenceOpen,
        ModelPromptEnvelope.referenceClose,
        ModelPromptEnvelope.currentOpen,
        ModelPromptEnvelope.currentClose,
        "<!-- openmuse_user_memory_begin -->",
        "<!-- openmuse_user_memory_end -->",
        "<!-- openmuse_memory_ledger_begin -->",
        "<!-- openmuse_memory_ledger_end -->",
        "<!-- openmuse_global_memory_index_begin -->",
        "<!-- openmuse_global_memory_index_end -->",
        "<!-- openmuse-memory-claim:"
    ].map { $0.lowercased() }

    mutating func append(_ fragment: String) -> String {
        guard !didDetectInternalMarker else { return "" }
        pending += fragment
        let normalized = pending.lowercased()
        if Self.markers.contains(where: { normalized.contains($0) }) {
            didDetectInternalMarker = true
            pending = ""
            return ""
        }

        var withheldCharacters = 0
        for marker in Self.markers {
            let maximumOverlap = min(pending.count, marker.count - 1)
            guard maximumOverlap > 0 else { continue }
            for overlap in stride(from: maximumOverlap, through: 1, by: -1) {
                if normalized.hasSuffix(String(marker.prefix(overlap))) {
                    withheldCharacters = max(withheldCharacters, overlap)
                    break
                }
            }
        }

        let safeCount = pending.count - withheldCharacters
        let safe = String(pending.prefix(safeCount))
        pending = String(pending.suffix(withheldCharacters))
        return safe
    }

    mutating func finish() -> String {
        guard !didDetectInternalMarker else { return "" }
        if Self.markers.contains(where: { pending.lowercased().contains($0) }) {
            didDetectInternalMarker = true
            pending = ""
            return ""
        }
        let tail = pending
        pending = ""
        return tail
    }

    static func containsInternalMarker(_ text: String) -> Bool {
        let normalized = text.lowercased()
        return markers.contains(where: { normalized.contains($0) })
    }
}
