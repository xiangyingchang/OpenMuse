import Foundation

/// Normalizes legacy root conversations into one durable main chat while retaining
/// imported conversations and all side-chat records.
enum ConversationContinuity {
    static func orderedMessages(_ messages: [MessageRecord]) -> [MessageRecord] {
        messages.sorted { lhs, rhs in
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
            return lhs.id < rhs.id
        }
    }

    static func ensurePrimary(in store: SQLiteStore, now: Date = .now) throws -> ConversationRecord {
        let stored = try store.load(ConversationRecord.self, kind: RecordKind.conversation)
        try repairLegacyActivityTitles(in: store, conversations: stored)
        let roots = stored.filter {
            $0.parentConversationID == nil && $0.importedFrom == nil && $0.importedSourceID == nil && $0.isArchived != true
        }

        let preferred = roots.filter { $0.isPrimary == true }.sorted(by: stableOrder).first
        guard var primary = preferred ?? roots.sorted(by: stableOrder).first else {
            let created = ConversationRecord(title: "主聊", isPrimary: true, isArchived: false, createdAt: now, updatedAt: now)
            try store.save(created, kind: RecordKind.conversation, id: created.id, appendRevision: true)
            return created
        }

        let legacyRoots = roots.filter { $0.id != primary.id }
        let legacyIDs = Set(legacyRoots.map(\.id))
        let previouslyMergedIDs = Set(stored.filter {
            $0.parentConversationID == nil && $0.importedFrom == nil && $0.importedSourceID == nil && $0.isArchived == true
        }.map(\.id))
        let mergedRootIDs = legacyIDs.union(previouslyMergedIDs)
        var writes: [SQLiteStoreWrite] = []

        let latestRootUpdate = roots.map(\.updatedAt).max() ?? primary.updatedAt
        let earliestRootCreation = roots.map(\.createdAt).min() ?? primary.createdAt
        if primary.title != "主聊" || primary.isPrimary != true || primary.isArchived == true ||
            primary.createdAt != earliestRootCreation || primary.updatedAt != latestRootUpdate {
            primary.title = "主聊"
            primary.isPrimary = true
            primary.isArchived = false
            primary.createdAt = earliestRootCreation
            primary.updatedAt = latestRootUpdate
            writes.append(try store.prepareWrite(primary, kind: RecordKind.conversation, id: primary.id, appendRevision: true))
        }

        for var legacy in legacyRoots {
            legacy.isPrimary = false
            legacy.isArchived = true
            writes.append(try store.prepareWrite(legacy, kind: RecordKind.conversation, id: legacy.id, appendRevision: true))
        }

        for var sideConversation in stored where mergedRootIDs.contains(sideConversation.parentConversationID ?? "") {
            sideConversation.parentConversationID = primary.id
            writes.append(try store.prepareWrite(sideConversation, kind: RecordKind.conversation, id: sideConversation.id, appendRevision: true))
        }

        for var message in try store.load(MessageRecord.self, kind: RecordKind.message) where mergedRootIDs.contains(message.conversationID) {
            message.conversationID = primary.id
            writes.append(try store.prepareWrite(message, kind: RecordKind.message, id: message.id, appendRevision: true))
        }
        for var attachment in try store.load(AttachmentRecord.self, kind: RecordKind.attachment) where mergedRootIDs.contains(attachment.conversationID) {
            attachment.conversationID = primary.id
            writes.append(try store.prepareWrite(attachment, kind: RecordKind.attachment, id: attachment.id, appendRevision: true))
        }
        for var goal in try store.load(GoalRecord.self, kind: RecordKind.goal) where mergedRootIDs.contains(goal.conversationID) {
            goal.conversationID = primary.id
            writes.append(try store.prepareWrite(goal, kind: RecordKind.goal, id: goal.id, appendRevision: true))
        }
        for var artifact in try store.load(ArtifactRecord.self, kind: RecordKind.artifact) where mergedRootIDs.contains(artifact.conversationID) {
            artifact.conversationID = primary.id
            writes.append(try store.prepareWrite(artifact, kind: RecordKind.artifact, id: artifact.id, appendRevision: true))
        }
        for var activity in try store.load(ActivityRecord.self, kind: RecordKind.task) where mergedRootIDs.contains(activity.conversationID) {
            activity.conversationID = primary.id
            writes.append(try store.prepareWrite(activity, kind: RecordKind.task, id: activity.id, appendRevision: true))
        }
        for var task in try store.load(TaskExecutionRecord.self, kind: RecordKind.executionTask) where mergedRootIDs.contains(task.conversationID) {
            task.conversationID = primary.id
            writes.append(try store.prepareWrite(task, kind: RecordKind.executionTask, id: task.id, appendRevision: true))
        }

        try store.saveAtomically(writes)
        return primary
    }

