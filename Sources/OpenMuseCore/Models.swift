import CryptoKit
import Foundation

public enum RecordKind {
    public static let conversation = "conversation"
    public static let agentWorkspace = "agent-workspace"
    public static let message = "message"
    public static let attachment = "attachment"
    public static let goal = "goal"
    public static let goalProgressEvent = "goal-progress-event"
    public static let artifact = "artifact"
    public static let document = "document"
    public static let task = "task"
    public static let activityOperation = "activity-operation"
    public static let executionTask = "execution-task"
    public static let taskCheckpoint = "task-checkpoint"
    public static let memoryClaim = "memory-claim"
    public static let memoryImportBatch = "memory-import-batch"
    public static let source = "source"
    public static let importRecord = "import-record"
    public static let referenceDocument = "reference-document"
    public static let personaRevision = "persona-revision"
    public static let ideaFeedback = "idea-feedback"
    public static let feedSource = "feed-source"
    public static let feedItem = "feed-item"
    public static let feedFeedback = "feed-feedback"
    public static let feedPreference = "feed-preference"
    public static let modelUsage = "model-usage"
    public static let schedule = "schedule"
    public static let maintenanceRun = "maintenance-run"
    public static let maintenanceProposal = "maintenance-proposal"
    public static let deletionTombstone = "deletion-tombstone"
}

/// A privacy tombstone keeps only the record identity, so old migration archives cannot restore forgotten data.
public struct DeletionTombstoneRecord: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let recordKind: String
    public let recordID: String
    public let deletedAt: Date

    public init(recordKind: String, recordID: String, deletedAt: Date = .now) {
        self.recordKind = recordKind
        self.recordID = recordID
        self.deletedAt = deletedAt
        self.id = Self.stableID(kind: recordKind, id: recordID)
    }

    public static func stableID(kind: String, id: String) -> String {
        let value = Data("\(kind)\u{0}\(id)".utf8)
        return SHA256.hash(data: value).map { String(format: "%02x", $0) }.joined()
    }
}

public struct ModelUsageRecord: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var provider: String
    public var model: String
    public var inputTokens: Int?
    public var outputTokens: Int?
    public var totalTokens: Int?
    public var createdAt: Date

    public init(id: String = UUID().uuidString, provider: String, model: String, inputTokens: Int?, outputTokens: Int?, totalTokens: Int?, createdAt: Date = .now) {
        self.id = id
        self.provider = provider
        self.model = model
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.totalTokens = totalTokens
        self.createdAt = createdAt
    }
}

public struct FeedSourceRecord: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var url: String
    public var title: String
    public var isEnabled: Bool
    public var lastFetchedAt: Date?
    public var lastError: String?
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: String = UUID().uuidString, url: String, title: String, isEnabled: Bool = true, lastFetchedAt: Date? = nil, lastError: String? = nil, createdAt: Date = .now, updatedAt: Date = .now) {
        self.id = id
        self.url = url
        self.title = title
        self.isEnabled = isEnabled
        self.lastFetchedAt = lastFetchedAt
        self.lastError = lastError
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct FeedItemRecord: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var sourceID: String
    public var sourceTitle: String
    public var title: String
    public var summary: String
    public var url: String
    public var imageURL: String?
    public var publishedAt: Date?
    public var fetchedAt: Date

    public init(id: String, sourceID: String, sourceTitle: String, title: String, summary: String, url: String, imageURL: String? = nil, publishedAt: Date? = nil, fetchedAt: Date = .now) {
        self.id = id
        self.sourceID = sourceID
        self.sourceTitle = sourceTitle
        self.title = title
        self.summary = summary
        self.url = url
        self.imageURL = imageURL
        self.publishedAt = publishedAt
        self.fetchedAt = fetchedAt
    }
}

public struct FeedFeedbackRecord: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var itemID: String
    public var action: String
    public var keywords: [String]?
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: String? = nil, itemID: String, action: String, keywords: [String]? = nil, createdAt: Date = .now, updatedAt: Date = .now) {
        self.id = id ?? "feed-\(itemID)"
        self.itemID = itemID
        self.action = action
        self.keywords = keywords
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct FeedPreferenceRecord: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var instruction: String
    public var updatedAt: Date

    public init(id: String = "default", instruction: String, updatedAt: Date = .now) {
        self.id = id
        self.instruction = instruction
        self.updatedAt = updatedAt
    }
}

