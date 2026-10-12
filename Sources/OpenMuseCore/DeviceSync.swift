import CryptoKit
import Foundation

public struct SyncEnvelope: Codable, Equatable, Sendable, Identifiable {
    public var id: String { eventID }
    public let schemaVersion: Int
    public let eventID: String
    public let workspaceID: String
    public let deviceID: String
    public let deviceSequence: Int64
    public let objectID: String
    public let kind: String
    public let baseRevision: Int
    public let revision: Int
    public let parentRevisionIDs: [String]
    public let appendsRevision: Bool
    public let payloadHash: String
    public let payload: Data
    public let isRedacted: Bool
    public let createdAt: Date

    public init(
        schemaVersion: Int = 1,
        eventID: String = UUID().uuidString,
        workspaceID: String,
        deviceID: String,
        deviceSequence: Int64,
        objectID: String,
        kind: String,
        baseRevision: Int,
        revision: Int,
        parentRevisionIDs: [String] = [],
        appendsRevision: Bool,
        payload: Data,
        isRedacted: Bool = false,
        createdAt: Date = .now
    ) {
        self.schemaVersion = schemaVersion
        self.eventID = eventID
        self.workspaceID = workspaceID
        self.deviceID = deviceID
        self.deviceSequence = deviceSequence
        self.objectID = objectID
        self.kind = kind
        self.baseRevision = baseRevision
        self.revision = revision
        self.parentRevisionIDs = parentRevisionIDs
        self.appendsRevision = appendsRevision
        self.payload = payload
        self.payloadHash = Self.hash(payload)
        self.isRedacted = isRedacted
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, eventID, workspaceID, deviceID, deviceSequence, objectID, kind
        case baseRevision, revision, parentRevisionIDs, appendsRevision, payloadHash, payload, isRedacted, createdAt
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        eventID = try values.decode(String.self, forKey: .eventID)
        workspaceID = try values.decode(String.self, forKey: .workspaceID)
        deviceID = try values.decode(String.self, forKey: .deviceID)
        deviceSequence = try values.decode(Int64.self, forKey: .deviceSequence)
        objectID = try values.decode(String.self, forKey: .objectID)
        kind = try values.decode(String.self, forKey: .kind)
        baseRevision = try values.decode(Int.self, forKey: .baseRevision)
        revision = try values.decode(Int.self, forKey: .revision)
        parentRevisionIDs = try values.decode([String].self, forKey: .parentRevisionIDs)
        appendsRevision = try values.decode(Bool.self, forKey: .appendsRevision)
        payloadHash = try values.decode(String.self, forKey: .payloadHash)
        payload = try values.decode(Data.self, forKey: .payload)
        isRedacted = try values.decodeIfPresent(Bool.self, forKey: .isRedacted) ?? false
        createdAt = try values.decode(Date.self, forKey: .createdAt)
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(schemaVersion, forKey: .schemaVersion)
        try values.encode(eventID, forKey: .eventID)
        try values.encode(workspaceID, forKey: .workspaceID)
        try values.encode(deviceID, forKey: .deviceID)
        try values.encode(deviceSequence, forKey: .deviceSequence)
        try values.encode(objectID, forKey: .objectID)
        try values.encode(kind, forKey: .kind)
        try values.encode(baseRevision, forKey: .baseRevision)
        try values.encode(revision, forKey: .revision)
        try values.encode(parentRevisionIDs, forKey: .parentRevisionIDs)
        try values.encode(appendsRevision, forKey: .appendsRevision)
        try values.encode(payloadHash, forKey: .payloadHash)
        try values.encode(payload, forKey: .payload)
        try values.encode(isRedacted, forKey: .isRedacted)
        try values.encode(createdAt, forKey: .createdAt)
    }

    func redactedCopy() -> SyncEnvelope {
        SyncEnvelope(
            schemaVersion: 2, eventID: eventID, workspaceID: workspaceID, deviceID: deviceID, deviceSequence: deviceSequence,
            objectID: objectID, kind: kind, baseRevision: baseRevision, revision: revision,
            parentRevisionIDs: parentRevisionIDs, appendsRevision: false, payload: Data(), isRedacted: true,
            createdAt: createdAt
        )
    }

    public var isValid: Bool {
        ((schemaVersion == 1 && !isRedacted) || (schemaVersion == 2 && isRedacted)) &&
        !eventID.isEmpty && eventID.count <= 100 &&
        !workspaceID.isEmpty && workspaceID.count <= 100 &&
        !deviceID.isEmpty && deviceID.count <= 100 &&
        deviceSequence > 0 &&
        !objectID.isEmpty && objectID.count <= 200 &&
        RecordKind.syncableKinds.contains(kind) &&
        baseRevision >= 0 && revision > baseRevision &&
        parentRevisionIDs.count <= 16 && parentRevisionIDs.allSatisfy { !$0.isEmpty && $0.count <= 100 } &&
        payload.count <= 512_000 &&
        (!isRedacted || payload.isEmpty) &&
        payloadHash == Self.hash(payload)
    }

