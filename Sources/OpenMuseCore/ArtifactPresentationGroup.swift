import Foundation

/// Groups same-named records for a compact chat presentation without merging or
/// discarding the underlying artifacts. Every record remains individually openable.
struct ArtifactPresentationGroup: Identifiable, Equatable {
    let id: String
    let records: [ArtifactRecord]

    var latest: ArtifactRecord {
        records[0]
    }

    static func make(from artifacts: [ArtifactRecord]) -> [ArtifactPresentationGroup] {
        let grouped = Dictionary(grouping: artifacts) { artifact in
            let normalizedTitle = artifact.title
                .split(whereSeparator: \.isWhitespace)
                .joined(separator: " ")
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
                .lowercased()
            return normalizedTitle.isEmpty ? "record:\(artifact.id)" : "\(artifact.kind.lowercased()):\(normalizedTitle)"
        }

        return grouped.map { key, records in
            ArtifactPresentationGroup(
                id: key,
                records: records.sorted {
                    if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
                    return $0.id < $1.id
                }
            )
        }
        .sorted {
            if $0.latest.updatedAt != $1.latest.updatedAt { return $0.latest.updatedAt > $1.latest.updatedAt }
            return $0.id < $1.id
        }
    }
}