public struct MemoryClaimRecord: Codable, Identifiable, Equatable {
    public var id: String
    public var value: String
    public var category: String
    public var scope: String
    public var confidence: Double
    public var sourceType: String
    public var sourceID: String
    public var sourceRecordID: String?
    public var sourceText: String
    public var importBatchID: String?
    public var isInferred: Bool?
    public var isSensitive: Bool?
    public var supersededByClaimID: String?
    /// Optional effective-time bounds. Nil means that no boundary is known.
    public var validFrom: Date?
    public var validUntil: Date?
    public var status: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: String = UUID().uuidString, value: String, category: String = "preference", scope: String = "user", confidence: Double = 1, sourceType: String = "explicit-user-message", sourceID: String, sourceRecordID: String? = nil, sourceText: String, importBatchID: String? = nil, isInferred: Bool? = false, isSensitive: Bool? = false, supersededByClaimID: String? = nil, validFrom: Date? = nil, validUntil: Date? = nil, status: String = "active", createdAt: Date = .now, updatedAt: Date = .now) {
        self.id = id
        self.value = value
        self.category = category
        self.scope = scope
        self.confidence = confidence
        self.sourceType = sourceType
        self.sourceID = sourceID
        self.sourceRecordID = sourceRecordID
        self.sourceText = sourceText
        self.importBatchID = importBatchID
        self.isInferred = isInferred
        self.isSensitive = isSensitive
        self.supersededByClaimID = supersededByClaimID
        self.validFrom = validFrom
        self.validUntil = validUntil
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// Normalized, content-free provenance metadata. Credentials and source text never belong here.
public struct SourceRecord: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var sourceType: String
    public var provider: String
    public var displayName: String
    public var externalID: String?
    public var locator: String?
    public var contentDigest: String?
    public var trust: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: String, sourceType: String, provider: String, displayName: String, externalID: String? = nil, locator: String? = nil, contentDigest: String? = nil, trust: String = "untrusted-import", createdAt: Date = .now, updatedAt: Date = .now) {
        self.id = id
        self.sourceType = sourceType
        self.provider = provider
        self.displayName = displayName
        self.externalID = externalID
        self.locator = locator
        self.contentDigest = contentDigest
        self.trust = trust
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public static func stableID(type: String, externalID: String) -> String {
        let bytes = Data("\(type)\u{0}\(externalID)".utf8)
        let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        return "source-\(digest)"
    }

    public static func digest(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    public var isValid: Bool {
        !id.isEmpty && id.count <= 200 && !sourceType.isEmpty && sourceType.count <= 80 &&
        provider.count <= 120 && !displayName.isEmpty && displayName.count <= 200 &&
        (externalID?.count ?? 0) <= 500 && (locator?.count ?? 0) <= 2_000 && trust.count <= 80 &&
        (contentDigest == nil || (contentDigest?.count == 64 && contentDigest!.allSatisfy(\.isHexDigit)))
    }
}

/// One import operation or imported source item, separate from the source and imported records.
public struct ImportRecord: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var sourceRecordID: String
    public var importType: String
    public var externalItemID: String?
    public var targetKind: String
    public var targetRecordID: String
    public var contentDigest: String?
    public var itemCount: Int
    public var status: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: String = UUID().uuidString, sourceRecordID: String, importType: String, externalItemID: String? = nil, targetKind: String, targetRecordID: String, contentDigest: String? = nil, itemCount: Int = 1, status: String = "imported", createdAt: Date = .now, updatedAt: Date = .now) {
        self.id = id
        self.sourceRecordID = sourceRecordID
        self.importType = importType
        self.externalItemID = externalItemID
        self.targetKind = targetKind
        self.targetRecordID = targetRecordID
        self.contentDigest = contentDigest
        self.itemCount = itemCount
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var isValid: Bool {
        !id.isEmpty && id.count <= 200 && !sourceRecordID.isEmpty && sourceRecordID.count <= 200 &&
        !importType.isEmpty && importType.count <= 100 && (externalItemID?.count ?? 0) <= 500 &&
        !targetKind.isEmpty && targetKind.count <= 100 && !targetRecordID.isEmpty && targetRecordID.count <= 200 &&
        (contentDigest == nil || (contentDigest?.count == 64 && contentDigest!.allSatisfy(\.isHexDigit))) &&
        (0...100_000).contains(itemCount) && ["imported", "partially-undone", "undone", "failed"].contains(status)
    }
}

/// A user-selected, read-only source document with normalized provenance and digest.
public struct ReferenceDocumentRecord: Codable, Identifiable, Equatable, Sendable {
    public static let maximumContentBytes = 120_000
    public var id: String
    public var provider: String
    public var externalID: String
    public var sourceRecordID: String
    public var importRecordID: String
    public var title: String
    public var locator: String?
    public var content: String
    public var contentDigest: String
    public var sourceUpdatedAt: Date?
    public var importedAt: Date
    public var updatedAt: Date

    public init(
        id: String,
        provider: String,
        externalID: String,
        sourceRecordID: String,
        importRecordID: String,
        title: String,
        locator: String? = nil,
        content: String,
        contentDigest: String,
        sourceUpdatedAt: Date? = nil,
        importedAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.provider = provider
        self.externalID = externalID
        self.sourceRecordID = sourceRecordID
        self.importRecordID = importRecordID
        self.title = title
        self.locator = locator
        self.content = content
        self.contentDigest = contentDigest
        self.sourceUpdatedAt = sourceUpdatedAt
        self.importedAt = importedAt
        self.updatedAt = updatedAt
    }

    public static func stableID(provider: String, externalID: String) -> String {
        "reference-" + String(SourceRecord.stableID(type: "reference-\(provider)", externalID: externalID).dropFirst("source-".count))
    }

    public var isValid: Bool {
        ["notion", "obsidian", "qq-mail"].contains(provider) &&
        !id.isEmpty && id.count <= 200 && id == Self.stableID(provider: provider, externalID: externalID) &&
        !externalID.isEmpty && externalID.count <= 500 && !sourceRecordID.isEmpty && sourceRecordID.count <= 200 &&
        !importRecordID.isEmpty && importRecordID.count <= 200 && !title.isEmpty && title.count <= 300 &&
        (locator?.count ?? 0) <= 2_000 && content.utf8.count <= Self.maximumContentBytes &&
        contentDigest == SourceRecord.digest(content)
    }
}