    private static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

public struct SyncCursor: Codable, Equatable, Sendable, Identifiable {
    public var id: String { deviceID }
    public let deviceID: String
    public let sequence: Int64

    public init(deviceID: String, sequence: Int64) {
        self.deviceID = deviceID
        self.sequence = sequence
    }
}

public struct DeviceSyncRequest: Codable, Sendable {
    public let workspaceID: String
    public let deviceID: String
    public let events: [SyncEnvelope]
    public let cursors: [SyncCursor]

    public init(workspaceID: String, deviceID: String, events: [SyncEnvelope], cursors: [SyncCursor]) {
        self.workspaceID = workspaceID
        self.deviceID = deviceID
        self.events = events
        self.cursors = cursors
    }

    public var isWithinLimits: Bool {
        !workspaceID.isEmpty && workspaceID.count <= 100 &&
        !deviceID.isEmpty && deviceID.count <= 100 &&
        events.count <= 25 && cursors.count <= 32 &&
        events.allSatisfy { $0.isValid && $0.workspaceID == workspaceID && $0.deviceID == deviceID } &&
        cursors.allSatisfy { !$0.deviceID.isEmpty && $0.deviceID.count <= 100 && $0.sequence >= 0 } &&
        events.reduce(0) { $0 + $1.payload.count } <= 700_000 &&
        ((try? JSONEncoder().encode(self).count) ?? Int.max) <= 1_000_000
    }
}

public struct DeviceSyncResponse: Codable, Sendable {
    public let acceptedEventIDs: [String]
    public let events: [SyncEnvelope]
    public let conflictCount: Int
    public let hasMore: Bool

    public init(acceptedEventIDs: [String], events: [SyncEnvelope], conflictCount: Int, hasMore: Bool) {
        self.acceptedEventIDs = acceptedEventIDs
        self.events = events
        self.conflictCount = conflictCount
        self.hasMore = hasMore
    }

    public var isWithinLimits: Bool {
        acceptedEventIDs.count <= 25 && Set(acceptedEventIDs).count == acceptedEventIDs.count &&
        events.count <= 25 && events.allSatisfy(\.isValid) && conflictCount >= 0 &&
        ((try? JSONEncoder().encode(self).count) ?? Int.max) <= 1_000_000
    }
}

public struct SyncEventPage: Sendable {
    public let events: [SyncEnvelope]
    public let hasMore: Bool

    public init(events: [SyncEnvelope], hasMore: Bool) {
        self.events = events
        self.hasMore = hasMore
    }
}

enum SyncApplyError: Error, LocalizedError {
    case invalidEnvelope
    case wrongWorkspace
    case conflictingEventID
    case sequenceGap(deviceID: String, expected: Int64)

    var errorDescription: String? {
        switch self {
        case .invalidEnvelope: "同步事件内容或校验值无效。"
        case .wrongWorkspace: "同步事件来自另一个工作区。"
        case .conflictingEventID: "同一个同步事件 ID 对应了不同内容。"
        case .sequenceGap(let deviceID, let expected): "设备 \(deviceID) 的同步记录缺少序号 \(expected)。"
        }
    }
}

public struct SyncApplyResult: Sendable {
    public let acceptedEventIDs: [String]
    public let conflictCount: Int

    public init(acceptedEventIDs: [String], conflictCount: Int) {
        self.acceptedEventIDs = acceptedEventIDs
        self.conflictCount = conflictCount
    }
}

public struct SyncConflictRecord: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let eventID: String
    public let workspaceID: String
    public let objectID: String
    public let kind: String
    public let localRevision: Int
    public let remoteRevision: Int
    public let localPayload: Data
    public let remotePayload: Data
    public let createdAt: Date

    public init(id: String, eventID: String, workspaceID: String, objectID: String, kind: String, localRevision: Int, remoteRevision: Int, localPayload: Data, remotePayload: Data, createdAt: Date = .now) {
        self.id = id
        self.eventID = eventID
        self.workspaceID = workspaceID
        self.objectID = objectID
        self.kind = kind
        self.localRevision = localRevision
        self.remoteRevision = remoteRevision
        self.localPayload = localPayload
        self.remotePayload = remotePayload
        self.createdAt = createdAt
    }
}

extension RecordKind {
    static let syncableKinds: Set<String> = [conversation, message, attachment, goal, goalProgressEvent, artifact, document, task, activityOperation, executionTask, taskCheckpoint, memoryClaim, memoryImportBatch, source, importRecord, referenceDocument, personaRevision, ideaFeedback, feedSource, feedItem, feedFeedback, feedPreference, modelUsage, schedule, maintenanceRun, maintenanceProposal, deletionTombstone]
}
