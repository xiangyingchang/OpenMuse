import Foundation

enum ChatTimelineEntry: Identifiable, Equatable {
    case message(MessageRecord)
    case artifactGroup(ArtifactPresentationGroup)

    var id: String {
        switch self {
        case .message(let message): "message:\(message.id)"
        case .artifactGroup(let group): "artifact:\(group.id)"
        }
    }
}

enum ChatTimeline {
    /// Places each artifact group after the newest message it references. Groups
    /// without a source message stay in the library and are not appended to chat.
    static func entries(
        messages: [MessageRecord],
        artifactGroups: [ArtifactPresentationGroup]
    ) -> [ChatTimelineEntry] {
        var groupsBySourceMessageID: [String: [ArtifactPresentationGroup]] = [:]

        for group in artifactGroups {
            let sourceMessageIDs = Set(group.records.flatMap { $0.sourceMessageIDs ?? [] })
            guard let latestSourceMessage = messages.last(where: { sourceMessageIDs.contains($0.id) }) else {
                continue
            }
            groupsBySourceMessageID[latestSourceMessage.id, default: []].append(group)
        }

        var result: [ChatTimelineEntry] = []
        for message in messages {
            result.append(.message(message))
            for group in groupsBySourceMessageID[message.id] ?? [] {
                result.append(.artifactGroup(group))
            }
        }
        return result
    }
}