public struct MemoryImportBatchRecord: Codable, Identifiable, Equatable {
    public var id: String
    public var sourceAI: String?
    public var promptVersion: String
    public var rawText: String
    public var status: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: String = UUID().uuidString, sourceAI: String? = nil, promptVersion: String = "memory-transfer.v1", rawText: String, status: String = "imported", createdAt: Date = .now, updatedAt: Date = .now) {
        self.id = id
        self.sourceAI = sourceAI
        self.promptVersion = promptVersion
        self.rawText = rawText
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct PersonaRevisionRecord: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var sourceMessageID: String
    public var sourceText: String
    public var habit: String
    public var reason: String
    public var documentRevision: Int
    public var status: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String? = nil,
        sourceMessageID: String,
        sourceText: String,
        habit: String,
        reason: String,
        documentRevision: Int,
        status: String = "applied",
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id ?? Self.stableID(sourceMessageID: sourceMessageID)
        self.sourceMessageID = sourceMessageID
        self.sourceText = sourceText
        self.habit = habit
        self.reason = reason
        self.documentRevision = documentRevision
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public static func stableID(sourceMessageID: String) -> String {
        let digest = SHA256.hash(data: Data("persona-revision\u{0}\(sourceMessageID)".utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    public var isValid: Bool {
        id == Self.stableID(sourceMessageID: sourceMessageID) &&
        !sourceMessageID.isEmpty && sourceMessageID.count <= 200 &&
        !sourceText.isEmpty && sourceText.utf8.count <= 8_000 &&
        !habit.isEmpty && habit.count <= 240 &&
        !reason.isEmpty && reason.count <= 240 &&
        documentRevision > 0 && ["applied", "undone"].contains(status)
    }
}

public struct MemoryImportCandidate: Codable, Identifiable, Equatable {
    public var id: String
    public var category: String
    public var value: String
    public var sourceText: String?
    public var isInferred: Bool
    public var isSensitive: Bool
    public var isSelected: Bool

    public init(id: String = UUID().uuidString, category: String, value: String, sourceText: String? = nil, isInferred: Bool, isSensitive: Bool, isSelected: Bool) {
        self.id = id
        self.category = category
        self.value = value
        self.sourceText = sourceText ?? value
        self.isInferred = isInferred
        self.isSensitive = isSensitive
        self.isSelected = isSelected
    }
}

public struct IdeaFeedbackRecord: Codable, Identifiable, Equatable {
    public var id: String
    public var goalID: String
    public var action: String
    public var note: String?
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: String? = nil, goalID: String, action: String, note: String? = nil, createdAt: Date = .now, updatedAt: Date = .now) {
        self.id = id ?? "idea-\(goalID)"
        self.goalID = goalID
        self.action = action
        self.note = note
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public enum MessageRole: String, Codable, Sendable {
    case user
    case assistant
}

public struct ConversationRecord: Codable, Identifiable, Equatable {
    public var id: String
    public var title: String
    public var parentConversationID: String?
    public var importedFrom: String?
    public var importedSourceID: String?
    /// Marks the one continuous, user-facing main conversation. Optional so older workspace
    /// records can be upgraded without a destructive schema migration.
    public var isPrimary: Bool?
    /// Keeps legacy primary sessions out of navigation after their messages are merged.
    public var isArchived: Bool?
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: String = UUID().uuidString, title: String = "新对话", parentConversationID: String? = nil, importedFrom: String? = nil, importedSourceID: String? = nil, isPrimary: Bool? = nil, isArchived: Bool? = nil, createdAt: Date = .now, updatedAt: Date = .now) {
        self.id = id
        self.title = title
        self.parentConversationID = parentConversationID
        self.importedFrom = importedFrom
        self.importedSourceID = importedSourceID
        self.isPrimary = isPrimary
        self.isArchived = isArchived
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct MessageRecord: Codable, Identifiable, Equatable {
    public var id: String
    public var conversationID: String
    public var role: MessageRole
    public var content: String
    public var createdAt: Date
    public var status: String
    public var importedFrom: String?
    public var importedSourceID: String?
    public var attachmentIDs: [String]?

    public init(id: String = UUID().uuidString, conversationID: String, role: MessageRole, content: String, createdAt: Date = .now, status: String = "complete", importedFrom: String? = nil, importedSourceID: String? = nil, attachmentIDs: [String]? = nil) {
        self.id = id
        self.conversationID = conversationID
        self.role = role
        self.content = content
        self.createdAt = createdAt
        self.status = status
        self.importedFrom = importedFrom
        self.importedSourceID = importedSourceID
        self.attachmentIDs = attachmentIDs
    }
}

public struct GoalStep: Codable, Identifiable, Equatable {
    public var id: String
    public var title: String
    public var isComplete: Bool

    public init(id: String = UUID().uuidString, title: String, isComplete: Bool = false) {
        self.id = id
        self.title = title
        self.isComplete = isComplete
    }
}

public struct GoalRecord: Codable, Identifiable, Equatable {
    public var id: String
    public var conversationID: String
    public var title: String
    public var summary: String
    public var goalKind: String?
    public var sourceMessageID: String?
    public var sourceText: String?
    public var confidence: Double?
    public var status: String
    public var steps: [GoalStep]
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: String = UUID().uuidString, conversationID: String, title: String, summary: String, goalKind: String? = nil, sourceMessageID: String? = nil, sourceText: String? = nil, confidence: Double? = nil, status: String = "进行中", steps: [GoalStep], createdAt: Date = .now, updatedAt: Date = .now) {
        self.id = id
        self.conversationID = conversationID
        self.title = title
        self.summary = summary
        self.goalKind = goalKind
        self.sourceMessageID = sourceMessageID
        self.sourceText = sourceText
        self.confidence = confidence
        self.status = status
        self.steps = steps
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// An immutable, deduplicated record of a progress statement the user explicitly made in chat.
public struct GoalProgressEventRecord: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var goalID: String
    public var sourceMessageID: String
    public var action: String
    public var stepID: String?
    public var createdAt: Date

    public init(goalID: String, sourceMessageID: String, action: String, stepID: String? = nil, createdAt: Date = .now) {
        self.goalID = goalID
        self.sourceMessageID = sourceMessageID
        self.action = action
        self.stepID = stepID
        self.createdAt = createdAt
        self.id = Self.stableID(goalID: goalID, sourceMessageID: sourceMessageID, action: action, stepID: stepID)
    }

    public static func stableID(goalID: String, sourceMessageID: String, action: String, stepID: String?) -> String {
        DeletionTombstoneRecord.stableID(
            kind: RecordKind.goalProgressEvent,
            id: "\(goalID)\u{0}\(sourceMessageID)\u{0}\(action)\u{0}\(stepID ?? "")"
        )
    }

    public var isValid: Bool {
        !goalID.isEmpty && goalID.count <= 200 && !sourceMessageID.isEmpty && sourceMessageID.count <= 200 &&
        ((action == "step-completed" && stepID.map { !$0.isEmpty && $0.count <= 200 } == true) ||
         (action == "goal-completed" && stepID == nil)) &&
        id == Self.stableID(goalID: goalID, sourceMessageID: sourceMessageID, action: action, stepID: stepID)
    }
}

public struct ScheduleRecord: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var goalID: String
    public var title: String
    public var dueAt: Date
    public var timeZoneID: String
    public var ownerDeviceID: String
    public var missedRunPolicy: String
    public var status: String
    public var notificationStatus: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: String = UUID().uuidString, goalID: String, title: String, dueAt: Date, timeZoneID: String = TimeZone.current.identifier, ownerDeviceID: String, missedRunPolicy: String = "show-on-next-open", status: String = "scheduled", notificationStatus: String = "pending", createdAt: Date = .now, updatedAt: Date = .now) {
        self.id = id
        self.goalID = goalID
        self.title = title
        self.dueAt = dueAt
        self.timeZoneID = timeZoneID
        self.ownerDeviceID = ownerDeviceID
        self.missedRunPolicy = missedRunPolicy
        self.status = status
        self.notificationStatus = notificationStatus
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// A private, auditable record of one bounded reflection run. It stores source IDs and a digest,
/// never the full prompt sent to the model.
public struct MaintenanceRunRecord: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var kind: String
    public var status: String
    public var sourceMessageIDs: [String]
    public var inputDigest: String
    public var summary: String
    /// A human-readable reflection, kept separate from factual memory and never injected into prompts.
    public var reflection: String?
    public var reflectionEvidence: [MaintenanceEvidence]?
    public var provider: String
    public var model: String
    public var inputTokens: Int?
    public var outputTokens: Int?
    public var failureMessage: String?
    public var attemptCount: Int
    /// Conservative token reservation for a request whose provider usage is not available.
    public var budgetReservedTokens: Int?
    public var startedAt: Date
    public var finishedAt: Date?

    public init(
        id: String,
        kind: String = "dreaming",
        status: String = "running",
        sourceMessageIDs: [String],
        inputDigest: String,
        summary: String = "",
        reflection: String? = nil,
        reflectionEvidence: [MaintenanceEvidence]? = nil,
        provider: String,
        model: String,
        inputTokens: Int? = nil,
        outputTokens: Int? = nil,
        failureMessage: String? = nil,
        attemptCount: Int = 1,
        budgetReservedTokens: Int? = nil,
        startedAt: Date = .now,
        finishedAt: Date? = nil
    ) {
        self.id = id
        self.kind = kind
        self.status = status
        self.sourceMessageIDs = sourceMessageIDs
        self.inputDigest = inputDigest
        self.summary = summary
        self.reflection = reflection
        self.reflectionEvidence = reflectionEvidence
        self.provider = provider
        self.model = model
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.failureMessage = failureMessage
        self.attemptCount = attemptCount
        self.budgetReservedTokens = budgetReservedTokens
        self.startedAt = startedAt
        self.finishedAt = finishedAt
    }

    public var isValid: Bool {
        !id.isEmpty && id.count <= 200 && kind == "dreaming" &&
        ["running", "completed", "failed"].contains(status) &&
        sourceMessageIDs.count <= 24 && Set(sourceMessageIDs).count == sourceMessageIDs.count && sourceMessageIDs.allSatisfy { !$0.isEmpty && $0.count <= 200 } &&
        inputDigest.count == 64 && summary.utf8.count <= 4_000 && provider.count <= 100 && model.count <= 200 &&
        (reflection?.utf8.count ?? 0) <= 1_200 &&
        ((reflection?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            ? (reflectionEvidence?.isEmpty ?? true)
            : (reflectionEvidence.map {
                !$0.isEmpty && $0.count <= 8 &&
                Set($0.map(\.sourceMessageID)).count == $0.count &&
                Set($0.map(\.sourceMessageID)).isSubset(of: Set(sourceMessageIDs)) &&
                $0.allSatisfy(\.isValid)
            } ?? false)) &&
        (failureMessage?.utf8.count ?? 0) <= 1_000 && (1...2).contains(attemptCount) &&
        (budgetReservedTokens == nil || (0...1_000_000).contains(budgetReservedTokens!))
    }
}

public struct MaintenanceEvidence: Codable, Equatable, Hashable, Sendable {
    public var sourceMessageID: String
    public var quote: String
    public var sourceContentDigest: String?

    public init(sourceMessageID: String, quote: String, sourceContentDigest: String? = nil) {
        self.sourceMessageID = sourceMessageID
        self.quote = quote
        self.sourceContentDigest = sourceContentDigest
    }

    public var isValid: Bool {
        !sourceMessageID.isEmpty && sourceMessageID.count <= 200 &&
        !quote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && quote == quote.trimmingCharacters(in: .whitespacesAndNewlines) &&
        quote.count <= 120 &&
        sourceContentDigest.map { $0.count == 64 && $0.allSatisfy(\.isHexDigit) } ?? true
    }
}

/// Model-generated reflection is always a proposal. A user decision is required before it changes memory or SOUL.md.
public struct MaintenanceProposalRecord: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var runID: String
    public var kind: String
    public var title: String
    public var content: String
    public var rationale: String
    public var sourceMessageIDs: [String]
    public var evidence: [MaintenanceEvidence]?
    public var targetGoalID: String?
    public var supersedesMemoryClaimID: String?
    public var supersedesMemoryClaimUpdatedAt: Date?
    public var confidence: Double
    public var status: String
    public var acceptedRecordID: String?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String,
        runID: String,
        kind: String,
        title: String,
        content: String,
        rationale: String,
        sourceMessageIDs: [String],
        evidence: [MaintenanceEvidence]? = nil,
        targetGoalID: String? = nil,
        supersedesMemoryClaimID: String? = nil,
        supersedesMemoryClaimUpdatedAt: Date? = nil,
        confidence: Double,
        status: String = "pending",
        acceptedRecordID: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.runID = runID
        self.kind = kind
        self.title = title
        self.content = content
        self.rationale = rationale
        self.sourceMessageIDs = sourceMessageIDs
        self.evidence = evidence
        self.targetGoalID = targetGoalID
        self.supersedesMemoryClaimID = supersedesMemoryClaimID
        self.supersedesMemoryClaimUpdatedAt = supersedesMemoryClaimUpdatedAt
        self.confidence = confidence
        self.status = status
        self.acceptedRecordID = acceptedRecordID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var isValid: Bool {
        !id.isEmpty && id.count <= 200 && !runID.isEmpty && runID.count <= 200 &&
        ["fact", "understanding", "collaboration-habit", "goal-step", "memory-update"].contains(kind) &&
        (kind == "goal-step" ? targetGoalID.map { !$0.isEmpty && $0.count <= 200 } == true : targetGoalID == nil) &&
        (kind == "memory-update"
            ? supersedesMemoryClaimID.map { !$0.isEmpty && $0.count <= 200 } == true && supersedesMemoryClaimUpdatedAt != nil
            : supersedesMemoryClaimID == nil && supersedesMemoryClaimUpdatedAt == nil) &&
        !title.isEmpty && title.count <= 160 && !content.isEmpty && content.count <= 600 &&
        !rationale.isEmpty && rationale.count <= 600 &&
        !sourceMessageIDs.isEmpty && sourceMessageIDs.count <= 8 && Set(sourceMessageIDs).count == sourceMessageIDs.count && sourceMessageIDs.allSatisfy { !$0.isEmpty && $0.count <= 200 } &&
        (evidence.map { items in
            items.count == sourceMessageIDs.count && items.count <= 8 &&
            Set(items.map(\.sourceMessageID)).count == items.count &&
            Set(items.map(\.sourceMessageID)) == Set(sourceMessageIDs) && items.allSatisfy(\.isValid)
        } ?? true) &&
        confidence.isFinite && (0...1).contains(confidence) &&
        ["pending", "accepted", "rejected", "stale"].contains(status)
    }
}

public struct MaintenancePreferences: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var quietHoursStart: Int
    public var quietHoursEnd: Int
    public var maximumRequestsPerDay: Int
    public var maximumTokensPerDay: Int
    public var maximumOutputTokensPerRun: Int
    public var timeZoneIdentifier: String
    public var preferredDevice: String
    public var missedRunPolicy: String

    public init(
        enabled: Bool = false,
        quietHoursStart: Int = 22,
        quietHoursEnd: Int = 8,
        maximumRequestsPerDay: Int = 20,
        maximumTokensPerDay: Int = 20_000,
        maximumOutputTokensPerRun: Int = 900,
        timeZoneIdentifier: String = TimeZone.current.identifier,
        preferredDevice: String = "current-device",
        missedRunPolicy: String = "show-on-next-open"
    ) {
        self.enabled = enabled
        self.quietHoursStart = min(max(quietHoursStart, 0), 23)
        self.quietHoursEnd = min(max(quietHoursEnd, 0), 23)
        self.maximumRequestsPerDay = min(max(maximumRequestsPerDay, 1), 100)
        self.maximumTokensPerDay = min(max(maximumTokensPerDay, 512), 1_000_000)
        self.maximumOutputTokensPerRun = min(max(maximumOutputTokensPerRun, 128), 4_096)
        self.timeZoneIdentifier = TimeZone(identifier: timeZoneIdentifier)?.identifier ?? TimeZone.current.identifier
        self.preferredDevice = preferredDevice == "current-device" ? preferredDevice : "current-device"
        self.missedRunPolicy = ["show-on-next-open", "skip"].contains(missedRunPolicy) ? missedRunPolicy : "show-on-next-open"
    }

    private enum CodingKeys: String, CodingKey {
        case enabled, quietHoursStart, quietHoursEnd, maximumRequestsPerDay, maximumTokensPerDay
        case maximumOutputTokensPerRun, timeZoneIdentifier, preferredDevice, missedRunPolicy
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            enabled: try values.decodeIfPresent(Bool.self, forKey: .enabled) ?? false,
            quietHoursStart: try values.decodeIfPresent(Int.self, forKey: .quietHoursStart) ?? 22,
            quietHoursEnd: try values.decodeIfPresent(Int.self, forKey: .quietHoursEnd) ?? 8,
            maximumRequestsPerDay: try values.decodeIfPresent(Int.self, forKey: .maximumRequestsPerDay) ?? 20,
            maximumTokensPerDay: try values.decodeIfPresent(Int.self, forKey: .maximumTokensPerDay) ?? 20_000,
            maximumOutputTokensPerRun: try values.decodeIfPresent(Int.self, forKey: .maximumOutputTokensPerRun) ?? 900,
            timeZoneIdentifier: try values.decodeIfPresent(String.self, forKey: .timeZoneIdentifier) ?? TimeZone.current.identifier,
            preferredDevice: try values.decodeIfPresent(String.self, forKey: .preferredDevice) ?? "current-device",
            missedRunPolicy: try values.decodeIfPresent(String.self, forKey: .missedRunPolicy) ?? "show-on-next-open"
        )
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(enabled, forKey: .enabled)
        try values.encode(quietHoursStart, forKey: .quietHoursStart)
        try values.encode(quietHoursEnd, forKey: .quietHoursEnd)
        try values.encode(maximumRequestsPerDay, forKey: .maximumRequestsPerDay)
        try values.encode(maximumTokensPerDay, forKey: .maximumTokensPerDay)
        try values.encode(maximumOutputTokensPerRun, forKey: .maximumOutputTokensPerRun)
        try values.encode(timeZoneIdentifier, forKey: .timeZoneIdentifier)
        try values.encode(preferredDevice, forKey: .preferredDevice)
        try values.encode(missedRunPolicy, forKey: .missedRunPolicy)
    }

    public var schedulingCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        return calendar
    }

    public func allowsRun(at date: Date, calendar: Calendar? = nil) -> Bool {
        let calendar = calendar ?? schedulingCalendar
        guard enabled else { return false }
        let hour = calendar.component(.hour, from: date)
        if quietHoursStart == quietHoursEnd { return true }
        if quietHoursStart < quietHoursEnd {
            return !(quietHoursStart..<quietHoursEnd).contains(hour)
        }
        return !(hour >= quietHoursStart || hour < quietHoursEnd)
    }

    /// The time iOS may first attempt a best-effort background refresh; the OS can run it later or not at all.
    public func nextBackgroundOpportunity(after date: Date, calendar: Calendar? = nil) -> Date? {
        let calendar = calendar ?? schedulingCalendar
        guard enabled else { return nil }
        var components = DateComponents()
        components.hour = quietHoursEnd
        components.minute = 0
        components.second = 0
        guard let next = calendar.nextDate(after: date, matching: components, matchingPolicy: .nextTime) else { return nil }
        return next
    }

    public func permitsMissedRun(at date: Date) -> Bool {
        guard missedRunPolicy == "skip" else { return true }
        let calendar = schedulingCalendar
        let start = calendar.startOfDay(for: date)
        guard let due = calendar.date(bySettingHour: quietHoursEnd, minute: 0, second: 0, of: start) else { return false }
        return date >= due && date < due.addingTimeInterval(60 * 60)
    }
}

public struct ArtifactRecord: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var kind: String
    public var conversationID: String
    public var goalID: String?
    public var currentRevision: Int
    public var content: String
    public var status: String?
    public var sourceMessageIDs: [String]?
    public var assumptions: [String]?
    public var expectedDayCount: Int?
    public var coveredDayCount: Int?
    public var travelPlanVariants: [TravelPlanVariantRecord]?
    public var selectedTravelPlanVariantID: String?
    public var assetReferences: [ArtifactAssetDescriptor]?
    public var updatedAt: Date

    public init(id: String = UUID().uuidString, title: String, kind: String = "travel-plan", conversationID: String, goalID: String?, currentRevision: Int = 1, content: String, status: String? = nil, sourceMessageIDs: [String]? = nil, assumptions: [String]? = nil, expectedDayCount: Int? = nil, coveredDayCount: Int? = nil, travelPlanVariants: [TravelPlanVariantRecord]? = nil, selectedTravelPlanVariantID: String? = nil, assetReferences: [ArtifactAssetDescriptor]? = nil, updatedAt: Date = .now) {
        self.id = id
        self.title = title
        self.kind = kind
        self.conversationID = conversationID
        self.goalID = goalID
        self.currentRevision = currentRevision
        self.content = content
        self.status = status
        self.sourceMessageIDs = sourceMessageIDs
        self.assumptions = assumptions
        self.expectedDayCount = expectedDayCount
        self.coveredDayCount = coveredDayCount
        self.travelPlanVariants = travelPlanVariants
        self.selectedTravelPlanVariantID = selectedTravelPlanVariantID
        self.assetReferences = assetReferences
        self.updatedAt = updatedAt
    }
}

