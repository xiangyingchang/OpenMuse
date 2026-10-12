import CryptoKit
import Foundation

public struct WorkspaceRecordSnapshot: Codable, Equatable, Sendable {
    public let kind: String
    public let recordID: String
    public let revision: Int
    public let payload: Data
    public let createdAt: Date
    public let updatedAt: Date

    public init(kind: String, recordID: String, revision: Int, payload: Data, createdAt: Date, updatedAt: Date) {
        self.kind = kind
        self.recordID = recordID
        self.revision = revision
        self.payload = payload
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct WorkspaceRevisionSnapshot: Codable, Equatable, Sendable {
    public let kind: String
    public let recordID: String
    public let revision: Int
    public let payload: Data
    public let createdAt: Date

    public init(kind: String, recordID: String, revision: Int, payload: Data, createdAt: Date) {
        self.kind = kind
        self.recordID = recordID
        self.revision = revision
        self.payload = payload
        self.createdAt = createdAt
    }
}

public struct WorkspaceAttachmentFile: Codable, Equatable, Sendable {
    public let id: String
    public let artifactID: String?
    public let mediaType: String?
    public let byteCount: Int
    public let sha256: String
    public let data: Data

    public init(id: String, data: Data, byteCount: Int, sha256: String, artifactID: String? = nil, mediaType: String? = nil) {
        self.id = id
        self.artifactID = artifactID
        self.mediaType = mediaType
        self.byteCount = byteCount
        self.sha256 = sha256
        self.data = data
    }

    public var isValid: Bool {
        let validFileIdentity: Bool
        if let artifactID {
            validFileIdentity = ArtifactAssetStore.isSafeID(artifactID) && ArtifactAssetStore.isSafeID(id) &&
                mediaType.map(ArtifactAssetStore.allowedMediaTypes.contains) == true && byteCount <= ArtifactAssetStore.maximumAssetBytes
        } else {
            validFileIdentity = mediaType == nil && AttachmentRecord.isSafeIdentifier(id) && byteCount <= AttachmentStore.maximumFileBytes
        }
        return validFileIdentity && data.count == byteCount && byteCount > 0 &&
            sha256.count == 64 && sha256.allSatisfy(\.isHexDigit) && Self.digest(data) == sha256.lowercased()
    }

    public var isArtifactAsset: Bool { artifactID != nil }

    private enum CodingKeys: String, CodingKey { case id, artifactID, mediaType, byteCount, sha256, data }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        artifactID = try values.decodeIfPresent(String.self, forKey: .artifactID)
        mediaType = try values.decodeIfPresent(String.self, forKey: .mediaType)
        byteCount = try values.decode(Int.self, forKey: .byteCount)
        sha256 = try values.decode(String.self, forKey: .sha256)
        data = try values.decode(Data.self, forKey: .data)
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encodeIfPresent(artifactID, forKey: .artifactID)
        try values.encodeIfPresent(mediaType, forKey: .mediaType)
        try values.encode(byteCount, forKey: .byteCount)
        try values.encode(sha256, forKey: .sha256)
        try values.encode(data, forKey: .data)
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

public struct WorkspaceStoreSnapshot: Codable, Equatable, Sendable {
    public let records: [WorkspaceRecordSnapshot]
    public let revisions: [WorkspaceRevisionSnapshot]
    public let conflicts: [SyncConflictRecord]

    public init(records: [WorkspaceRecordSnapshot], revisions: [WorkspaceRevisionSnapshot], conflicts: [SyncConflictRecord] = []) {
        self.records = records
        self.revisions = revisions
        self.conflicts = conflicts
    }
}

/// A portable text file from one conversation's isolated agent workspace.
/// These files are intermediate task material, not shared memory or artifacts.
public struct WorkspaceAgentFile: Codable, Equatable, Sendable {
    public let conversationID: String
    public let path: String
    public let byteCount: Int
    public let sha256: String
    public let data: Data

    public init(conversationID: String, path: String, data: Data) {
        self.conversationID = conversationID
        self.path = path
        self.byteCount = data.count
        self.sha256 = Self.digest(data)
        self.data = data
    }

    public var isValid: Bool {
        !conversationID.isEmpty && conversationID.count <= 200 &&
            OnDeviceAgentWorkspace.isSafePortablePath(path) &&
            byteCount >= 0 && byteCount <= OnDeviceAgentWorkspace.maximumFileBytes &&
            data.count == byteCount && String(data: data, encoding: .utf8) != nil &&
            sha256.count == 64 && sha256.allSatisfy(\.isHexDigit) && Self.digest(data) == sha256.lowercased()
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

public struct WorkspaceArchiveManifest: Codable, Equatable, Sendable {
    public let formatVersion: Int
    public let minimumReaderVersion: Int
    public let exportID: String
    public let createdAt: Date
    public let recordCount: Int
    public let revisionCount: Int
    public let conflictCount: Int
    public let includedKinds: [String]
    public let omittedKinds: [String]
    public let payloadSHA256: String

    public init(formatVersion: Int = 1, minimumReaderVersion: Int = 1, exportID: String, createdAt: Date, recordCount: Int, revisionCount: Int, conflictCount: Int, includedKinds: [String], omittedKinds: [String], payloadSHA256: String) {
        self.formatVersion = formatVersion
        self.minimumReaderVersion = minimumReaderVersion
        self.exportID = exportID
        self.createdAt = createdAt
        self.recordCount = recordCount
        self.revisionCount = revisionCount
        self.conflictCount = conflictCount
        self.includedKinds = includedKinds
        self.omittedKinds = omittedKinds
        self.payloadSHA256 = payloadSHA256
    }
}

public struct WorkspaceArchive: Codable, Equatable, Sendable {
    public let manifest: WorkspaceArchiveManifest
    public let payload: WorkspaceStoreSnapshot
    public let attachmentFiles: [WorkspaceAttachmentFile]
    public let agentWorkspaceFiles: [WorkspaceAgentFile]

    public init(manifest: WorkspaceArchiveManifest, payload: WorkspaceStoreSnapshot, attachmentFiles: [WorkspaceAttachmentFile] = [], agentWorkspaceFiles: [WorkspaceAgentFile] = []) {
        self.manifest = manifest
        self.payload = payload
        self.attachmentFiles = attachmentFiles
        self.agentWorkspaceFiles = agentWorkspaceFiles
    }

    private enum CodingKeys: String, CodingKey { case manifest, payload, attachmentFiles, agentWorkspaceFiles }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        manifest = try values.decode(WorkspaceArchiveManifest.self, forKey: .manifest)
        payload = try values.decode(WorkspaceStoreSnapshot.self, forKey: .payload)
        attachmentFiles = try values.decodeIfPresent([WorkspaceAttachmentFile].self, forKey: .attachmentFiles) ?? []
        agentWorkspaceFiles = try values.decodeIfPresent([WorkspaceAgentFile].self, forKey: .agentWorkspaceFiles) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(manifest, forKey: .manifest)
        try values.encode(payload, forKey: .payload)
        try values.encode(attachmentFiles, forKey: .attachmentFiles)
        if !agentWorkspaceFiles.isEmpty { try values.encode(agentWorkspaceFiles, forKey: .agentWorkspaceFiles) }
    }

    public static let maximumArchiveBytes = 50_000_000
    private static let privateKinds: Set<String> = [RecordKind.conversation, RecordKind.message, RecordKind.agentWorkspace, RecordKind.task, RecordKind.executionTask, RecordKind.taskCheckpoint, RecordKind.memoryImportBatch, RecordKind.importRecord, RecordKind.personaRevision, RecordKind.maintenanceRun, RecordKind.maintenanceProposal]

    public static func make(
        from snapshot: WorkspaceStoreSnapshot,
        includeConversations: Bool,
        attachmentFiles: [WorkspaceAttachmentFile] = [],
        agentWorkspaceFiles: [WorkspaceAgentFile] = [],
        exportID: String = UUID().uuidString,
        createdAt: Date = .now
    ) throws -> WorkspaceArchive {
        let attachmentReferences = snapshot.records.contains { record in
            record.kind == RecordKind.attachment || messageHasAttachments(record.kind, payload: record.payload)
        } || snapshot.revisions.contains { messageHasAttachments($0.kind, payload: $0.payload) } ||
            snapshot.conflicts.contains { $0.kind == RecordKind.attachment || messageHasAttachments($0.kind, payload: $0.localPayload) || messageHasAttachments($0.kind, payload: $0.remotePayload) }
        var omittedKinds = includeConversations ? [] : Array(privateKinds)
        if !includeConversations && (attachmentReferences || snapshot.records.contains(where: { $0.kind == RecordKind.attachment })) {
            omittedKinds.append(RecordKind.attachment)
        }
        let currentAttachmentIDs = includeConversations
            ? Set(snapshot.records.filter { $0.kind == RecordKind.attachment }.map(\.recordID))
            : []
        let records = try snapshot.records
            .filter { includeConversations || ($0.kind != RecordKind.attachment && !privateKinds.contains($0.kind)) }
            .map { record in
                WorkspaceRecordSnapshot(
                    kind: record.kind, recordID: record.recordID, revision: record.revision,
                    payload: try strippingAttachmentReferences(record.kind, payload: record.payload, keeping: currentAttachmentIDs),
                    createdAt: record.createdAt, updatedAt: record.updatedAt
                )
            }
        let attachmentIDs = Set(records.filter { $0.kind == RecordKind.attachment }.map(\.recordID))
        let artifactFiles = attachmentFiles.filter(\.isArtifactAsset)
        let archivedAttachmentFiles = includeConversations ? attachmentFiles.filter { !$0.isArtifactAsset } : []
        let archiveFiles = archivedAttachmentFiles + artifactFiles
        guard Set(archivedAttachmentFiles.map(\.id)) == attachmentIDs,
              archiveFiles.allSatisfy(\.isValid) else { throw WorkspaceArchiveError.missingAttachmentFiles }
        let archivedAgentFiles = includeConversations ? agentWorkspaceFiles : []
        let includedConversationIDs = Set(records.filter { $0.kind == RecordKind.conversation }.map(\.recordID))
        guard archivedAgentFiles.allSatisfy(\.isValid),
              archivedAgentFiles.allSatisfy({ includedConversationIDs.contains($0.conversationID) }),
              Set(archivedAgentFiles.map { "\($0.conversationID):\($0.path)" }).count == archivedAgentFiles.count,
              Dictionary(grouping: archivedAgentFiles, by: \.conversationID).values.allSatisfy({ files in
                  files.count <= OnDeviceAgentWorkspace.maximumListedFiles &&
                      files.reduce(0, { $0 + $1.byteCount }) <= OnDeviceAgentWorkspace.maximumWorkspaceBytes
              }) else { throw WorkspaceArchiveError.invalidAgentWorkspace }
        let recordKeys = Set(records.map { "\($0.kind):\($0.recordID)" })
        let revisions = try snapshot.revisions
            .filter { includeConversations || ($0.kind != RecordKind.attachment && !privateKinds.contains($0.kind)) }
            .filter { recordKeys.contains("\($0.kind):\($0.recordID)") }
            .map { revision in
                WorkspaceRevisionSnapshot(
                    kind: revision.kind, recordID: revision.recordID, revision: revision.revision,
                    payload: try strippingAttachmentReferences(revision.kind, payload: revision.payload, keeping: currentAttachmentIDs), createdAt: revision.createdAt
                )
            }
        let conflicts = try snapshot.conflicts
            .filter { includeConversations || ($0.kind != RecordKind.attachment && !privateKinds.contains($0.kind)) }
            .map { conflict in
                SyncConflictRecord(
                    id: conflict.id, eventID: conflict.eventID, workspaceID: conflict.workspaceID,
                    objectID: conflict.objectID, kind: conflict.kind,
                    localRevision: conflict.localRevision, remoteRevision: conflict.remoteRevision,
                    localPayload: try strippingAttachmentReferences(conflict.kind, payload: conflict.localPayload, keeping: currentAttachmentIDs),
                    remotePayload: try strippingAttachmentReferences(conflict.kind, payload: conflict.remotePayload, keeping: currentAttachmentIDs),
                    createdAt: conflict.createdAt
                )
            }
        let payload = WorkspaceStoreSnapshot(records: records, revisions: revisions, conflicts: conflicts)
        let includedKinds = Set(records.map(\.kind)).union(archivedAgentFiles.isEmpty ? [] : [RecordKind.agentWorkspace])
        let formatVersion = archivedAgentFiles.isEmpty ? 1 : 2
        let hash = try payloadHash(payload, attachmentFiles: archiveFiles, agentWorkspaceFiles: archivedAgentFiles)
        let manifest = WorkspaceArchiveManifest(
            formatVersion: formatVersion,
            minimumReaderVersion: formatVersion,
            exportID: exportID,
            createdAt: createdAt,
            recordCount: records.count,
            revisionCount: revisions.count,
            conflictCount: conflicts.count,
            includedKinds: Array(includedKinds).sorted(),
            omittedKinds: Array(Set(omittedKinds)).sorted(),
            payloadSHA256: hash
        )
        let archive = WorkspaceArchive(manifest: manifest, payload: payload, attachmentFiles: archiveFiles, agentWorkspaceFiles: archivedAgentFiles)
        try archive.validate()
        return archive
    }

    public func encoded() throws -> Data {
        try validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(self)
        guard data.count <= Self.maximumArchiveBytes else { throw WorkspaceArchiveError.tooLarge }
        return data
    }

    public static func decode(_ data: Data) throws -> WorkspaceArchive {
        guard data.count <= maximumArchiveBytes else { throw WorkspaceArchiveError.tooLarge }
        let archive = try JSONDecoder().decode(WorkspaceArchive.self, from: data)
        try archive.validate()
        return archive
    }

    public static func decodePackage(_ data: Data) throws -> WorkspaceArchive {
        if data.starts(with: [0x50, 0x4b]) { return try WorkspacePortableArchive.decode(data) }
        return try decode(data)
    }

    public func validate() throws {
        guard [1, 2].contains(manifest.formatVersion), manifest.minimumReaderVersion <= 2,
              manifest.formatVersion == 2 || agentWorkspaceFiles.isEmpty else { throw WorkspaceArchiveError.unsupportedVersion }
        guard !manifest.exportID.isEmpty, manifest.exportID.count <= 100,
              manifest.recordCount == payload.records.count,
              manifest.revisionCount == payload.revisions.count,
              manifest.conflictCount == payload.conflicts.count,
              payload.records.count <= 250_000, payload.revisions.count <= 1_000_000,
              attachmentFiles.count <= 10_000, agentWorkspaceFiles.count <= 250_000 else { throw WorkspaceArchiveError.invalidManifest }
        let recordKeys = payload.records.map { "\($0.kind):\($0.recordID)" }
        guard Set(recordKeys).count == recordKeys.count,
              payload.records.allSatisfy({ RecordKind.syncableKinds.contains($0.kind) && !$0.recordID.isEmpty && $0.revision > 0 && $0.payload.count <= 512_000 && (try? JSONSerialization.jsonObject(with: $0.payload)) != nil }),
              payload.revisions.allSatisfy({ RecordKind.syncableKinds.contains($0.kind) && !$0.recordID.isEmpty && $0.revision > 0 && $0.payload.count <= 512_000 && (try? JSONSerialization.jsonObject(with: $0.payload)) != nil }) else {
            throw WorkspaceArchiveError.invalidRecords
        }
        let attachmentRecords = try payload.records.filter { $0.kind == RecordKind.attachment }.map { try JSONDecoder().decode(AttachmentRecord.self, from: $0.payload) }
        let chatFiles = attachmentFiles.filter { !$0.isArtifactAsset }
        let assetFiles = attachmentFiles.filter(\.isArtifactAsset)
        let artifactReferences = try Self.artifactAssetReferences(in: payload)
        let expectedAssetKeys = Set(artifactReferences.map { "\($0.artifactID)/\($0.descriptor.id)" })
        let actualAssetKeys = Set(assetFiles.compactMap { file in file.artifactID.map { "\($0)/\(file.id)" } })
        let assetGroups = Dictionary(grouping: artifactReferences, by: \.artifactID)
        guard attachmentRecords.allSatisfy({ $0.isValid }),
              attachmentRecords.allSatisfy({ record in payload.records.contains(where: { $0.kind == RecordKind.attachment && $0.recordID == record.id }) }),
              Set(chatFiles.map(\.id)).count == chatFiles.count,
              Set(chatFiles.map(\.id)) == Set(attachmentRecords.map(\.id)),
              Set(expectedAssetKeys).count == artifactReferences.count,
              Set(actualAssetKeys).count == assetFiles.count,
              actualAssetKeys == expectedAssetKeys,
              assetGroups.values.allSatisfy({ references in
                  references.count <= ArtifactAssetStore.maximumAssetsPerArtifact &&
                      references.reduce(0, { $0 + $1.descriptor.byteCount }) <= ArtifactAssetStore.maximumTotalBytesPerArtifact
              }),
              attachmentFiles.allSatisfy(\.isValid),
              chatFiles.allSatisfy({ file in attachmentRecords.contains(where: { $0.id == file.id && $0.byteCount == file.byteCount && $0.sha256 == file.sha256 }) }),
              assetFiles.allSatisfy({ file in artifactReferences.contains(where: { $0.artifactID == file.artifactID && $0.descriptor.id == file.id && $0.descriptor.byteCount == file.byteCount && $0.descriptor.sha256 == file.sha256 && $0.descriptor.mediaType == file.mediaType }) }),
              Self.hasNoDanglingAttachmentReferences(payload, attachmentIDs: Set(attachmentRecords.map(\.id))) else {
            throw WorkspaceArchiveError.invalidRecords
        }
        let conversationIDs = Set(payload.records.filter { $0.kind == RecordKind.conversation }.map(\.recordID))
        let agentFileKeys = agentWorkspaceFiles.map { "\($0.conversationID):\($0.path)" }
        guard agentWorkspaceFiles.allSatisfy(\.isValid),
              agentWorkspaceFiles.allSatisfy({ conversationIDs.contains($0.conversationID) }),
              Set(agentFileKeys).count == agentFileKeys.count,
              Dictionary(grouping: agentWorkspaceFiles, by: \.conversationID).values.allSatisfy({ files in
                  files.count <= OnDeviceAgentWorkspace.maximumListedFiles &&
                      files.reduce(0, { $0 + $1.byteCount }) <= OnDeviceAgentWorkspace.maximumWorkspaceBytes
              }),
              (agentWorkspaceFiles.isEmpty || manifest.includedKinds.contains(RecordKind.agentWorkspace)) else {
            throw WorkspaceArchiveError.invalidAgentWorkspace
        }
        let rawBytes = payload.records.reduce(0) { $0 + $1.payload.count } + payload.revisions.reduce(0) { $0 + $1.payload.count }
        let conflictBytes = payload.conflicts.reduce(0) { $0 + $1.localPayload.count + $1.remotePayload.count }
        let attachmentBytes = attachmentFiles.reduce(0) { $0 + $1.byteCount }
        let agentWorkspaceBytes = agentWorkspaceFiles.reduce(0) { $0 + $1.byteCount }
        guard rawBytes + conflictBytes + attachmentBytes + agentWorkspaceBytes <= 35_000_000 else { throw WorkspaceArchiveError.tooLarge }
        guard payload.conflicts.allSatisfy({ RecordKind.syncableKinds.contains($0.kind) && $0.localPayload.count <= 512_000 && $0.remotePayload.count <= 512_000 }) else {
            throw WorkspaceArchiveError.invalidRecords
        }
        let expected = try Self.payloadHash(payload, attachmentFiles: attachmentFiles, agentWorkspaceFiles: agentWorkspaceFiles)
        guard expected == manifest.payloadSHA256 else { throw WorkspaceArchiveError.checksumMismatch }
    }

    private struct IntegrityPayload: Codable {
        let payload: WorkspaceStoreSnapshot
        let attachmentFiles: [WorkspaceAttachmentFile]
    }

    private struct IntegrityPayloadWithAgentWorkspace: Codable {
        let payload: WorkspaceStoreSnapshot
        let attachmentFiles: [WorkspaceAttachmentFile]
        let agentWorkspaceFiles: [WorkspaceAgentFile]
    }

    private static func payloadHash(_ payload: WorkspaceStoreSnapshot, attachmentFiles: [WorkspaceAttachmentFile], agentWorkspaceFiles: [WorkspaceAgentFile] = []) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        // Archives from before binary attachment support hashed the snapshot directly.
        let data: Data
        if !agentWorkspaceFiles.isEmpty {
            data = try encoder.encode(IntegrityPayloadWithAgentWorkspace(payload: payload, attachmentFiles: attachmentFiles, agentWorkspaceFiles: agentWorkspaceFiles))
        } else {
            data = try attachmentFiles.isEmpty ? encoder.encode(payload) : encoder.encode(IntegrityPayload(payload: payload, attachmentFiles: attachmentFiles))
        }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    public static func artifactAssetReferences(in payload: WorkspaceStoreSnapshot) throws -> [(artifactID: String, descriptor: ArtifactAssetDescriptor)] {
        let snapshots = payload.records.filter { $0.kind == RecordKind.artifact }.map { ($0.recordID, $0.payload) } +
            payload.revisions.filter { $0.kind == RecordKind.artifact }.map { ($0.recordID, $0.payload) }
        var references: [String: ArtifactAssetDescriptor] = [:]
        for (recordID, data) in snapshots {
            let artifact = try JSONDecoder().decode(ArtifactRecord.self, from: data)
            guard artifact.id == recordID, ArtifactAssetStore.isSafeID(artifact.id) else { throw WorkspaceArchiveError.invalidRecords }
            for descriptor in artifact.assetReferences ?? [] {
                guard descriptor.isValid else { throw WorkspaceArchiveError.invalidRecords }
                let key = "\(artifact.id)/\(descriptor.id)"
                if let existing = references[key], existing != descriptor { throw WorkspaceArchiveError.invalidRecords }
                references[key] = descriptor
            }
        }
        for conflict in payload.conflicts where conflict.kind == RecordKind.artifact {
            for data in [conflict.localPayload, conflict.remotePayload] {
                let artifact = try JSONDecoder().decode(ArtifactRecord.self, from: data)
                guard artifact.id == conflict.objectID, ArtifactAssetStore.isSafeID(artifact.id) else {
                    throw WorkspaceArchiveError.invalidRecords
                }
                for descriptor in artifact.assetReferences ?? [] {
                    guard descriptor.isValid else { throw WorkspaceArchiveError.invalidRecords }
                    let key = "\(artifact.id)/\(descriptor.id)"
                    if let existing = references[key], existing != descriptor { throw WorkspaceArchiveError.invalidRecords }
                    references[key] = descriptor
                }
            }
        }
        return references.map { key, descriptor in
            let artifactID = key.components(separatedBy: "/").first ?? ""
            return (artifactID, descriptor)
        }.sorted { ($0.artifactID, $0.descriptor.id) < ($1.artifactID, $1.descriptor.id) }
    }

    private static func hasNoDanglingAttachmentReferences(_ payload: WorkspaceStoreSnapshot, attachmentIDs: Set<String>) -> Bool {
        let messagePayloads = payload.records.filter { $0.kind == RecordKind.message }.map(\.payload) +
            payload.revisions.filter { $0.kind == RecordKind.message }.map(\.payload) +
            payload.conflicts.filter { $0.kind == RecordKind.message }.flatMap { [$0.localPayload, $0.remotePayload] }
        return messagePayloads.allSatisfy { data in
            guard let message = try? JSONDecoder().decode(MessageRecord.self, from: data) else { return false }
            return Set(message.attachmentIDs ?? []).isSubset(of: attachmentIDs)
        }
    }

    private static func messageHasAttachments(_ kind: String, payload: Data) -> Bool {
        guard kind == RecordKind.message,
              let message = try? JSONDecoder().decode(MessageRecord.self, from: payload) else { return false }
        return !(message.attachmentIDs ?? []).isEmpty
    }

    private static func strippingAttachmentReferences(_ kind: String, payload: Data, keeping attachmentIDs: Set<String> = []) throws -> Data {
        guard kind == RecordKind.message,
              var message = try? JSONDecoder().decode(MessageRecord.self, from: payload),
              !(message.attachmentIDs ?? []).isEmpty else { return payload }
        let retained = (message.attachmentIDs ?? []).filter(attachmentIDs.contains)
        message.attachmentIDs = retained.isEmpty ? nil : retained
        return try JSONEncoder().encode(message)
    }
}

public struct WorkspaceImportReport: Equatable, Sendable {
    public let importedRecords: Int
    public let unchangedRecords: Int
    public let conflicts: Int
    public let duplicateArchive: Bool
    public let importedAgentWorkspaceFiles: Int
    public let preservedAgentWorkspaceConflicts: Int
    public let removedEquivalentConflicts: Int
    public let removedDuplicateRevisions: Int

    public init(
        importedRecords: Int, unchangedRecords: Int, conflicts: Int, duplicateArchive: Bool = false,
        importedAgentWorkspaceFiles: Int = 0, preservedAgentWorkspaceConflicts: Int = 0,
        removedEquivalentConflicts: Int = 0, removedDuplicateRevisions: Int = 0
    ) {
        self.importedRecords = importedRecords
        self.unchangedRecords = unchangedRecords
        self.conflicts = conflicts
        self.duplicateArchive = duplicateArchive
        self.importedAgentWorkspaceFiles = importedAgentWorkspaceFiles
        self.preservedAgentWorkspaceConflicts = preservedAgentWorkspaceConflicts
        self.removedEquivalentConflicts = removedEquivalentConflicts
        self.removedDuplicateRevisions = removedDuplicateRevisions
    }

    public var cleanupSummary: String {
        var details: [String] = []
        if removedEquivalentConflicts > 0 { details.append("已移除 (removedEquivalentConflicts) 条内容相同的误报冲突") }
        if removedDuplicateRevisions > 0 { details.append("已合并 (removedDuplicateRevisions) 条重复历史修订") }
        return details.isEmpty ? "" : "；" + details.joined(separator: "；")
    }
}

public enum WorkspaceArchiveError: Error, LocalizedError {
    case tooLarge
    case missingAttachmentFiles
    case attachmentConflict(String)
    case unsupportedVersion
    case invalidManifest
    case invalidRecords
    case invalidAgentWorkspace
    case agentWorkspaceUnavailable
    case agentWorkspaceBusy
    case agentWorkspaceRestoreIncomplete
    case invalidPortableArchive
    case checksumMismatch

    public var errorDescription: String? {
        switch self {
        case .tooLarge: "迁移文件超过 50 MB 限制，或包含超过当前单条记录限制的内容。"
        case .missingAttachmentFiles: "迁移包缺少附件原件；请在保存了原件的设备上重新导出。"
        case .attachmentConflict(let name): "本机已有同 ID 但摘要不同的附件（\(name)）；为避免覆盖，未导入迁移包。"
        case .unsupportedVersion: "迁移文件来自更新版本的 OpenMuse；为保护资料，本版本不会写入。"
        case .invalidManifest, .invalidRecords, .invalidPortableArchive: "迁移文件清单或记录格式无效。"
        case .invalidAgentWorkspace: "迁移文件中的 Agent 工作区无效，或超出对话工作区限制。"
        case .agentWorkspaceUnavailable: "本机 Agent 工作区暂时不可访问；没有导入或导出这些任务草稿。"
        case .agentWorkspaceBusy: "请等当前 Agent 任务结束或取消后再导入迁移文件。"
        case .agentWorkspaceRestoreIncomplete: "资料记录已导入，但任务草稿没有全部恢复。修复本机存储后重新导入即可补回草稿，已有记录不会重复写入。"
        case .checksumMismatch: "迁移文件校验失败；本机资料未改变。"
        }
    }
}