    private static func stableOrder(_ lhs: ConversationRecord, _ rhs: ConversationRecord) -> Bool {
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return lhs.id < rhs.id
    }

    private static func repairLegacyActivityTitles(in store: SQLiteStore, conversations: [ConversationRecord]) throws {
        let localConversationIDs = Set(conversations.filter {
            $0.importedFrom == nil && $0.importedSourceID == nil
        }.map(\.id))
        let messages = try store.load(MessageRecord.self, kind: RecordKind.message)
        let sourceMessages = Dictionary(uniqueKeysWithValues: messages.map { ($0.id, $0) })
        let eligibleMessages = messages.filter {
            $0.role == .user && $0.importedFrom == nil && $0.importedSourceID == nil && localConversationIDs.contains($0.conversationID)
        }
        let activities = try store.load(ActivityRecord.self, kind: RecordKind.task).sorted {
            if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
            return $0.id < $1.id
        }
        var claimedMessageIDs = Set(activities.compactMap(\.sourceMessageID))
        var writes: [SQLiteStoreWrite] = []

        for var activity in activities {
            let existingSource = activity.sourceMessageID.flatMap { sourceMessages[$0] }.flatMap {
                $0.conversationID == activity.conversationID && $0.role == .user ? $0 : nil
            }
            let matchedMessage = existingSource ?? eligibleMessages
                .filter { $0.conversationID == activity.conversationID && !claimedMessageIDs.contains($0.id) }
                .filter {
                    let age = activity.createdAt.timeIntervalSince($0.createdAt)
                    return age >= -2 && age <= 60
                }
                .max {
                    if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
                    return $0.id < $1.id
                }

            guard let matchedMessage else { continue }
            let originalActivity = activity
            activity.sourceMessageID = matchedMessage.id
            claimedMessageIDs.insert(matchedMessage.id)
            if activity.title == "继续聊一聊" {
                activity.title = ActivityTitle.make(from: matchedMessage.content.isEmpty ? "处理分享的内容" : matchedMessage.content)
            }
            guard activity != originalActivity else { continue }
            writes.append(try store.prepareWrite(activity, kind: RecordKind.task, id: activity.id, appendRevision: true))
        }

        if !writes.isEmpty { try store.saveAtomically(writes) }
    }
}

enum ActivityTitle {
    static func make(from request: String, goalTitle: String? = nil, maximumCharacters: Int = 28) -> String {
        if let goalTitle {
            let trimmed = goalTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return clipped(trimmed, maximumCharacters: maximumCharacters) }
        }

        let firstLine = request.components(separatedBy: .newlines).first ?? request
        var title = firstLine.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let boundary = title.firstIndex(where: { "。！？!?；;".contains($0) }) {
            title = String(title[..<boundary])
        }
        title = title.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "，,。！？!?；;：:")))

        for prefix in ["能不能帮我", "你可以帮我", "你能帮我", "请帮我", "麻烦你", "帮我", "我想要", "我想", "请你", "请"] {
            if title.hasPrefix(prefix), title.count > prefix.count {
                title.removeFirst(prefix.count)
                title = title.trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }

        guard !title.isEmpty else { return clipped("处理分享的内容", maximumCharacters: maximumCharacters) }
        return clipped(title, maximumCharacters: maximumCharacters)
    }

    private static func clipped(_ title: String, maximumCharacters: Int) -> String {
        guard maximumCharacters > 0 else { return "" }
        guard title.count > maximumCharacters else { return title }
        guard maximumCharacters > 1 else { return "…" }
        return String(title.prefix(maximumCharacters - 1)) + "…"
    }
}