public struct TravelPlanVariantRecord: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var content: String
    public var sourceMessageIDs: [String]?
    public var assumptions: [String]?
    public var expectedDayCount: Int?
    public var coveredDayCount: Int?
    public var updatedAt: Date

    public init(id: String = UUID().uuidString, title: String, content: String, sourceMessageIDs: [String]? = nil, assumptions: [String]? = nil, expectedDayCount: Int? = nil, coveredDayCount: Int? = nil, updatedAt: Date = .now) {
        self.id = id
        self.title = title
        self.content = content
        self.sourceMessageIDs = sourceMessageIDs
        self.assumptions = assumptions
        self.expectedDayCount = expectedDayCount
        self.coveredDayCount = coveredDayCount
        self.updatedAt = updatedAt
    }
}

public struct WorkspaceDocument: Codable, Identifiable, Equatable {
    public var id: String { path }
    public var path: String
    public var title: String
    public var content: String
    public var revision: Int
    public var updatedAt: Date

    public init(path: String, title: String, content: String, revision: Int = 1, updatedAt: Date = .now) {
        self.path = path
        self.title = title
        self.content = content
        self.revision = revision
        self.updatedAt = updatedAt
    }
}

public struct ActivityStepRecord: Codable, Identifiable, Equatable {
    public var id: String
    public var group: String
    public var title: String
    public var detail: String
    public var status: String
    public var updatedAt: Date

    public init(id: String = UUID().uuidString, group: String = "MAIN", title: String, detail: String, status: String = "pending", updatedAt: Date = .now) {
        self.id = id
        self.group = group
        self.title = title
        self.detail = detail
        self.status = status
        self.updatedAt = updatedAt
    }
}

/// Detailed, durable record of one model-selected tool invocation. Kept separate
/// from the activity summary so long tool outputs cannot make the task record
/// exceed the workspace sync/archive payload limit.
public struct ActivityOperationRecord: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var activityID: String
    public var stepID: String
    public var group: String
    public var toolName: String
    public var toolCallID: String?
    public var title: String
    public var status: String
    public var inputJSON: String?
    public var outputText: String?
    public var errorText: String?
    public var safeSummary: String?
    public var relativePath: String?
    public var startedAt: Date
    public var finishedAt: Date?
    public var updatedAt: Date

    public static func stableID(activityID: String, stepID: String) -> String {
        let value = Data("\(activityID)\u{0}\(stepID)".utf8)
        let digest = SHA256.hash(data: value).map { String(format: "%02x", $0) }.joined()
        return "activity-operation-\(digest)"
    }

    public init(
        id: String,
        activityID: String,
        stepID: String,
        group: String,
        toolName: String,
        toolCallID: String? = nil,
        title: String,
        status: String,
        inputJSON: String? = nil,
        outputText: String? = nil,
        errorText: String? = nil,
        safeSummary: String? = nil,
        relativePath: String? = nil,
        startedAt: Date = .now,
        finishedAt: Date? = nil,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.activityID = activityID
        self.stepID = stepID
        self.group = group
        self.toolName = toolName
        self.toolCallID = toolCallID
        self.title = title
        self.status = status
        self.inputJSON = inputJSON
        self.outputText = outputText
        self.errorText = errorText
        self.safeSummary = safeSummary
        self.relativePath = relativePath
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.updatedAt = updatedAt
    }

    public var duration: TimeInterval? {
        guard let finishedAt else { return nil }
        return max(0, finishedAt.timeIntervalSince(startedAt))
    }

    public var isValid: Bool {
        !id.isEmpty && id.utf8.count <= 200 &&
        !activityID.isEmpty && activityID.utf8.count <= 200 &&
        !stepID.isEmpty && stepID.utf8.count <= 200 &&
        ["PHONE", "MAC"].contains(group) &&
        !toolName.isEmpty && toolName.utf8.count <= 64 &&
        (toolCallID?.utf8.count ?? 0) <= 150 &&
        !title.isEmpty && title.utf8.count <= 200 &&
        ["started", "running", "awaiting-approval", "approved", "completed", "timed-out", "denied", "failed", "cancelled", "suspended"].contains(status) &&
        (inputJSON?.utf8.count ?? 0) <= ActivityToolDetailPolicy.maximumInputBytes &&
        (outputText?.utf8.count ?? 0) <= ActivityToolDetailPolicy.maximumOutputBytes &&
        (errorText?.utf8.count ?? 0) <= ActivityToolDetailPolicy.maximumErrorBytes &&
        (safeSummary?.utf8.count ?? 0) <= 1_000 &&
        (relativePath?.utf8.count ?? 0) <= 500 &&
        (finishedAt == nil || finishedAt! >= startedAt)
    }
}

public struct ActivityRecord: Codable, Identifiable, Equatable {
    public var id: String
    public var conversationID: String
    public var sourceMessageID: String?
    public var title: String
    public var stage: String
    public var status: String
    public var ownerDeviceID: String?
    public var steps: [ActivityStepRecord]?
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: String = UUID().uuidString, conversationID: String, sourceMessageID: String? = nil, title: String, stage: String, status: String = "running", ownerDeviceID: String? = nil, steps: [ActivityStepRecord]? = [], createdAt: Date = .now, updatedAt: Date = .now) {
        self.id = id
        self.conversationID = conversationID
        self.sourceMessageID = sourceMessageID
        self.title = title
        self.stage = stage
        self.status = status
        self.ownerDeviceID = ownerDeviceID
        self.steps = steps
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// Durable execution ownership. This is distinct from ActivityRecord, which is only a user-facing progress view.
public struct TaskExecutionRecord: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var goalID: String?
    public var conversationID: String
    public var constraintRevision: Int
    public var requiredCapabilities: [String]
    public var status: String
    public var runEpoch: Int
    public var ownerDeviceID: String?
    public var lastCommittedCheckpointID: String?
    public var lastCheckpointSequence: Int
    public var parentTaskID: String?
    public var branchID: String?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String = UUID().uuidString,
        goalID: String? = nil,
        conversationID: String,
        constraintRevision: Int = 0,
        requiredCapabilities: [String] = [],
        status: String = "queued",
        runEpoch: Int = 0,
        ownerDeviceID: String? = nil,
        lastCommittedCheckpointID: String? = nil,
        lastCheckpointSequence: Int = 0,
        parentTaskID: String? = nil,
        branchID: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.goalID = goalID
        self.conversationID = conversationID
        self.constraintRevision = constraintRevision
        self.requiredCapabilities = requiredCapabilities
        self.status = status
        self.runEpoch = runEpoch
        self.ownerDeviceID = ownerDeviceID
        self.lastCommittedCheckpointID = lastCommittedCheckpointID
        self.lastCheckpointSequence = lastCheckpointSequence
        self.parentTaskID = parentTaskID
        self.branchID = branchID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var isValid: Bool {
        !id.isEmpty && id.count <= 200 && !conversationID.isEmpty && conversationID.count <= 200 &&
        constraintRevision >= 0 && requiredCapabilities.count <= 64 &&
        requiredCapabilities.allSatisfy { !$0.isEmpty && $0.count <= 100 } &&
        ["queued", "running", "waiting_user", "waiting_device", "suspended", "completed", "failed", "cancelled"].contains(status) &&
        runEpoch >= 0 && lastCheckpointSequence >= 0 &&
        (ownerDeviceID.map { !$0.isEmpty && $0.count <= 100 } ?? true) &&
        ((runEpoch == 0 && ownerDeviceID == nil && status == "queued") || (runEpoch > 0 && ownerDeviceID != nil)) &&
        ((lastCheckpointSequence == 0 && lastCommittedCheckpointID == nil) || (lastCheckpointSequence > 0 && lastCommittedCheckpointID != nil)) &&
        (parentTaskID.map { !$0.isEmpty && $0.count <= 200 } ?? true) &&
        (branchID.map { !$0.isEmpty && $0.count <= 100 } ?? true)
    }
}

/// A durable, idempotent boundary after a task step. Large output belongs in an attachment store, not this record.
public struct TaskCheckpointRecord: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var taskID: String
    public var attemptID: String
    public var stepID: String
    public var idempotencyKey: String
    public var runEpoch: Int
    public var ownerDeviceID: String
    public var sequence: Int
    public var inputRevision: Int
    public var effectClass: String
    public var status: String
    public var resultSummary: String
    public var outputRefs: [String]
    public var createdAt: Date

    public init(
        id: String? = nil,
        taskID: String,
        attemptID: String,
        stepID: String,
        idempotencyKey: String,
        runEpoch: Int,
        ownerDeviceID: String,
        sequence: Int,
        inputRevision: Int,
        effectClass: String = "read-only",
        status: String = "completed",
        resultSummary: String = "",
        outputRefs: [String] = [],
        createdAt: Date = .now
    ) {
        self.id = id ?? DeletionTombstoneRecord.stableID(kind: RecordKind.taskCheckpoint, id: "\(taskID)\u{0}\(runEpoch)\u{0}\(idempotencyKey)")
        self.taskID = taskID
        self.attemptID = attemptID
        self.stepID = stepID
        self.idempotencyKey = idempotencyKey
        self.runEpoch = runEpoch
        self.ownerDeviceID = ownerDeviceID
        self.sequence = sequence
        self.inputRevision = inputRevision
        self.effectClass = effectClass
        self.status = status
        self.resultSummary = resultSummary
        self.outputRefs = outputRefs
        self.createdAt = createdAt
    }

    public var isValid: Bool {
        !id.isEmpty && id.count <= 200 && !taskID.isEmpty && taskID.count <= 200 &&
        !attemptID.isEmpty && attemptID.count <= 200 && !stepID.isEmpty && stepID.count <= 200 &&
        !idempotencyKey.isEmpty && idempotencyKey.count <= 200 && runEpoch > 0 &&
        !ownerDeviceID.isEmpty && ownerDeviceID.count <= 100 && sequence > 0 && inputRevision >= 0 &&
        ["read-only", "workspace-write", "external-side-effect"].contains(effectClass) &&
        ["completed", "waiting_user", "waiting_device", "failed", "cancelled"].contains(status) &&
        resultSummary.utf8.count <= 8_000 && outputRefs.count <= 64 &&
        outputRefs.allSatisfy { !$0.isEmpty && $0.count <= 500 } &&
        id == DeletionTombstoneRecord.stableID(kind: RecordKind.taskCheckpoint, id: "\(taskID)\u{0}\(runEpoch)\u{0}\(idempotencyKey)")
    }
}

public enum TaskExecutionError: Error, LocalizedError, Equatable {
    case missingTask
    case staleEpoch
    case wrongOwner
    case invalidTransition
    case invalidCheckpoint
    case conflictingCheckpoint

    public var errorDescription: String? {
        switch self {
        case .missingTask: "找不到这项任务。"
        case .staleEpoch: "任务运行版本已变化，旧运行不能覆盖新进度。"
        case .wrongOwner: "当前设备不是这项任务的执行设备。"
        case .invalidTransition: "任务当前状态不允许执行这项操作。"
        case .invalidCheckpoint: "任务检查点内容无效或不连续。"
        case .conflictingCheckpoint: "同一个幂等步骤返回了不同内容，已保留原检查点。"
        }
    }
}

public enum ModelProvider: String, Codable, CaseIterable, Identifiable, Sendable {
    case openAI = "OpenAI"
    case deepSeek = "DeepSeek"
    case custom = "OpenAI 兼容接口"

    public var id: String { rawValue }

    public var defaultEndpoint: String {
        switch self {
        case .openAI: "https://api.openai.com/v1"
        case .deepSeek: "https://api.deepseek.com/v1"
        case .custom: "https://"
        }
    }

    public var defaultModel: String {
        switch self {
        case .openAI: "gpt-4o-mini"
        case .deepSeek: "deepseek-chat"
        case .custom: "your-model-id"
        }
    }

    public var defaultSupportsToolCalling: Bool {
        switch self {
        case .openAI, .deepSeek: true
        case .custom: false
        }
    }

    public var defaultSupportsStreamingResponses: Bool {
        switch self {
        case .openAI, .deepSeek: true
        case .custom: false
        }
    }
}

public struct ModelConfiguration: Codable, Equatable, Sendable {
    public var provider: ModelProvider
    public var endpoint: String
    public var model: String
    public var contextWindow: Int
    /// Whether the selected endpoint/model accepts OpenAI-compatible function tools.
    public var supportsToolCalling: Bool
    /// Whether plain direct replies should use server-sent streaming when available.
    public var supportsStreamingResponses: Bool

    public init(
        provider: ModelProvider = .deepSeek,
        endpoint: String = ModelProvider.deepSeek.defaultEndpoint,
        model: String = ModelProvider.deepSeek.defaultModel,
        contextWindow: Int = 32_000,
        supportsToolCalling: Bool? = nil,
        supportsStreamingResponses: Bool? = nil
    ) {
        self.provider = provider
        self.endpoint = endpoint
        self.model = model
        self.contextWindow = contextWindow
        self.supportsToolCalling = supportsToolCalling ?? provider.defaultSupportsToolCalling
        self.supportsStreamingResponses = supportsStreamingResponses ?? provider.defaultSupportsStreamingResponses
    }

    private enum CodingKeys: String, CodingKey {
        case provider, endpoint, model, contextWindow, supportsToolCalling, supportsStreamingResponses
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        provider = try container.decode(ModelProvider.self, forKey: .provider)
        endpoint = try container.decode(String.self, forKey: .endpoint)
        model = try container.decode(String.self, forKey: .model)
        contextWindow = try container.decodeIfPresent(Int.self, forKey: .contextWindow) ?? 32_000
        // Preserve behavior for already-saved configurations; new custom endpoints default off.
        supportsToolCalling = try container.decodeIfPresent(Bool.self, forKey: .supportsToolCalling) ?? true
        supportsStreamingResponses = try container.decodeIfPresent(Bool.self, forKey: .supportsStreamingResponses) ?? true
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(provider, forKey: .provider)
        try container.encode(endpoint, forKey: .endpoint)
        try container.encode(model, forKey: .model)
        try container.encode(contextWindow, forKey: .contextWindow)
        try container.encode(supportsToolCalling, forKey: .supportsToolCalling)
        try container.encode(supportsStreamingResponses, forKey: .supportsStreamingResponses)
    }

    public var isReady: Bool {
        let rawEndpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: rawEndpoint),
              let scheme = components.scheme?.lowercased(),
              let host = components.host?.lowercased(),
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil,
              !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        return scheme == "https" || ((host == "localhost" || host == "127.0.0.1" || host == "::1") && scheme == "http")
    }

    public var credentialAccount: String {
        let rawEndpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedEndpoint: String
        if var components = URLComponents(string: rawEndpoint) {
            if let scheme = components.scheme { components.scheme = scheme.lowercased() }
            if let host = components.host { components.host = host.lowercased() }
            components.path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            normalizedEndpoint = components.string ?? rawEndpoint
        } else {
            normalizedEndpoint = rawEndpoint
        }
        return "model-api-key:\(provider.rawValue):\(normalizedEndpoint)"
    }
}

public struct TranscriptMessage: Codable, Sendable {
    public var role: String
    public var content: String
}

public enum WorkspaceSection: String, CaseIterable, Identifiable {
    case chat = "聊天"
    case feed = "动态"
    case ideas = "点子"
    case goals = "目标"
    case library = "资源库"

    public var id: String { rawValue }

    public var symbol: String {
        switch self {
        case .chat: "bubble.left"
        case .goals: "checkmark.square"
        case .feed: "book.closed"
        case .ideas: "lightbulb"
        case .library: "square.grid.2x2"
        }
    }
}

public enum OpenMuseSheet: Identifiable {
    case companion
    case settings
    case memories
    case activity
    case memoryImport
    case artifact(ArtifactRecord)
    case document(WorkspaceDocument)

    public var id: String {
        switch self {
        case .companion: "companion"
        case .settings: "settings"
        case .memories: "memories"
        case .activity: "activity"
        case .memoryImport: "memory-import"
        case .artifact(let item): "artifact-\(item.id)"
        case .document(let item): "document-\(item.path)"
        }
    }
}
