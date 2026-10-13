import CSQLite
import Foundation

public enum SQLiteStoreError: Error, LocalizedError {
    case open(String)
    case statement(String)
    case encoding
    case decoding

    public var errorDescription: String? {
        switch self {
        case .open(let message), .statement(let message): message
        case .encoding: "无法保存这条记录。"
        case .decoding: "本地记录格式无法读取，原文件已保留。"
        }
    }
}

public struct SQLiteStoreWrite {
    fileprivate let payload: Data
    fileprivate let kind: String
    fileprivate let id: String
    fileprivate let revision: Int
    fileprivate let appendRevision: Bool
}

/// Local-first store. Records, revisions and the sync outbox share one SQLite transaction boundary.
public final class SQLiteStore {
    private static let currentSchemaVersion = 4
    private var handle: OpaquePointer?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let lock = NSRecursiveLock()
    public private(set) var workspaceID = ""
    public private(set) var deviceID = ""

    public init(path: URL) throws {
        try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        let result = sqlite3_open_v2(path.path, &handle, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil)
        guard result == SQLITE_OK, handle != nil else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "无法打开本地数据库。"
            if let handle { sqlite3_close(handle); self.handle = nil }
            throw SQLiteStoreError.open(message)
        }
        sqlite3_busy_timeout(handle, 5_000)
        do {
            let version = try readSchemaVersion()
            guard version <= Self.currentSchemaVersion else {
                throw SQLiteStoreError.open("本地资料库来自更新版本的 OpenMuse；为保护资料，本版本不会降级或覆盖它。")
            }
            try execute("PRAGMA journal_mode=WAL")
            try execute("PRAGMA foreign_keys=ON")
            try configureSchema(existingVersion: version)
            workspaceID = try loadOrCreateMetadata("workspace_id")
            deviceID = try loadOrCreateMetadata("device_id")
            try migrateLegacyOutboxEvents()
        }
        catch {
            if let handle { sqlite3_close(handle) }
            self.handle = nil
            throw error
        }
    }

    private func configureSchema(existingVersion version: Int) throws {
        try execute("BEGIN IMMEDIATE")
        do {
            try execute("CREATE TABLE IF NOT EXISTS records (kind TEXT NOT NULL, id TEXT NOT NULL, revision INTEGER NOT NULL, payload BLOB NOT NULL, created_at REAL NOT NULL, updated_at REAL NOT NULL, PRIMARY KEY(kind, id))")
            try execute("CREATE TABLE IF NOT EXISTS revisions (id TEXT PRIMARY KEY, kind TEXT NOT NULL, object_id TEXT NOT NULL, revision INTEGER NOT NULL, payload BLOB NOT NULL, created_at REAL NOT NULL)")
            try execute("CREATE TABLE IF NOT EXISTS outbox (event_id TEXT PRIMARY KEY, kind TEXT NOT NULL, object_id TEXT NOT NULL, revision INTEGER NOT NULL, payload BLOB NOT NULL, created_at REAL NOT NULL, state TEXT NOT NULL DEFAULT 'pending')")
            try execute("CREATE INDEX IF NOT EXISTS records_kind_updated ON records(kind, updated_at)")
            try execute("CREATE INDEX IF NOT EXISTS revisions_object ON revisions(kind, object_id, revision)")
            try execute("CREATE TABLE IF NOT EXISTS sync_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)")
            try execute("CREATE TABLE IF NOT EXISTS sync_events (local_order INTEGER PRIMARY KEY AUTOINCREMENT, event_id TEXT NOT NULL UNIQUE, workspace_id TEXT NOT NULL, device_id TEXT NOT NULL, device_sequence INTEGER NOT NULL, object_id TEXT NOT NULL, kind TEXT NOT NULL, base_revision INTEGER NOT NULL, revision INTEGER NOT NULL, parent_revision_ids TEXT NOT NULL, appends_revision INTEGER NOT NULL, payload_hash TEXT NOT NULL, payload BLOB NOT NULL, created_at REAL NOT NULL, UNIQUE(workspace_id,device_id,device_sequence))")
            try execute("CREATE TABLE IF NOT EXISTS sync_cursors (workspace_id TEXT NOT NULL, device_id TEXT NOT NULL, sequence INTEGER NOT NULL, PRIMARY KEY(workspace_id,device_id))")
            try execute("CREATE TABLE IF NOT EXISTS sync_conflicts (id TEXT PRIMARY KEY, event_id TEXT NOT NULL UNIQUE, workspace_id TEXT NOT NULL, object_id TEXT NOT NULL, kind TEXT NOT NULL, local_revision INTEGER NOT NULL, remote_revision INTEGER NOT NULL, local_payload BLOB NOT NULL, remote_payload BLOB NOT NULL, created_at REAL NOT NULL)")
            try execute("CREATE TABLE IF NOT EXISTS imported_archives (export_id TEXT PRIMARY KEY, imported_at REAL NOT NULL)")
            try execute("CREATE VIRTUAL TABLE IF NOT EXISTS message_search USING fts5(message_id UNINDEXED, conversation_id UNINDEXED, role UNINDEXED, imported_from UNINDEXED, created_at UNINDEXED, terms, tokenize='unicode61')")
            try execute("CREATE INDEX IF NOT EXISTS sync_events_workspace_order ON sync_events(workspace_id,local_order)")
            try execute("CREATE INDEX IF NOT EXISTS sync_conflicts_workspace ON sync_conflicts(workspace_id,created_at)")
            if version < 4 { try rebuildMessageSearchIndex() }
            if version < Self.currentSchemaVersion { try execute("PRAGMA user_version=\(Self.currentSchemaVersion)") }
            try execute("COMMIT")
        } catch {
            _ = try? execute("ROLLBACK")
            throw error
        }
    }

    private func readSchemaVersion() throws -> Int {
        guard let handle else { throw SQLiteStoreError.open("本地数据库未打开。") }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, "PRAGMA user_version", -1, &statement, nil) == SQLITE_OK, let statement else {
            throw SQLiteStoreError.statement(String(cString: sqlite3_errmsg(handle)))
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { throw SQLiteStoreError.statement(String(cString: sqlite3_errmsg(handle))) }
        return Int(sqlite3_column_int(statement, 0))
    }

    deinit {
        if let handle { sqlite3_close(handle) }
    }

    public func save<T: Encodable>(_ value: T, kind: String, id: String, revision: Int = 1, appendRevision: Bool = false) throws {
        try saveAtomically([prepareWrite(value, kind: kind, id: id, revision: revision, appendRevision: appendRevision)])
    }

    public func exportSnapshot() throws -> WorkspaceStoreSnapshot {
        lock.lock(); defer { lock.unlock() }
        guard let handle else { throw SQLiteStoreError.open("本地资料库未打开。") }
        var recordsStatement: OpaquePointer?
        let recordsSQL = "SELECT kind,id,revision,payload,created_at,updated_at FROM records ORDER BY kind,id"
        guard sqlite3_prepare_v2(handle, recordsSQL, -1, &recordsStatement, nil) == SQLITE_OK, let recordsStatement else {
            throw SQLiteStoreError.statement(String(cString: sqlite3_errmsg(handle)))
        }
        defer { sqlite3_finalize(recordsStatement) }
        var records: [WorkspaceRecordSnapshot] = []
        while sqlite3_step(recordsStatement) == SQLITE_ROW {
            guard let kind = sqlite3_column_text(recordsStatement, 0), let id = sqlite3_column_text(recordsStatement, 1),
                  let payload = sqlite3_column_blob(recordsStatement, 3) else { continue }
            records.append(WorkspaceRecordSnapshot(
                kind: String(cString: kind), recordID: String(cString: id), revision: Int(sqlite3_column_int64(recordsStatement, 2)),
                payload: Data(bytes: payload, count: Int(sqlite3_column_bytes(recordsStatement, 3))),
                createdAt: Date(timeIntervalSince1970: sqlite3_column_double(recordsStatement, 4)),
                updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(recordsStatement, 5))
            ))
        }

        var revisionsStatement: OpaquePointer?
        let revisionsSQL = "SELECT kind,object_id,revision,payload,created_at FROM revisions ORDER BY kind,object_id,revision,created_at"
        guard sqlite3_prepare_v2(handle, revisionsSQL, -1, &revisionsStatement, nil) == SQLITE_OK, let revisionsStatement else {
            throw SQLiteStoreError.statement(String(cString: sqlite3_errmsg(handle)))
        }
        defer { sqlite3_finalize(revisionsStatement) }
        var revisions: [WorkspaceRevisionSnapshot] = []
        while sqlite3_step(revisionsStatement) == SQLITE_ROW {
            guard let kind = sqlite3_column_text(revisionsStatement, 0), let id = sqlite3_column_text(revisionsStatement, 1),
                  let payload = sqlite3_column_blob(revisionsStatement, 3) else { continue }
            revisions.append(WorkspaceRevisionSnapshot(
                kind: String(cString: kind), recordID: String(cString: id), revision: Int(sqlite3_column_int64(revisionsStatement, 2)),
                payload: Data(bytes: payload, count: Int(sqlite3_column_bytes(revisionsStatement, 3))),
                createdAt: Date(timeIntervalSince1970: sqlite3_column_double(revisionsStatement, 4))
            ))
        }
        return WorkspaceStoreSnapshot(records: records, revisions: revisions, conflicts: try loadSyncConflicts())
    }

    public func importSnapshot(_ archive: WorkspaceArchive) throws -> WorkspaceImportReport {
        try archive.validate()
        lock.lock(); defer { lock.unlock() }
        guard handle != nil else { throw SQLiteStoreError.open("本地资料库未打开。") }
        try execute("BEGIN IMMEDIATE")
        do {
            if try hasImportedArchive(archive.manifest.exportID) {
                let removedEquivalentConflicts = try removeEquivalentSyncConflicts().count
                let removedDuplicateRevisions = try removeEquivalentDuplicateRevisions().count
                try execute("COMMIT")
                return WorkspaceImportReport(
                    importedRecords: 0, unchangedRecords: 0, conflicts: 0, duplicateArchive: true,
                    removedEquivalentConflicts: removedEquivalentConflicts,
                    removedDuplicateRevisions: removedDuplicateRevisions
                )
            }
            var imported = 0
            var unchanged = 0
            var conflicts = 0
            var insertedConflictIDs = Set<String>()
            let archivedConflictKeys = Set(archive.payload.conflicts.map { "\($0.kind):\($0.objectID)" })
            let archivedTombstones = archive.payload.records.compactMap { snapshot -> DeletionTombstoneRecord? in
                guard snapshot.kind == RecordKind.deletionTombstone else { return nil }
                return try? decoder.decode(DeletionTombstoneRecord.self, from: snapshot.payload)
            }
            let archivedDeletedKeys = Set(archivedTombstones.map { "\($0.recordKind):\($0.recordID)" })
            let localTombstones = try load(DeletionTombstoneRecord.self, kind: RecordKind.deletionTombstone)
            let deletedKeys = Set((localTombstones + archivedTombstones).map { "\($0.recordKind):\($0.recordID)" })
            let latestMemoryDeletionAt = (localTombstones + archivedTombstones)
                .filter { $0.recordKind == RecordKind.memoryClaim }
                .map(\.deletedAt)
                .max()
            let importOrder = archive.payload.records.sorted { left, right in
                left.kind == RecordKind.deletionTombstone && right.kind != RecordKind.deletionTombstone
            }
            for record in importOrder {
                if record.kind == RecordKind.document, record.recordID == "USER.md",
                   let latestMemoryDeletionAt, record.updatedAt < latestMemoryDeletionAt {
                    unchanged += 1
                    continue
                }
                if record.kind != RecordKind.deletionTombstone,
                   archivedDeletedKeys.contains("\(record.kind):\(record.recordID)"),
                   try activeTombstone(kind: record.kind, id: record.recordID) == nil {
                    unchanged += 1
                    continue
                }
                if record.kind != RecordKind.deletionTombstone,
                   try activeTombstone(kind: record.kind, id: record.recordID) != nil {
                    unchanged += 1
                    continue
                }
                let current = try recordState(kind: record.kind, id: record.recordID)
                if current.payload == nil {
                    try insert(record.payload, kind: record.kind, id: record.recordID, revision: record.revision, createdAt: record.createdAt, updatedAt: record.updatedAt)
                    try insertRevisionIfMissing(record.payload, kind: record.kind, objectID: record.recordID, revision: record.revision, createdAt: record.updatedAt)
                    let event = SyncEnvelope(
                        workspaceID: workspaceID, deviceID: deviceID, deviceSequence: try nextDeviceSequence(),
                        objectID: record.recordID, kind: record.kind, baseRevision: 0, revision: record.revision,
                        appendsRevision: true, payload: record.payload, createdAt: record.updatedAt
                    )
                    try insertSyncEnvelope(event)
                    try insertOutbox(event)
                    try setSyncCursor(workspaceID: workspaceID, deviceID: deviceID, sequence: event.deviceSequence)
                    if record.kind == RecordKind.deletionTombstone,
                       let tombstone = try? decoder.decode(DeletionTombstoneRecord.self, from: record.payload) {
                        if tombstone.recordKind == RecordKind.attachment { try removeAttachmentReferences(tombstone.recordID) }
                        try eraseRecordPayloads(kind: tombstone.recordKind, id: tombstone.recordID)
                        try redactHistoricalSyncPayloads(kind: tombstone.recordKind, id: tombstone.recordID)
                    }
                    imported += 1
                } else if payloadsAreEquivalent(current.payload!, record.payload) ||
                    (record.kind == RecordKind.document && documentsAreEquivalent(current.payload!, record.payload)) {
                    unchanged += 1
                } else {
                    if !archivedConflictKeys.contains("\(record.kind):\(record.recordID)") {
                        let conflict = SyncConflictRecord(
                            id: UUID().uuidString, eventID: "import-\(UUID().uuidString)", workspaceID: workspaceID,
                            objectID: record.recordID, kind: record.kind, localRevision: current.revision,
                            remoteRevision: record.revision, localPayload: current.payload!, remotePayload: record.payload,
                            createdAt: archive.manifest.createdAt
                        )
                        try insertSyncConflict(conflict)
                        insertedConflictIDs.insert(conflict.id)
                        conflicts += 1
                    }
                }
            }
            for revision in archive.payload.revisions {
                if deletedKeys.contains("\(revision.kind):\(revision.recordID)") { continue }
                if revision.kind == RecordKind.document, revision.recordID == "USER.md",
                   let latestMemoryDeletionAt, revision.createdAt < latestMemoryDeletionAt {
                    continue
                }
                try insertRevisionIfMissing(revision.payload, kind: revision.kind, objectID: revision.recordID, revision: revision.revision, createdAt: revision.createdAt)
            }
            for archivedConflict in archive.payload.conflicts {
                if deletedKeys.contains("\(archivedConflict.kind):\(archivedConflict.objectID)") { continue }
                if archivedConflict.kind == RecordKind.document, archivedConflict.objectID == "USER.md",
                   let latestMemoryDeletionAt, archivedConflict.createdAt < latestMemoryDeletionAt {
                    continue
                }
                let current = try recordState(kind: archivedConflict.kind, id: archivedConflict.objectID)
                var alternatives: [(Data, Int)] = [
                    (archivedConflict.localPayload, archivedConflict.localRevision),
                    (archivedConflict.remotePayload, archivedConflict.remoteRevision)
                ]
                if let record = archive.payload.records.first(where: { $0.kind == archivedConflict.kind && $0.recordID == archivedConflict.objectID }) {
                    alternatives.append((record.payload, record.revision))
                }
                var seenAlternatives: [Data] = []
                alternatives = alternatives.filter { payload, _ in
                    guard !seenAlternatives.contains(where: { payloadsAreEquivalent($0, payload) }) else { return false }
                    if let currentPayload = current.payload, payloadsAreEquivalent(payload, currentPayload) { return false }
                    seenAlternatives.append(payload)
                    return true
                }
                for (alternative, alternativeRevision) in alternatives {
                    let importedConflict = SyncConflictRecord(
                        id: UUID().uuidString, eventID: "archive-\(UUID().uuidString)", workspaceID: workspaceID,
                        objectID: archivedConflict.objectID, kind: archivedConflict.kind,
                        localRevision: current.payload == nil ? archivedConflict.localRevision : current.revision,
                        remoteRevision: alternativeRevision,
                        localPayload: current.payload ?? archivedConflict.localPayload,
                        remotePayload: alternative, createdAt: archivedConflict.createdAt
                    )
                    if try !hasEquivalentConflict(importedConflict) {
                        try insertSyncConflict(importedConflict)
                        insertedConflictIDs.insert(importedConflict.id)
                        conflicts += 1
                    }
                }
            }
            let removedEquivalentConflictIDs = try removeEquivalentSyncConflicts()
            let removedDuplicateRevisionIDs = try removeEquivalentDuplicateRevisions()
            conflicts = max(0, conflicts - insertedConflictIDs.intersection(removedEquivalentConflictIDs).count)
            try registerImportedArchive(archive.manifest.exportID)
            try execute("COMMIT")
            return WorkspaceImportReport(
                importedRecords: imported, unchangedRecords: unchanged, conflicts: conflicts,
                removedEquivalentConflicts: removedEquivalentConflictIDs.count,
                removedDuplicateRevisions: removedDuplicateRevisionIDs.count
            )
        } catch {
            _ = try? execute("ROLLBACK")
            throw error
        }
    }

    func prepareWrite<T: Encodable>(_ value: T, kind: String, id: String, revision: Int = 1, appendRevision: Bool = false) throws -> SQLiteStoreWrite {
        SQLiteStoreWrite(payload: try encoder.encode(value), kind: kind, id: id, revision: revision, appendRevision: appendRevision)
    }

    public func saveAtomically(_ writes: [SQLiteStoreWrite]) throws {
        try saveAtomically(writes, pruningHistoryFor: [])
    }

    func saveAtomically(_ writes: [SQLiteStoreWrite], pruningHistoryFor prunedRecords: [(kind: String, id: String)]) throws {
        guard !writes.isEmpty else { return }
        lock.lock(); defer { lock.unlock() }
        guard handle != nil else { throw SQLiteStoreError.open("本地资料库未打开。") }
        try execute("BEGIN IMMEDIATE")
        do {
            for write in writes {
                try persist(write)
            }
            for record in prunedRecords {
                try pruneRecordHistoryWithinTransaction(kind: record.kind, id: record.id, keepingLatestSyncEvent: true)
            }
            try execute("COMMIT")
        } catch {
            _ = try? execute("ROLLBACK")
            throw error
        }
    }

    /// Creates a local-first task record. A queued task has no owner until one device claims it.
    public func createExecutionTask(_ task: TaskExecutionRecord) throws {
        guard task.isValid, task.status == "queued", task.runEpoch == 0,
              task.ownerDeviceID == nil, task.lastCheckpointSequence == 0,
              task.lastCommittedCheckpointID == nil, task.parentTaskID == nil, task.branchID == nil else {
            throw TaskExecutionError.invalidTransition
        }
        lock.lock(); defer { lock.unlock() }
        guard handle != nil else { throw SQLiteStoreError.open("本地资料库未打开。") }
        try execute("BEGIN IMMEDIATE")
        do {
            guard try currentRevision(kind: RecordKind.executionTask, id: task.id) == 0 else {
                throw TaskExecutionError.invalidTransition
            }
            try persist(prepareWrite(task, kind: RecordKind.executionTask, id: task.id, appendRevision: true))
            try execute("COMMIT")
        } catch {
            _ = try? execute("ROLLBACK")
            throw error
        }
    }

    /// Marks only this installation's interrupted runs as suspended. Records owned by a paired
    /// device remain running until that device or an explicit handoff changes their state.
    @discardableResult
    public func suspendOwnedRunningExecutionTasks(ownerDeviceID: String) throws -> [TaskExecutionRecord] {
        guard !ownerDeviceID.isEmpty, ownerDeviceID.count <= 100 else { throw TaskExecutionError.invalidTransition }
        lock.lock(); defer { lock.unlock() }
        guard handle != nil else { throw SQLiteStoreError.open("本地资料库未打开。") }
        let candidates = try load(TaskExecutionRecord.self, kind: RecordKind.executionTask)
            .filter { $0.status == "running" && $0.ownerDeviceID == ownerDeviceID }
        guard !candidates.isEmpty else { return [] }
        try execute("BEGIN IMMEDIATE")
        do {
            var suspended: [TaskExecutionRecord] = []
            for candidate in candidates {
                guard var task = try storedRecord(TaskExecutionRecord.self, kind: RecordKind.executionTask, id: candidate.id),
                      task.status == "running", task.ownerDeviceID == ownerDeviceID else { continue }
                task.status = "suspended"
                task.updatedAt = .now
                try persist(prepareWrite(task, kind: RecordKind.executionTask, id: task.id, appendRevision: true))
                suspended.append(task)
            }
            try execute("COMMIT")
            return suspended
        } catch {
            _ = try? execute("ROLLBACK")
            throw error
        }
    }

    /// Claims queued work or resumes suspended work using a compare-and-swap epoch.
    /// A queued task preassigned by a completed handoff keeps that handoff's new epoch.
    @discardableResult
    public func claimExecutionTask(id: String, ownerDeviceID: String, expectedEpoch: Int) throws -> TaskExecutionRecord {
        guard !ownerDeviceID.isEmpty, ownerDeviceID.count <= 100, expectedEpoch >= 0 else {
            throw TaskExecutionError.invalidTransition
        }
        lock.lock(); defer { lock.unlock() }
        guard handle != nil else { throw SQLiteStoreError.open("本地资料库未打开。") }
        try execute("BEGIN IMMEDIATE")
        do {
            guard var task = try storedRecord(TaskExecutionRecord.self, kind: RecordKind.executionTask, id: id) else {
                throw TaskExecutionError.missingTask
            }
            guard task.isValid, task.runEpoch == expectedEpoch else { throw TaskExecutionError.staleEpoch }
            guard task.status == "queued" || task.status == "suspended" || task.status == "waiting_device" else {
                throw TaskExecutionError.invalidTransition
            }
            if task.status != "queued" || task.ownerDeviceID != ownerDeviceID {
                task.runEpoch += 1
            }
            task.ownerDeviceID = ownerDeviceID
            task.status = "running"
            task.updatedAt = .now
            try persist(prepareWrite(task, kind: RecordKind.executionTask, id: task.id, appendRevision: true))
            try execute("COMMIT")
            return task
        } catch {
            _ = try? execute("ROLLBACK")
            throw error
        }
    }

    /// Transfers ownership only after the current owner has reached its latest committed checkpoint.
    /// The new epoch invalidates any late response from the previous owner.
    @discardableResult
    public func handoffExecutionTask(id: String, fromOwner: String, toOwner: String, expectedEpoch: Int, checkpointID: String?) throws -> TaskExecutionRecord {
        guard !toOwner.isEmpty, toOwner.count <= 100, fromOwner != toOwner else { throw TaskExecutionError.invalidTransition }
        lock.lock(); defer { lock.unlock() }
        guard handle != nil else { throw SQLiteStoreError.open("本地资料库未打开。") }
        try execute("BEGIN IMMEDIATE")
        do {
            guard var task = try storedRecord(TaskExecutionRecord.self, kind: RecordKind.executionTask, id: id) else {
                throw TaskExecutionError.missingTask
            }
            guard task.runEpoch == expectedEpoch else { throw TaskExecutionError.staleEpoch }
            guard task.ownerDeviceID == fromOwner else { throw TaskExecutionError.wrongOwner }
            guard task.status == "running", task.lastCommittedCheckpointID == checkpointID else {
                throw TaskExecutionError.invalidTransition
            }
            if let checkpointID {
                guard let checkpoint = try storedRecord(TaskCheckpointRecord.self, kind: RecordKind.taskCheckpoint, id: checkpointID),
                      checkpoint.taskID == task.id, checkpoint.runEpoch == expectedEpoch,
                      checkpoint.ownerDeviceID == fromOwner else { throw TaskExecutionError.invalidCheckpoint }
            } else if task.lastCheckpointSequence != 0 {
                throw TaskExecutionError.invalidCheckpoint
            }
            task.ownerDeviceID = toOwner
            task.runEpoch += 1
            task.status = "queued"
            task.updatedAt = .now
            try persist(prepareWrite(task, kind: RecordKind.executionTask, id: task.id, appendRevision: true))
            try execute("COMMIT")
            return task
        } catch {
            _ = try? execute("ROLLBACK")
            throw error
        }
    }

    /// Starts a visible, separately stored branch from the last checkpoint when the original owner is unreachable.
    /// It deliberately does not claim that the original task has stopped.
    public func createOfflineExecutionBranch(parentTaskID: String, newOwnerDeviceID: String, expectedEpoch: Int, checkpointID: String) throws -> TaskExecutionRecord {
        guard !newOwnerDeviceID.isEmpty, newOwnerDeviceID.count <= 100, !checkpointID.isEmpty else {
            throw TaskExecutionError.invalidTransition
        }
        lock.lock(); defer { lock.unlock() }
        guard handle != nil else { throw SQLiteStoreError.open("本地资料库未打开。") }
        try execute("BEGIN IMMEDIATE")
        do {
            guard let parent = try storedRecord(TaskExecutionRecord.self, kind: RecordKind.executionTask, id: parentTaskID) else {
                throw TaskExecutionError.missingTask
            }
            guard parent.runEpoch == expectedEpoch else { throw TaskExecutionError.staleEpoch }
            guard parent.status == "running", parent.lastCommittedCheckpointID == checkpointID,
                  let checkpoint = try storedRecord(TaskCheckpointRecord.self, kind: RecordKind.taskCheckpoint, id: checkpointID),
                  checkpoint.taskID == parent.id, checkpoint.runEpoch == expectedEpoch,
                  checkpoint.sequence == parent.lastCheckpointSequence else { throw TaskExecutionError.invalidCheckpoint }
            var branch = TaskExecutionRecord(
                goalID: parent.goalID,
                conversationID: parent.conversationID,
                constraintRevision: parent.constraintRevision,
                requiredCapabilities: parent.requiredCapabilities,
                status: "running",
                runEpoch: expectedEpoch + 1,
                ownerDeviceID: newOwnerDeviceID,
                lastCommittedCheckpointID: checkpoint.id,
                lastCheckpointSequence: checkpoint.sequence,
                parentTaskID: parent.id,
                branchID: UUID().uuidString
            )
            branch.createdAt = .now
            branch.updatedAt = branch.createdAt
            try persist(prepareWrite(branch, kind: RecordKind.executionTask, id: branch.id, appendRevision: true))
            try execute("COMMIT")
            return branch
        } catch {
            _ = try? execute("ROLLBACK")
            throw error
        }
    }

    /// Commits one bounded step result and the task's resume pointer in one SQLite transaction.
    @discardableResult
    public func commitExecutionCheckpoint(_ checkpoint: TaskCheckpointRecord) throws -> TaskCheckpointRecord {
        guard checkpoint.isValid else { throw TaskExecutionError.invalidCheckpoint }
        lock.lock(); defer { lock.unlock() }
        guard handle != nil else { throw SQLiteStoreError.open("本地资料库未打开。") }
        try execute("BEGIN IMMEDIATE")
        do {
            if let existing = try storedRecord(TaskCheckpointRecord.self, kind: RecordKind.taskCheckpoint, id: checkpoint.id) {
                guard Self.checkpointsMatch(existing, checkpoint) else { throw TaskExecutionError.conflictingCheckpoint }
                try execute("COMMIT")
                return existing
            }
            guard var task = try storedRecord(TaskExecutionRecord.self, kind: RecordKind.executionTask, id: checkpoint.taskID) else {
                throw TaskExecutionError.missingTask
            }
            guard task.runEpoch == checkpoint.runEpoch else { throw TaskExecutionError.staleEpoch }
            guard task.ownerDeviceID == checkpoint.ownerDeviceID else { throw TaskExecutionError.wrongOwner }
            guard task.status == "running", checkpoint.sequence == task.lastCheckpointSequence + 1 else {
                throw TaskExecutionError.invalidCheckpoint
            }
            task.lastCheckpointSequence = checkpoint.sequence
            task.lastCommittedCheckpointID = checkpoint.id
            task.updatedAt = .now
            try persist(prepareWrite(checkpoint, kind: RecordKind.taskCheckpoint, id: checkpoint.id))
            try persist(prepareWrite(task, kind: RecordKind.executionTask, id: task.id, appendRevision: true))
            try execute("COMMIT")
            return checkpoint
        } catch {
            _ = try? execute("ROLLBACK")
            throw error
        }
    }

    @discardableResult
    public func setExecutionTaskStatus(id: String, ownerDeviceID: String, expectedEpoch: Int, status: String) throws -> TaskExecutionRecord {
        guard ["waiting_user", "waiting_device", "suspended", "completed", "failed", "cancelled"].contains(status) else {
            throw TaskExecutionError.invalidTransition
        }
        lock.lock(); defer { lock.unlock() }
        guard handle != nil else { throw SQLiteStoreError.open("本地资料库未打开。") }
        try execute("BEGIN IMMEDIATE")
        do {
            guard var task = try storedRecord(TaskExecutionRecord.self, kind: RecordKind.executionTask, id: id) else {
                throw TaskExecutionError.missingTask
            }
            guard task.runEpoch == expectedEpoch else { throw TaskExecutionError.staleEpoch }
            guard task.ownerDeviceID == ownerDeviceID else { throw TaskExecutionError.wrongOwner }
            guard task.status == "running" else { throw TaskExecutionError.invalidTransition }
            task.status = status
            task.updatedAt = .now
            try persist(prepareWrite(task, kind: RecordKind.executionTask, id: task.id, appendRevision: true))
            try execute("COMMIT")
            return task
        } catch {
            _ = try? execute("ROLLBACK")
            throw error
        }
    }

    /// Permanently removes a record from this store and propagates a content-free tombstone.
    /// Historical sync envelopes are redacted while their sequence numbers remain intact.
    @discardableResult
    public func forgetRecord(kind: String, id: String, deletedAt: Date = .now) throws -> DeletionTombstoneRecord {
        try forgetRecords([(kind: kind, id: id)], deletedAt: deletedAt)[0]
    }

    /// Permanently removes related records in one transaction, so derived private data cannot
    /// survive when a user forgets the source memory.
    @discardableResult
    public func forgetRecords(_ items: [(kind: String, id: String)], deletedAt: Date = .now) throws -> [DeletionTombstoneRecord] {
        try forgetRecords(items, andSaving: [], deletedAt: deletedAt)
    }

    /// Atomically removes private records and updates any surviving import batch projections.
    @discardableResult
    func forgetRecords(
        _ items: [(kind: String, id: String)],
        andSaving writes: [SQLiteStoreWrite],
        pruningHistoryFor prunedRecords: [(kind: String, id: String)] = [],
        deletedAt: Date = .now
    ) throws -> [DeletionTombstoneRecord] {
        guard !items.isEmpty, items.count <= 10_000,
              items.allSatisfy({ RecordKind.syncableKinds.contains($0.kind) && $0.kind != RecordKind.deletionTombstone && !$0.id.isEmpty && $0.id.count <= 200 }),
              writes.count <= 500, prunedRecords.count <= 500,
              writes.allSatisfy({ RecordKind.syncableKinds.contains($0.kind) && !$0.id.isEmpty && $0.id.count <= 200 }),
              prunedRecords.allSatisfy({ RecordKind.syncableKinds.contains($0.kind) && !$0.id.isEmpty && $0.id.count <= 200 }) else {
            throw SyncApplyError.invalidEnvelope
        }
        var seen = Set<String>()
        let uniqueItems = items.filter { seen.insert("\($0.kind):\($0.id)").inserted }
        let deletedKeys = Set(uniqueItems.map { "\($0.kind):\($0.id)" })
        guard writes.allSatisfy({ !deletedKeys.contains("\($0.kind):\($0.id)") }) else { throw SyncApplyError.invalidEnvelope }
        lock.lock(); defer { lock.unlock() }
        guard handle != nil else { throw SQLiteStoreError.open("本地数据库未打开。") }
        try execute("BEGIN IMMEDIATE")
        do {
            var tombstones: [DeletionTombstoneRecord] = []
            for item in uniqueItems {
                if let existing = try activeTombstone(kind: item.kind, id: item.id) {
                    tombstones.append(existing)
                    continue
                }
                if item.kind == RecordKind.attachment { try removeAttachmentReferences(item.id) }
                let tombstoneID = DeletionTombstoneRecord.stableID(kind: item.kind, id: item.id)
                let tombstone = DeletionTombstoneRecord(recordKind: item.kind, recordID: item.id, deletedAt: deletedAt)
                let baseRevision = try currentRevision(kind: RecordKind.deletionTombstone, id: tombstoneID)
                let revision = baseRevision + 1
                let payload = try encoder.encode(tombstone)
                try insert(payload, kind: RecordKind.deletionTombstone, id: tombstoneID, revision: revision, createdAt: deletedAt, updatedAt: deletedAt)
                try insertRevision(payload, kind: RecordKind.deletionTombstone, objectID: tombstoneID, revision: revision, createdAt: deletedAt)
                let parent = try latestSyncEventID(kind: RecordKind.deletionTombstone, objectID: tombstoneID).map { [$0] } ?? []
                let event = SyncEnvelope(
                    workspaceID: workspaceID, deviceID: deviceID, deviceSequence: try nextDeviceSequence(),
                    objectID: tombstoneID, kind: RecordKind.deletionTombstone, baseRevision: baseRevision,
                    revision: revision, parentRevisionIDs: parent, appendsRevision: true, payload: payload, createdAt: deletedAt
                )
                try insertSyncEnvelope(event)
                try insertOutbox(event)
                try setSyncCursor(workspaceID: workspaceID, deviceID: deviceID, sequence: event.deviceSequence)
                try eraseRecordPayloads(kind: item.kind, id: item.id)
                try redactHistoricalSyncPayloads(kind: item.kind, id: item.id)
                tombstones.append(tombstone)
            }
            for write in writes { try persist(write) }
            let deletedRecordKeys = Set(uniqueItems.map { "\($0.kind):\($0.id)" })
            for record in prunedRecords where !deletedRecordKeys.contains("\(record.kind):\(record.id)") {
                try pruneRecordHistoryWithinTransaction(kind: record.kind, id: record.id, keepingLatestSyncEvent: true)
            }
            try execute("COMMIT")
            return tombstones
        } catch {
            _ = try? execute("ROLLBACK")
            throw error
        }
    }

    /// Drops old revisions after a user has explicitly removed sensitive text from a projection file.
    public func pruneRecordHistory(kind: String, id: String) throws {
        lock.lock(); defer { lock.unlock() }
        guard handle != nil else { throw SQLiteStoreError.open("本地数据库未打开。") }
        try execute("BEGIN IMMEDIATE")
        do {
            try pruneRecordHistoryWithinTransaction(kind: kind, id: id, keepingLatestSyncEvent: true)
            try execute("COMMIT")
        } catch {
            _ = try? execute("ROLLBACK")
            throw error
        }
    }

    private func pruneRecordHistoryWithinTransaction(kind: String, id: String, keepingLatestSyncEvent: Bool) throws {
        guard let handle else { throw SQLiteStoreError.open("本地资料库未打开。") }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, "DELETE FROM revisions WHERE kind=? AND object_id=?", -1, &statement, nil) == SQLITE_OK, let statement else {
            throw SQLiteStoreError.statement(String(cString: sqlite3_errmsg(handle)))
        }
        bind(kind, to: statement, at: 1); bind(id, to: statement, at: 2)
        let result = sqlite3_step(statement)
        sqlite3_finalize(statement)
        guard result == SQLITE_DONE else { throw SQLiteStoreError.statement(String(cString: sqlite3_errmsg(handle))) }
        try eraseConflictPayloads(kind: kind, id: id)
        try redactHistoricalSyncPayloads(kind: kind, id: id, keepingLatest: keepingLatestSyncEvent)
    }

    public func load<T: Decodable>(_ type: T.Type, kind: String) throws -> [T] {
        lock.lock(); defer { lock.unlock() }
        guard let handle else { throw SQLiteStoreError.open("本地数据库未打开。") }
        var statement: OpaquePointer?
        let sql = "SELECT payload FROM records WHERE kind=? ORDER BY updated_at DESC"
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw SQLiteStoreError.statement(String(cString: sqlite3_errmsg(handle)))
        }
        defer { sqlite3_finalize(statement) }
        bind(kind, to: statement, at: 1)
        var values: [T] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let bytes = sqlite3_column_blob(statement, 0) else { continue }
            let count = Int(sqlite3_column_bytes(statement, 0))
            let data = Data(bytes: bytes, count: count)
            do { values.append(try decoder.decode(type, from: data)) }
            catch { throw SQLiteStoreError.decoding }
        }
        return values
    }

    /// Finds only original user-authored messages. Imported conversations and the
    /// current/parent conversation are excluded by default at the call site.
    public func searchUserMessages(matching terms: Set<String>, excludingConversationIDs: Set<String> = [], limit: Int = 8) throws -> [MessageRecord] {
        let safeTerms = terms.filter { !$0.isEmpty && $0.count <= 64 && $0.allSatisfy { $0.isLetter || $0.isNumber } }.sorted()
        guard !safeTerms.isEmpty, limit > 0 else { return [] }
        lock.lock(); defer { lock.unlock() }
        guard let handle else { throw SQLiteStoreError.open("本地数据库未打开。") }
        let matchExpression = "terms : (" + safeTerms.map { "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"" }.joined(separator: " OR ") + ")"
        let excluded = excludingConversationIDs.sorted()
        let exclusionSQL = excluded.isEmpty ? "" : " AND message_search.conversation_id NOT IN (" + Array(repeating: "?", count: excluded.count).joined(separator: ",") + ")"
        let sql = "SELECT r.payload FROM message_search JOIN records AS r ON r.kind='message' AND r.id=message_search.message_id WHERE message_search MATCH ? AND message_search.role='user' AND COALESCE(message_search.imported_from,'')=''\(exclusionSQL) ORDER BY bm25(message_search), CAST(message_search.created_at AS REAL) DESC LIMIT ?"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw SQLiteStoreError.statement(String(cString: sqlite3_errmsg(handle)))
        }
        defer { sqlite3_finalize(statement) }
        bind(matchExpression, to: statement, at: 1)
        var parameterIndex: Int32 = 2
        for conversationID in excluded {
            bind(conversationID, to: statement, at: parameterIndex)
            parameterIndex += 1
        }
        sqlite3_bind_int64(statement, parameterIndex, sqlite3_int64(min(limit, 50)))
        var results = [MessageRecord]()
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let bytes = sqlite3_column_blob(statement, 0) else { continue }
            let data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 0)))
            do { results.append(try decoder.decode(MessageRecord.self, from: data)) }
            catch { throw SQLiteStoreError.decoding }
        }
        return results
    }

    public func revisions<T: Decodable>(_ type: T.Type, kind: String, objectID: String) throws -> [T] {
        lock.lock(); defer { lock.unlock() }
        guard let handle else { throw SQLiteStoreError.open("本地数据库未打开。") }
        var statement: OpaquePointer?
        let sql = "SELECT payload FROM revisions WHERE kind=? AND object_id=? ORDER BY revision"
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw SQLiteStoreError.statement(String(cString: sqlite3_errmsg(handle)))
        }
        defer { sqlite3_finalize(statement) }
        bind(kind, to: statement, at: 1); bind(objectID, to: statement, at: 2)
        var values: [T] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let bytes = sqlite3_column_blob(statement, 0) else { continue }
            let count = Int(sqlite3_column_bytes(statement, 0))
            values.append(try decoder.decode(type, from: Data(bytes: bytes, count: count)))
        }
        return values
    }

    public func pendingOutboxCount() throws -> Int {
        lock.lock(); defer { lock.unlock() }
        guard let handle else { throw SQLiteStoreError.open("本地数据库未打开。") }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, "SELECT COUNT(*) FROM outbox WHERE state='pending'", -1, &statement, nil) == SQLITE_OK, let statement else {
            throw SQLiteStoreError.statement(String(cString: sqlite3_errmsg(handle)))
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int64(statement, 0))
    }

    public func pendingSyncEvents(limit: Int = 25) throws -> [SyncEnvelope] {
        lock.lock(); defer { lock.unlock() }
        guard let handle else { throw SQLiteStoreError.open("本地资料库未打开。") }
        var statement: OpaquePointer?
        let sql = "SELECT sync_events.payload FROM outbox JOIN sync_events ON sync_events.event_id=outbox.event_id WHERE outbox.state='pending' AND sync_events.workspace_id=? ORDER BY sync_events.local_order"
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw SQLiteStoreError.statement(String(cString: sqlite3_errmsg(handle)))
        }
        defer { sqlite3_finalize(statement) }
        bind(workspaceID, to: statement, at: 1)
        let boundedLimit = max(1, min(limit, 25))
        var values: [SyncEnvelope] = []
        var payloadBytes = 0
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let bytes = sqlite3_column_blob(statement, 0) else { continue }
            let count = Int(sqlite3_column_bytes(statement, 0))
            let event = try decoder.decode(SyncEnvelope.self, from: Data(bytes: bytes, count: count))
            guard event.isValid else { throw SyncApplyError.invalidEnvelope }
            guard values.count < boundedLimit else { break }
            let candidate = values + [event]
            let candidateBytes = payloadBytes + event.payload.count
            let request = DeviceSyncRequest(workspaceID: workspaceID, deviceID: deviceID, events: candidate, cursors: [])
            guard candidateBytes <= 700_000, request.isWithinLimits else {
                guard !values.isEmpty else { throw SyncApplyError.invalidEnvelope }
                break
            }
            values = candidate
            payloadBytes = candidateBytes
        }
        return values
    }

    public func acknowledgeSyncEvents(_ eventIDs: [String]) throws {
        guard !eventIDs.isEmpty else { return }
        lock.lock(); defer { lock.unlock() }
        guard handle != nil else { throw SQLiteStoreError.open("本地资料库未打开。") }
        try execute("BEGIN IMMEDIATE")
        do {
            for eventID in eventIDs where !eventID.isEmpty && eventID.count <= 100 {
                var statement: OpaquePointer?
                guard sqlite3_prepare_v2(handle, "UPDATE outbox SET state='sent' WHERE event_id=?", -1, &statement, nil) == SQLITE_OK, let statement else {
                    throw SQLiteStoreError.statement(String(cString: sqlite3_errmsg(handle)))
                }
                bind(eventID, to: statement, at: 1)
                guard sqlite3_step(statement) == SQLITE_DONE else {
                    sqlite3_finalize(statement)
                    throw SQLiteStoreError.statement(String(cString: sqlite3_errmsg(handle)))
                }
                sqlite3_finalize(statement)
            }
            try execute("COMMIT")
        } catch {
            _ = try? execute("ROLLBACK")
            throw error
        }
    }

    public func syncCursors() throws -> [SyncCursor] {
        lock.lock(); defer { lock.unlock() }
        guard let handle else { throw SQLiteStoreError.open("本地资料库未打开。") }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, "SELECT device_id,sequence FROM sync_cursors WHERE workspace_id=? ORDER BY device_id", -1, &statement, nil) == SQLITE_OK, let statement else {
            throw SQLiteStoreError.statement(String(cString: sqlite3_errmsg(handle)))
        }
        defer { sqlite3_finalize(statement) }
        bind(workspaceID, to: statement, at: 1)
        var values: [SyncCursor] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let id = sqlite3_column_text(statement, 0) else { continue }
            values.append(SyncCursor(deviceID: String(cString: id), sequence: sqlite3_column_int64(statement, 1)))
        }
        return values
    }

    public func syncEvents(after cursors: [SyncCursor], workspaceID: String, limit: Int = 50) throws -> SyncEventPage {
        lock.lock(); defer { lock.unlock() }
        guard let handle else { throw SQLiteStoreError.open("本地资料库未打开。") }
        guard workspaceID == self.workspaceID else { throw SyncApplyError.wrongWorkspace }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, "SELECT payload FROM sync_events WHERE workspace_id=? ORDER BY local_order", -1, &statement, nil) == SQLITE_OK, let statement else {
            throw SQLiteStoreError.statement(String(cString: sqlite3_errmsg(handle)))
        }
        defer { sqlite3_finalize(statement) }
        bind(workspaceID, to: statement, at: 1)
        let cursorMap = Dictionary(cursors.map { ($0.deviceID, $0.sequence) }, uniquingKeysWith: max)
        let boundedLimit = max(1, min(limit, 25))
        var events: [SyncEnvelope] = []
        var hasMore = false
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let bytes = sqlite3_column_blob(statement, 0) else { continue }
            let count = Int(sqlite3_column_bytes(statement, 0))
            let envelope = try decoder.decode(SyncEnvelope.self, from: Data(bytes: bytes, count: count))
            guard envelope.deviceSequence > (cursorMap[envelope.deviceID] ?? 0) else { continue }
            guard events.count < boundedLimit else { hasMore = true; break }
            let candidate = events + [envelope]
            let response = DeviceSyncResponse(acceptedEventIDs: [], events: candidate, conflictCount: 0, hasMore: false)
            guard try encoder.encode(response).count <= 900_000 else {
                guard !events.isEmpty else { throw SyncApplyError.invalidEnvelope }
                hasMore = true
                break
            }
            events = candidate
        }
        return SyncEventPage(events: events, hasMore: hasMore)
    }

    @discardableResult
    public func applyRemoteSyncEvents(_ events: [SyncEnvelope], workspaceID: String) throws -> SyncApplyResult {
        guard events.count <= 100, events.allSatisfy({ $0.isValid && $0.workspaceID == workspaceID }) else {
            throw SyncApplyError.invalidEnvelope
        }
        guard workspaceID == self.workspaceID else { throw SyncApplyError.wrongWorkspace }
        lock.lock(); defer { lock.unlock() }
        guard handle != nil else { throw SQLiteStoreError.open("本地资料库未打开。") }
        try execute("BEGIN IMMEDIATE")
        do {
            var accepted: [String] = []
            var conflicts = 0
            for event in events {
                if let existing = try syncEvent(eventID: event.eventID) {
                    if existing == event {
                        accepted.append(event.eventID)
                        continue
                    }
                    if event.isRedacted,
                       existing.workspaceID == event.workspaceID,
                       existing.deviceID == event.deviceID,
                       existing.deviceSequence == event.deviceSequence,
                       existing.objectID == event.objectID,
                       existing.kind == event.kind {
                        try replaceStoredSyncEnvelope(event)
                        accepted.append(event.eventID)
                        continue
                    }
                    throw SyncApplyError.conflictingEventID
                }
                let cursor = try syncCursor(workspaceID: workspaceID, deviceID: event.deviceID)
                guard event.deviceSequence == cursor + 1 else {
                    throw SyncApplyError.sequenceGap(deviceID: event.deviceID, expected: cursor + 1)
                }
                if event.isRedacted {
                    try insertSyncEnvelope(event)
                    try setSyncCursor(workspaceID: workspaceID, deviceID: event.deviceID, sequence: event.deviceSequence)
                    accepted.append(event.eventID)
                    continue
                }
                let current = try recordState(kind: event.kind, id: event.objectID)
                if event.kind == RecordKind.deletionTombstone {
                    guard let tombstone = try? decoder.decode(DeletionTombstoneRecord.self, from: event.payload),
                          tombstone.id == event.objectID,
                          RecordKind.syncableKinds.contains(tombstone.recordKind),
                          tombstone.recordKind != RecordKind.deletionTombstone,
                          !tombstone.recordID.isEmpty, tombstone.recordID.count <= 200 else {
                        throw SyncApplyError.invalidEnvelope
                    }
                    if current.payload == nil || current.revision == event.baseRevision {
                        try insert(event.payload, kind: event.kind, id: event.objectID, revision: event.revision, createdAt: event.createdAt, updatedAt: event.createdAt)
                        if event.appendsRevision {
                            try insertRevision(event.payload, kind: event.kind, objectID: event.objectID, revision: event.revision, createdAt: event.createdAt)
                        }
                    }
                    if tombstone.recordKind == RecordKind.attachment { try removeAttachmentReferences(tombstone.recordID) }
                    try eraseRecordPayloads(kind: tombstone.recordKind, id: tombstone.recordID)
                    try redactHistoricalSyncPayloads(kind: tombstone.recordKind, id: tombstone.recordID)
                } else if try activeTombstone(kind: event.kind, id: event.objectID) != nil {
                    // A forget action wins over an older write from a device that was offline.
                } else if try current.revision == event.baseRevision ||
                    (current.revision == 0 && hasRedactedPriorEvent(kind: event.kind, objectID: event.objectID, deviceID: event.deviceID, beforeSequence: event.deviceSequence)) {
                    try insert(event.payload, kind: event.kind, id: event.objectID, revision: event.revision)
                    if event.appendsRevision {
                        try insertRevision(event.payload, kind: event.kind, objectID: event.objectID, revision: event.revision)
                    }
                } else if !(current.revision == event.revision && current.payload.map { payloadsAreEquivalent($0, event.payload) } == true) {
                    let conflict = SyncConflictRecord(
                        id: UUID().uuidString,
                        eventID: event.eventID,
                        workspaceID: workspaceID,
                        objectID: event.objectID,
                        kind: event.kind,
                        localRevision: current.revision,
                        remoteRevision: event.revision,
                        localPayload: current.payload ?? Data(),
                        remotePayload: event.payload,
                        createdAt: event.createdAt
                    )
                    try insertSyncConflict(conflict)
                    conflicts += 1
                }
                try insertSyncEnvelope(event)
                try setSyncCursor(workspaceID: workspaceID, deviceID: event.deviceID, sequence: event.deviceSequence)
                if event.parentRevisionIDs.count >= 2 {
                    try clearResolvedConflicts(parentEventIDs: event.parentRevisionIDs, workspaceID: workspaceID, objectID: event.objectID)
                }
                accepted.append(event.eventID)
            }
            try execute("COMMIT")
            return SyncApplyResult(acceptedEventIDs: accepted, conflictCount: conflicts)
        } catch {
            _ = try? execute("ROLLBACK")
            throw error
        }
    }

    public func loadSyncConflicts() throws -> [SyncConflictRecord] {
        lock.lock(); defer { lock.unlock() }
        guard let handle else { throw SQLiteStoreError.open("本地资料库未打开。") }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, "SELECT id,event_id,workspace_id,object_id,kind,local_revision,remote_revision,local_payload,remote_payload,created_at FROM sync_conflicts WHERE workspace_id=? ORDER BY created_at DESC", -1, &statement, nil) == SQLITE_OK, let statement else {
            throw SQLiteStoreError.statement(String(cString: sqlite3_errmsg(handle)))
        }
        defer { sqlite3_finalize(statement) }
        bind(workspaceID, to: statement, at: 1)
        var values: [SyncConflictRecord] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let id = sqlite3_column_text(statement, 0), let eventID = sqlite3_column_text(statement, 1),
                  let workspaceID = sqlite3_column_text(statement, 2), let objectID = sqlite3_column_text(statement, 3),
                  let kind = sqlite3_column_text(statement, 4),
                  let localPayload = sqlite3_column_blob(statement, 7), let remotePayload = sqlite3_column_blob(statement, 8) else { continue }
            values.append(SyncConflictRecord(
                id: String(cString: id), eventID: String(cString: eventID), workspaceID: String(cString: workspaceID),
                objectID: String(cString: objectID), kind: String(cString: kind),
                localRevision: Int(sqlite3_column_int64(statement, 5)), remoteRevision: Int(sqlite3_column_int64(statement, 6)),
                localPayload: Data(bytes: localPayload, count: Int(sqlite3_column_bytes(statement, 7))),
                remotePayload: Data(bytes: remotePayload, count: Int(sqlite3_column_bytes(statement, 8))),
                createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 9))
            ))
        }
        return values
    }

    public func resolveSyncConflict(id: String, keepRemote: Bool) throws {
        lock.lock(); defer { lock.unlock() }
        guard handle != nil else { throw SQLiteStoreError.open("本地资料库未打开。") }
        guard let conflict = try loadSyncConflicts().first(where: { $0.id == id }) else { return }
        try execute("BEGIN IMMEDIATE")
        do {
            let current = try recordState(kind: conflict.kind, id: conflict.objectID)
            let newRevision = current.revision + 1
            let chosenPayload = keepRemote ? conflict.remotePayload : conflict.localPayload
            let revisedPayload = try updatingEmbeddedRevision(in: chosenPayload, to: newRevision)
            try insert(revisedPayload, kind: conflict.kind, id: conflict.objectID, revision: newRevision)
            try insertRevision(revisedPayload, kind: conflict.kind, objectID: conflict.objectID, revision: newRevision)
            let localParent = try latestSyncEventID(kind: conflict.kind, objectID: conflict.objectID, deviceID: deviceID)
            var parents = [localParent, conflict.eventID].compactMap { $0 }
            var seenParents = Set<String>()
            parents = parents.filter { seenParents.insert($0).inserted }
            let event = SyncEnvelope(
                workspaceID: workspaceID, deviceID: deviceID, deviceSequence: try nextDeviceSequence(),
                objectID: conflict.objectID, kind: conflict.kind, baseRevision: current.revision,
                revision: newRevision, parentRevisionIDs: Array(parents.prefix(16)), appendsRevision: true,
                payload: revisedPayload
            )
            try insertSyncEnvelope(event)
            try insertOutbox(event)
            try setSyncCursor(workspaceID: workspaceID, deviceID: deviceID, sequence: event.deviceSequence)
            try deleteSyncConflict(id: conflict.id)
            try execute("COMMIT")
        } catch {
            _ = try? execute("ROLLBACK")
            throw error
        }
    }

    private func updatingEmbeddedRevision(in payload: Data, to revision: Int) throws -> Data {
        guard var object = try JSONSerialization.jsonObject(with: payload) as? [String: Any] else { throw SQLiteStoreError.decoding }
        if object["revision"] != nil { object["revision"] = revision }
        if object["currentRevision"] != nil { object["currentRevision"] = revision }
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .fragmentsAllowed])
    }

    private func deleteSyncConflict(id: String) throws {
        guard let handle else { throw SQLiteStoreError.open("本地资料库未打开。") }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, "DELETE FROM sync_conflicts WHERE id=?", -1, &statement, nil) == SQLITE_OK, let statement else {
            throw SQLiteStoreError.statement(String(cString: sqlite3_errmsg(handle)))
        }
        defer { sqlite3_finalize(statement) }
        bind(id, to: statement, at: 1)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw SQLiteStoreError.statement(String(cString: sqlite3_errmsg(handle))) }
    }

    private func clearResolvedConflicts(parentEventIDs: [String], workspaceID: String, objectID: String) throws {
        for eventID in parentEventIDs {
            guard let handle else { throw SQLiteStoreError.open("本地资料库未打开。") }
            var statement: OpaquePointer?
            let sql = "DELETE FROM sync_conflicts WHERE workspace_id=? AND object_id=? AND event_id=?"
            guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
                throw SQLiteStoreError.statement(String(cString: sqlite3_errmsg(handle)))
            }
            bind(workspaceID, to: statement, at: 1); bind(objectID, to: statement, at: 2); bind(eventID, to: statement, at: 3)
            let result = sqlite3_step(statement)
            sqlite3_finalize(statement)
            guard result == SQLITE_DONE else { throw SQLiteStoreError.statement(String(cString: sqlite3_errmsg(handle))) }
        }
    }

    public func adoptWorkspaceID(_ sharedWorkspaceID: String) throws {
        let value = sharedWorkspaceID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.count <= 100 else { throw SyncApplyError.wrongWorkspace }
        guard value != workspaceID else { return }
        lock.lock(); defer { lock.unlock() }
        guard handle != nil else { throw SQLiteStoreError.open("本地资料库未打开。") }
        guard try syncEventsContainOnlyLocalDevice() else { throw SyncApplyError.wrongWorkspace }
        let localCursor = try syncCursor(workspaceID: workspaceID, deviceID: deviceID)
        let oldWorkspaceID = workspaceID
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, "SELECT event_id,payload FROM sync_events WHERE workspace_id=? AND device_id=? ORDER BY local_order", -1, &statement, nil) == SQLITE_OK, let statement else {
            throw SQLiteStoreError.statement(String(cString: sqlite3_errmsg(handle)))
        }
        bind(oldWorkspaceID, to: statement, at: 1); bind(deviceID, to: statement, at: 2)
        var events: [SyncEnvelope] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let bytes = sqlite3_column_blob(statement, 1) else { continue }
            events.append(try decoder.decode(SyncEnvelope.self, from: Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 1)))))
        }
        sqlite3_finalize(statement)

        try execute("BEGIN IMMEDIATE")
        do {
            try deleteSyncCursors(workspaceID: oldWorkspaceID)
            for oldEvent in events {
                let event = SyncEnvelope(
                    eventID: oldEvent.eventID, workspaceID: value, deviceID: oldEvent.deviceID,
                    deviceSequence: oldEvent.deviceSequence, objectID: oldEvent.objectID, kind: oldEvent.kind,
                    baseRevision: oldEvent.baseRevision, revision: oldEvent.revision,
                    parentRevisionIDs: oldEvent.parentRevisionIDs, appendsRevision: oldEvent.appendsRevision,
                    payload: oldEvent.payload, createdAt: oldEvent.createdAt
                )
                try updateSyncEnvelopeWorkspace(event)
                try updateOutboxPayload(eventID: event.eventID, payload: try encoder.encode(event), state: "pending")
            }
            try setMetadata("workspace_id", value: value)
            if localCursor > 0 { try setSyncCursor(workspaceID: value, deviceID: deviceID, sequence: localCursor) }
            try execute("COMMIT")
            workspaceID = value
        } catch {
            _ = try? execute("ROLLBACK")
            throw error
        }
    }

    private func deleteSyncCursors(workspaceID: String) throws {
        guard let handle else { throw SQLiteStoreError.open("本地资料库未打开。") }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, "DELETE FROM sync_cursors WHERE workspace_id=?", -1, &statement, nil) == SQLITE_OK, let statement else {
            throw SQLiteStoreError.statement(String(cString: sqlite3_errmsg(handle)))
        }
        defer { sqlite3_finalize(statement) }
        bind(workspaceID, to: statement, at: 1)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw SQLiteStoreError.statement(String(cString: sqlite3_errmsg(handle))) }
    }

    private func syncEventsContainOnlyLocalDevice() throws -> Bool {
        guard let handle else { throw SQLiteStoreError.open("本地资料库未打开。") }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, "SELECT COUNT(*) FROM sync_events WHERE workspace_id=? AND device_id<>?", -1, &statement, nil) == SQLITE_OK, let statement else {
            throw SQLiteStoreError.statement(String(cString: sqlite3_errmsg(handle)))
        }
        defer { sqlite3_finalize(statement) }
        bind(workspaceID, to: statement, at: 1); bind(deviceID, to: statement, at: 2)
        return sqlite3_step(statement) == SQLITE_ROW && sqlite3_column_int64(statement, 0) == 0
    }

    private func updateSyncEnvelopeWorkspace(_ envelope: SyncEnvelope) throws {
        guard let handle else { throw SQLiteStoreError.open("本地资料库未打开。") }
        var statement: OpaquePointer?
        let sql = "UPDATE sync_events SET workspace_id=?,payload_hash=?,payload=? WHERE event_id=?"
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw SQLiteStoreError.statement(String(cString: sqlite3_errmsg(handle)))
        }
        defer { sqlite3_finalize(statement) }
        bind(envelope.workspaceID, to: statement, at: 1); bind(envelope.payloadHash, to: statement, at: 2)
        bind(try encoder.encode(envelope), to: statement, at: 3); bind(envelope.eventID, to: statement, at: 4)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw SQLiteStoreError.statement(String(cString: sqlite3_errmsg(handle))) }
    }

    private func loadOrCreateMetadata(_ key: String) throws -> String {
        guard let handle else { throw SQLiteStoreError.open("本地资料库未打开。") }
        var select: OpaquePointer?
        guard sqlite3_prepare_v2(handle, "SELECT value FROM sync_meta WHERE key=?", -1, &select, nil) == SQLITE_OK, let select else {
            throw SQLiteStoreError.statement(String(cString: sqlite3_errmsg(handle)))
        }
        bind(key, to: select, at: 1)
        if sqlite3_step(select) == SQLITE_ROW, let value = sqlite3_column_text(select, 0) {
            let result = String(cString: value)
            sqlite3_finalize(select)
            return result
        }
        sqlite3_finalize(select)
        let value = UUID().uuidString
        try setMetadata(key, value: value)
        return value
    }

    private func metadata(_ key: String) throws -> String? {
        guard let handle else { throw SQLiteStoreError.open("本地资料库未打开。") }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, "SELECT value FROM sync_meta WHERE key=?", -1, &statement, nil) == SQLITE_OK, let statement else {
            throw SQLiteStoreError.statement(String(cString: sqlite3_errmsg(handle)))
        }
        defer { sqlite3_finalize(statement) }
        bind(key, to: statement, at: 1)
        guard sqlite3_step(statement) == SQLITE_ROW, let value = sqlite3_column_text(statement, 0) else { return nil }
        return String(cString: value)
    }

    private func setMetadata(_ key: String, value: String) throws {
        guard let handle else { throw SQLiteStoreError.open("本地资料库未打开。") }
        var statement: OpaquePointer?
        let sql = "INSERT INTO sync_meta(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value"
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw SQLiteStoreError.statement(String(cString: sqlite3_errmsg(handle)))
        }
        defer { sqlite3_finalize(statement) }
        bind(key, to: statement, at: 1); bind(value, to: statement, at: 2)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw SQLiteStoreError.statement(String(cString: sqlite3_errmsg(handle))) }
    }

    private func nextDeviceSequence() throws -> Int64 {
        let previous = Int64(try metadata("next_device_sequence") ?? "0") ?? 0
        let next = previous + 1
        try setMetadata("next_device_sequence", value: String(next))
        return next
    }

    /// Persists a record and its sync event inside the caller's existing transaction.
    private func persist(_ write: SQLiteStoreWrite) throws {
        if write.kind != RecordKind.deletionTombstone,
           try activeTombstone(kind: write.kind, id: write.id) != nil {
            throw SQLiteStoreError.statement("这条资料已被彻底忘记，不能被旧写入恢复。")
        }
        let baseRevision = try currentRevision(kind: write.kind, id: write.id)
        let revision = max(write.revision, baseRevision + 1)
        let parentRevisionIDs = try latestSyncEventID(kind: write.kind, objectID: write.id).map { [$0] } ?? []
        try insert(write.payload, kind: write.kind, id: write.id, revision: revision)
        if write.appendRevision {
            try insertRevision(write.payload, kind: write.kind, objectID: write.id, revision: revision)
        }
        let envelope = SyncEnvelope(
            workspaceID: workspaceID,
            deviceID: deviceID,
            deviceSequence: try nextDeviceSequence(),
            objectID: write.id,
            kind: write.kind,
            baseRevision: baseRevision,
            revision: revision,
            parentRevisionIDs: parentRevisionIDs,
            appendsRevision: write.appendRevision,
            payload: write.payload
        )
        try insertSyncEnvelope(envelope)
        try insertOutbox(envelope)
        try setSyncCursor(workspaceID: workspaceID, deviceID: deviceID, sequence: envelope.deviceSequence)
    }

    private func storedRecord<T: Decodable>(_ type: T.Type, kind: String, id: String) throws -> T? {
        guard let payload = try recordState(kind: kind, id: id).payload else { return nil }
        do { return try decoder.decode(type, from: payload) }
        catch { throw SQLiteStoreError.decoding }
    }

    private static func checkpointsMatch(_ lhs: TaskCheckpointRecord, _ rhs: TaskCheckpointRecord) -> Bool {
        lhs.id == rhs.id && lhs.taskID == rhs.taskID && lhs.attemptID == rhs.attemptID &&
        lhs.stepID == rhs.stepID && lhs.idempotencyKey == rhs.idempotencyKey && lhs.runEpoch == rhs.runEpoch &&
        lhs.ownerDeviceID == rhs.ownerDeviceID && lhs.sequence == rhs.sequence && lhs.inputRevision == rhs.inputRevision &&
        lhs.effectClass == rhs.effectClass && lhs.status == rhs.status && lhs.resultSummary == rhs.resultSummary &&
        lhs.outputRefs == rhs.outputRefs
    }

    private func currentRevision(kind: String, id: String) throws -> Int {
        guard let handle else { throw SQLiteStoreError.open("本地资料库未打开。") }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, "SELECT revision FROM records WHERE kind=? AND id=?", -1, &statement, nil) == SQLITE_OK, let statement else {
            throw SQLiteStoreError.statement(String(cString: sqlite3_errmsg(handle)))
        }
        defer { sqlite3_finalize(statement) }
        bind(kind, to: statement, at: 1); bind(id, to: statement, at: 2)
        return sqlite3_step(statement) == SQLITE_ROW ? Int(sqlite3_column_int64(statement, 0)) : 0
    }

    private func recordState(kind: String, id: String) throws -> (revision: Int, payload: Data?) {
        guard let handle else { throw SQLiteStoreError.open("本地资料库未打开。") }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, "SELECT revision,payload FROM records WHERE kind=? AND id=?", -1, &statement, nil) == SQLITE_OK, let statement else {
            throw SQLiteStoreError.statement(String(cString: sqlite3_errmsg(handle)))
        }
        defer { sqlite3_finalize(statement) }
        bind(kind, to: statement, at: 1); bind(id, to: statement, at: 2)
        guard sqlite3_step(statement) == SQLITE_ROW else { return (0, nil) }
        guard let payload = sqlite3_column_blob(statement, 1) else { return (Int(sqlite3_column_int64(statement, 0)), nil) }
        return (Int(sqlite3_column_int64(statement, 0)), Data(bytes: payload, count: Int(sqlite3_column_bytes(statement, 1))))
    }

    private func activeTombstone(kind: String, id: String) throws -> DeletionTombstoneRecord? {
        let tombstoneID = DeletionTombstoneRecord.stableID(kind: kind, id: id)
        guard let payload = try recordState(kind: RecordKind.deletionTombstone, id: tombstoneID).payload else { return nil }
        let tombstone = try decoder.decode(DeletionTombstoneRecord.self, from: payload)
        guard tombstone.recordKind == kind, tombstone.recordID == id, tombstone.id == tombstoneID else {
            throw SQLiteStoreError.decoding
        }
        return tombstone
    }

    private func eraseRecordPayloads(kind: String, id: String) throws {
        guard let handle else { throw SQLiteStoreError.open("本地数据库未打开。") }
        for sql in [
            "DELETE FROM records WHERE kind=? AND id=?",
            "DELETE FROM revisions WHERE kind=? AND object_id=?",
            "DELETE FROM sync_conflicts WHERE workspace_id=? AND kind=? AND object_id=?"
        ] {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
                throw SQLiteStoreError.statement(String(cString: sqlite3_errmsg(handle)))
            }
            if sql.contains("sync_conflicts") {
                bind(workspaceID, to: statement, at: 1); bind(kind, to: statement, at: 2); bind(id, to: statement, at: 3)
            } else {
                bind(kind, to: statement, at: 1); bind(id, to: statement, at: 2)
            }
            let result = sqlite3_step(statement)
            sqlite3_finalize(statement)
            guard result == SQLITE_DONE else { throw SQLiteStoreError.statement(String(cString: sqlite3_errmsg(handle))) }
        }
        if kind == RecordKind.message {
            try deleteMessageSearchEntry(id: id)
        }
    }

    private func removeAttachmentReferences(_ attachmentID: String) throws {
        let messages = try load(MessageRecord.self, kind: RecordKind.message)
        for var message in messages where (message.attachmentIDs ?? []).contains(attachmentID) {
            let remaining = (message.attachmentIDs ?? []).filter { $0 != attachmentID }
            message.attachmentIDs = remaining.isEmpty ? nil : remaining
            let revision = try currentRevision(kind: RecordKind.message, id: message.id) + 1
            try persist(prepareWrite(message, kind: RecordKind.message, id: message.id, revision: revision, appendRevision: true))
        }
    }

    private func eraseConflictPayloads(kind: String, id: String) throws {
        guard let handle else { throw SQLiteStoreError.open("本地数据库未打开。") }
        var statement: OpaquePointer?
        let sql = "DELETE FROM sync_conflicts WHERE workspace_id=? AND kind=? AND object_id=?"
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw SQLiteStoreError.statement(String(cString: sqlite3_errmsg(handle)))
        }
        bind(workspaceID, to: statement, at: 1); bind(kind, to: statement, at: 2); bind(id, to: statement, at: 3)
        let result = sqlite3_step(statement)
        sqlite3_finalize(statement)
        guard result == SQLITE_DONE else { throw SQLiteStoreError.statement(String(cString: sqlite3_errmsg(handle))) }
    }

    private func redactHistoricalSyncPayloads(kind: String, id: String, keepingLatest: Bool = false) throws {
        guard let handle else { throw SQLiteStoreError.open("本地数据库未打开。") }
        var select: OpaquePointer?
        let sql = "SELECT payload FROM sync_events WHERE workspace_id=? AND kind=? AND object_id=? ORDER BY local_order"
        guard sqlite3_prepare_v2(handle, sql, -1, &select, nil) == SQLITE_OK, let select else {
            throw SQLiteStoreError.statement(String(cString: sqlite3_errmsg(handle)))
        }
        bind(workspaceID, to: select, at: 1); bind(kind, to: select, at: 2); bind(id, to: select, at: 3)
        var envelopes = [SyncEnvelope]()
        while sqlite3_step(select) == SQLITE_ROW {
            guard let bytes = sqlite3_column_blob(select, 0) else { continue }
            let count = Int(sqlite3_column_bytes(select, 0))
            envelopes.append(try decoder.decode(SyncEnvelope.self, from: Data(bytes: bytes, count: count)))
        }
        sqlite3_finalize(select)
        let latestID = keepingLatest ? envelopes.last?.eventID : nil
        for envelope in envelopes where !envelope.isRedacted && envelope.eventID != latestID {
            try replaceStoredSyncEnvelope(envelope.redactedCopy())
        }
    }

    private func hasRedactedPriorEvent(kind: String, objectID: String, deviceID: String, beforeSequence: Int64) throws -> Bool {
        guard let handle else { throw SQLiteStoreError.open("本地数据库未打开。") }
        var statement: OpaquePointer?
        let sql = "SELECT payload FROM sync_events WHERE workspace_id=? AND kind=? AND object_id=? AND device_id=? AND device_sequence<? ORDER BY device_sequence DESC"
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw SQLiteStoreError.statement(String(cString: sqlite3_errmsg(handle)))
        }
        bind(workspaceID, to: statement, at: 1); bind(kind, to: statement, at: 2)
        bind(objectID, to: statement, at: 3); bind(deviceID, to: statement, at: 4)
        sqlite3_bind_int64(statement, 5, sqlite3_int64(beforeSequence))
        var found = false
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let bytes = sqlite3_column_blob(statement, 0) else { continue }
            let count = Int(sqlite3_column_bytes(statement, 0))
            if try decoder.decode(SyncEnvelope.self, from: Data(bytes: bytes, count: count)).isRedacted {
                found = true
                break
            }
        }
        sqlite3_finalize(statement)
        return found
    }

    private func replaceStoredSyncEnvelope(_ envelope: SyncEnvelope) throws {
        guard let handle else { throw SQLiteStoreError.open("本地数据库未打开。") }
        let encoded = try encoder.encode(envelope)
        var eventStatement: OpaquePointer?
        let eventSQL = "UPDATE sync_events SET payload_hash=?,payload=? WHERE event_id=?"
        guard sqlite3_prepare_v2(handle, eventSQL, -1, &eventStatement, nil) == SQLITE_OK, let eventStatement else {
            throw SQLiteStoreError.statement(String(cString: sqlite3_errmsg(handle)))
        }
        bind(envelope.payloadHash, to: eventStatement, at: 1); bind(encoded, to: eventStatement, at: 2); bind(envelope.eventID, to: eventStatement, at: 3)
        let eventResult = sqlite3_step(eventStatement)
        sqlite3_finalize(eventStatement)
        guard eventResult == SQLITE_DONE else { throw SQLiteStoreError.statement(String(cString: sqlite3_errmsg(handle))) }

        var outboxStatement: OpaquePointer?
        let outboxSQL = "UPDATE outbox SET payload=? WHERE event_id=?"
        guard sqlite3_prepare_v2(handle, outboxSQL, -1, &outboxStatement, nil) == SQLITE_OK, let outboxStatement else {
            throw SQLiteStoreError.statement(String(cString: sqlite3_errmsg(handle)))
        }
        bind(encoded, to: outboxStatement, at: 1); bind(envelope.eventID, to: outboxStatement, at: 2)
        let outboxResult = sqlite3_step(outboxStatement)
        sqlite3_finalize(outboxStatement)
        guard outboxResult == SQLITE_DONE else { throw SQLiteStoreError.statement(String(cString: sqlite3_errmsg(handle))) }
    }

    private func latestSyncEventID(kind: String, objectID: String) throws -> String? {
        guard let handle else { throw SQLiteStoreError.open("本地资料库未打开。") }
        var statement: OpaquePointer?
        let sql = "SELECT event_id FROM sync_events WHERE workspace_id=? AND kind=? AND object_id=? ORDER BY local_order DESC LIMIT 1"
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw SQLiteStoreError.statement(String(cString: sqlite3_errmsg(handle)))
        }
        defer { sqlite3_finalize(statement) }
        bind(workspaceID, to: statement, at: 1)
        bind(kind, to: statement, at: 2); bind(objectID, to: statement, at: 3)
        guard sqlite3_step(statement) == SQLITE_ROW, let value = sqlite3_column_text(statement, 0) else { return nil }
        return String(cString: value)
    }

    private func latestSyncEventID(kind: String, objectID: String, deviceID: String) throws -> String? {
        guard let handle else { throw SQLiteStoreError.open("本地数据库未打开。") }
        var statement: OpaquePointer?
        let sql = "SELECT event_id FROM sync_events WHERE workspace_id=? AND device_id=? AND kind=? AND object_id=? ORDER BY device_sequence DESC LIMIT 1"
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw SQLiteStoreError.statement(String(cString: sqlite3_errmsg(handle)))
        }
        defer { sqlite3_finalize(statement) }
        bind(workspaceID, to: statement, at: 1); bind(deviceID, to: statement, at: 2)
        bind(kind, to: statement, at: 3); bind(objectID, to: statement, at: 4)
        guard sqlite3_step(statement) == SQLITE_ROW, let value = sqlite3_column_text(statement, 0) else { return nil }
        return String(cString: value)
    }

    private func syncCursor(workspaceID: String, deviceID: String) throws -> Int64 {
        guard let handle else { throw SQLiteStoreError.open("本地资料库未打开。") }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, "SELECT sequence FROM sync_cursors WHERE workspace_id=? AND device_id=?", -1, &statement, nil) == SQLITE_OK, let statement else {
            throw SQLiteStoreError.statement(String(cString: sqlite3_errmsg(handle)))
        }
        defer { sqlite3_finalize(statement) }
        bind(workspaceID, to: statement, at: 1); bind(deviceID, to: statement, at: 2)
        return sqlite3_step(statement) == SQLITE_ROW ? sqlite3_column_int64(statement, 0) : 0
    }

    private func setSyncCursor(workspaceID: String, deviceID: String, sequence: Int64) throws {
        guard let handle else { throw SQLiteStoreError.open("本地资料库未打开。") }
        var statement: OpaquePointer?
        let sql = "INSERT INTO sync_cursors(workspace_id,device_id,sequence) VALUES(?,?,?) ON CONFLICT(workspace_id,device_id) DO UPDATE SET sequence=MAX(sync_cursors.sequence,excluded.sequence)"
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw SQLiteStoreError.statement(String(cString: sqlite3_errmsg(handle)))
        }
        defer { sqlite3_finalize(statement) }
        bind(workspaceID, to: statement, at: 1); bind(deviceID, to: statement, at: 2); sqlite3_bind_int64(statement, 3, sequence)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw SQLiteStoreError.statement(String(cString: sqlite3_errmsg(handle))) }
    }

    private func syncEvent(eventID: String) throws -> SyncEnvelope? {
        guard let handle else { throw SQLiteStoreError.open("本地资料库未打开。") }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, "SELECT payload FROM sync_events WHERE event_id=?", -1, &statement, nil) == SQLITE_OK, let statement else {
            throw SQLiteStoreError.statement(String(cString: sqlite3_errmsg(handle)))
        }
        defer { sqlite3_finalize(statement) }
        bind(eventID, to: statement, at: 1)
        guard sqlite3_step(statement) == SQLITE_ROW, let bytes = sqlite3_column_blob(statement, 0) else { return nil }
        return try decoder.decode(SyncEnvelope.self, from: Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 0))))
    }

    private func insertSyncEnvelope(_ envelope: SyncEnvelope) throws {
        guard let handle else { throw SQLiteStoreError.open("本地资料库未打开。") }
        var statement: OpaquePointer?
        let sql = "INSERT INTO sync_events(event_id,workspace_id,device_id,device_sequence,object_id,kind,base_revision,revision,parent_revision_ids,appends_revision,payload_hash,payload,created_at) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)"
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw SQLiteStoreError.statement(String(cString: sqlite3_errmsg(handle)))
        }
        defer { sqlite3_finalize(statement) }
        bind(envelope.eventID, to: statement, at: 1); bind(envelope.workspaceID, to: statement, at: 2)
        bind(envelope.deviceID, to: statement, at: 3); sqlite3_bind_int64(statement, 4, envelope.deviceSequence)
        bind(envelope.objectID, to: statement, at: 5); bind(envelope.kind, to: statement, at: 6)
        sqlite3_bind_int64(statement, 7, sqlite3_int64(envelope.baseRevision)); sqlite3_bind_int64(statement, 8, sqlite3_int64(envelope.revision))
        bind(try encoder.encode(envelope.parentRevisionIDs), to: statement, at: 9)
        sqlite3_bind_int(statement, 10, envelope.appendsRevision ? 1 : 0); bind(envelope.payloadHash, to: statement, at: 11)
        bind(try encoder.encode(envelope), to: statement, at: 12); sqlite3_bind_double(statement, 13, envelope.createdAt.timeIntervalSince1970)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw SQLiteStoreError.statement(String(cString: sqlite3_errmsg(handle))) }
    }

    private func insertSyncConflict(_ conflict: SyncConflictRecord) throws {
        guard let handle else { throw SQLiteStoreError.open("本地资料库未打开。") }
        var statement: OpaquePointer?
        let sql = "INSERT INTO sync_conflicts(id,event_id,workspace_id,object_id,kind,local_revision,remote_revision,local_payload,remote_payload,created_at) VALUES(?,?,?,?,?,?,?,?,?,?)"
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw SQLiteStoreError.statement(String(cString: sqlite3_errmsg(handle)))
        }
        defer { sqlite3_finalize(statement) }
        bind(conflict.id, to: statement, at: 1); bind(conflict.eventID, to: statement, at: 2); bind(conflict.workspaceID, to: statement, at: 3)
        bind(conflict.objectID, to: statement, at: 4); bind(conflict.kind, to: statement, at: 5)
        sqlite3_bind_int64(statement, 6, sqlite3_int64(conflict.localRevision)); sqlite3_bind_int64(statement, 7, sqlite3_int64(conflict.remoteRevision))
        bind(conflict.localPayload, to: statement, at: 8); bind(conflict.remotePayload, to: statement, at: 9)
        sqlite3_bind_double(statement, 10, conflict.createdAt.timeIntervalSince1970)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw SQLiteStoreError.statement(String(cString: sqlite3_errmsg(handle))) }
    }

    private func execute(_ sql: String) throws {
        guard let handle else { throw SQLiteStoreError.open("本地数据库未打开。") }
        var errorPointer: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(handle, sql, nil, nil, &errorPointer) == SQLITE_OK else {
            let message = errorPointer.map { String(cString: $0) } ?? String(cString: sqlite3_errmsg(handle))
            sqlite3_free(errorPointer)
            throw SQLiteStoreError.statement(message)
        }
    }

    private func rebuildMessageSearchIndex() throws {
        guard let handle else { throw SQLiteStoreError.open("本地数据库未打开。") }
        try execute("DELETE FROM message_search")
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, "SELECT payload FROM records WHERE kind='message'", -1, &statement, nil) == SQLITE_OK, let statement else {
            throw SQLiteStoreError.statement(String(cString: sqlite3_errmsg(handle)))
        }
        defer { sqlite3_finalize(statement) }
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let bytes = sqlite3_column_blob(statement, 0) else { continue }
            let data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 0)))
            do { try indexMessageSearchEntry(try decoder.decode(MessageRecord.self, from: data)) }
            catch { throw SQLiteStoreError.decoding }
        }
    }

    private func indexMessageSearchEntry(_ message: MessageRecord) throws {
        try deleteMessageSearchEntry(id: message.id)
        guard let handle else { throw SQLiteStoreError.open("本地数据库未打开。") }
        let indexText = String(message.content.prefix(20_000))
        let mayIndex = !MemoryPrivacyPolicy.isSensitive(message.content) || MemoryPrivacyPolicy.explicitlyRequestsRetention(message.content)
        let terms = mayIndex ? PromptContextBuilder.keywords(indexText).sorted().joined(separator: " ") : ""
        var statement: OpaquePointer?
        let sql = "INSERT INTO message_search(message_id,conversation_id,role,imported_from,created_at,terms) VALUES(?,?,?,?,?,?)"
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw SQLiteStoreError.statement(String(cString: sqlite3_errmsg(handle)))
        }
        defer { sqlite3_finalize(statement) }
        bind(message.id, to: statement, at: 1)
        bind(message.conversationID, to: statement, at: 2)
        bind(message.role.rawValue, to: statement, at: 3)
        bind(message.importedFrom ?? "", to: statement, at: 4)
        bind(String(message.createdAt.timeIntervalSince1970), to: statement, at: 5)
        bind(terms, to: statement, at: 6)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw SQLiteStoreError.statement(String(cString: sqlite3_errmsg(handle))) }
    }

    private func deleteMessageSearchEntry(id: String) throws {
        guard let handle else { throw SQLiteStoreError.open("本地数据库未打开。") }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, "DELETE FROM message_search WHERE message_id=?", -1, &statement, nil) == SQLITE_OK, let statement else {
            throw SQLiteStoreError.statement(String(cString: sqlite3_errmsg(handle)))
        }
        defer { sqlite3_finalize(statement) }
        bind(id, to: statement, at: 1)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw SQLiteStoreError.statement(String(cString: sqlite3_errmsg(handle))) }
    }

    private func insert(_ payload: Data, kind: String, id: String, revision: Int, createdAt: Date? = nil, updatedAt: Date? = nil) throws {
        guard let handle else { throw SQLiteStoreError.open("本地数据库未打开。") }
        var statement: OpaquePointer?
        let sql = "INSERT INTO records(kind,id,revision,payload,created_at,updated_at) VALUES(?,?,?,?,COALESCE((SELECT created_at FROM records WHERE kind=? AND id=?),?),?) ON CONFLICT(kind,id) DO UPDATE SET revision=excluded.revision,payload=excluded.payload,updated_at=excluded.updated_at"
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw SQLiteStoreError.statement(String(cString: sqlite3_errmsg(handle)))
        }
        defer { sqlite3_finalize(statement) }
        let created = createdAt?.timeIntervalSince1970 ?? Date.now.timeIntervalSince1970
        let updated = updatedAt?.timeIntervalSince1970 ?? Date.now.timeIntervalSince1970
        bind(kind, to: statement, at: 1); bind(id, to: statement, at: 2)
        sqlite3_bind_int64(statement, 3, sqlite3_int64(revision)); bind(payload, to: statement, at: 4)
        bind(kind, to: statement, at: 5); bind(id, to: statement, at: 6)
        sqlite3_bind_double(statement, 7, created); sqlite3_bind_double(statement, 8, updated)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw SQLiteStoreError.statement(String(cString: sqlite3_errmsg(handle))) }
        if kind == RecordKind.message {
            do { try indexMessageSearchEntry(decoder.decode(MessageRecord.self, from: payload)) }
            catch { throw SQLiteStoreError.decoding }
        }
    }

    private func insertRevision(_ payload: Data, kind: String, objectID: String, revision: Int, createdAt: Date = .now) throws {
        guard let handle else { throw SQLiteStoreError.open("本地数据库未打开。") }
        var statement: OpaquePointer?
        let sql = "INSERT INTO revisions(id,kind,object_id,revision,payload,created_at) VALUES(?,?,?,?,?,?)"
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw SQLiteStoreError.statement(String(cString: sqlite3_errmsg(handle)))
        }
        defer { sqlite3_finalize(statement) }
        bind(UUID().uuidString, to: statement, at: 1); bind(kind, to: statement, at: 2); bind(objectID, to: statement, at: 3)
        sqlite3_bind_int64(statement, 4, sqlite3_int64(revision)); bind(payload, to: statement, at: 5)
        sqlite3_bind_double(statement, 6, createdAt.timeIntervalSince1970)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw SQLiteStoreError.statement(String(cString: sqlite3_errmsg(handle))) }
    }

    private func insertRevisionIfMissing(_ payload: Data, kind: String, objectID: String, revision: Int, createdAt: Date) throws {
        guard let handle else { throw SQLiteStoreError.open("本地数据库未打开。") }
        let exists = try { () -> Bool in
            var statement: OpaquePointer?
            let sql = "SELECT payload FROM revisions WHERE kind=? AND object_id=? AND revision=?"
            guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
                throw SQLiteStoreError.statement(String(cString: sqlite3_errmsg(handle)))
            }
            defer { sqlite3_finalize(statement) }
            self.bind(kind, to: statement, at: 1); self.bind(objectID, to: statement, at: 2)
            sqlite3_bind_int64(statement, 3, sqlite3_int64(revision))
            while true {
                let result = sqlite3_step(statement)
                if result == SQLITE_DONE { return false }
                guard result == SQLITE_ROW else { throw SQLiteStoreError.statement(String(cString: sqlite3_errmsg(handle))) }
                guard let existingPayload = sqlite3_column_blob(statement, 0) else { continue }
                let existing = Data(bytes: existingPayload, count: Int(sqlite3_column_bytes(statement, 0)))
                if self.payloadsAreEquivalent(existing, payload) { return true }
            }
        }()
        if !exists { try insertRevision(payload, kind: kind, objectID: objectID, revision: revision, createdAt: createdAt) }
    }

    private func payloadsAreEquivalent(_ left: Data, _ right: Data) -> Bool {
        if left == right { return true }
        guard let canonicalLeft = try? WorkspacePortableArchive.canonicalPayload(left),
              let canonicalRight = try? WorkspacePortableArchive.canonicalPayload(right) else { return false }
        return canonicalLeft == canonicalRight
    }

    private func removeEquivalentSyncConflicts() throws -> Set<String> {
        guard let handle else { throw SQLiteStoreError.open("本地资料库未打开。") }
        let duplicateIDs = try { () throws -> [String] in
            var statement: OpaquePointer?
            let sql = "SELECT id,local_payload,remote_payload FROM sync_conflicts WHERE workspace_id=?"
            guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
                throw SQLiteStoreError.statement(String(cString: sqlite3_errmsg(handle)))
            }
            defer { sqlite3_finalize(statement) }
            bind(workspaceID, to: statement, at: 1)
            var ids: [String] = []
            while true {
                switch sqlite3_step(statement) {
                case SQLITE_ROW:
                    guard let id = sqlite3_column_text(statement, 0),
                          let localBlob = sqlite3_column_blob(statement, 1),
                          let remoteBlob = sqlite3_column_blob(statement, 2) else { continue }
                    let local = Data(bytes: localBlob, count: Int(sqlite3_column_bytes(statement, 1)))
                    let remote = Data(bytes: remoteBlob, count: Int(sqlite3_column_bytes(statement, 2)))
                    if payloadsAreEquivalent(local, remote) { ids.append(String(cString: id)) }
                case SQLITE_DONE:
                    return ids
                default:
                    throw SQLiteStoreError.statement(String(cString: sqlite3_errmsg(handle)))
                }
            }
        }()
        guard !duplicateIDs.isEmpty else { return [] }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, "DELETE FROM sync_conflicts WHERE id=?", -1, &statement, nil) == SQLITE_OK, let statement else {
            throw SQLiteStoreError.statement(String(cString: sqlite3_errmsg(handle)))
        }
        defer { sqlite3_finalize(statement) }
        for id in duplicateIDs {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
            bind(id, to: statement, at: 1)
            guard sqlite3_step(statement) == SQLITE_DONE else { throw SQLiteStoreError.statement(String(cString: sqlite3_errmsg(handle))) }
        }
        return Set(duplicateIDs)
    }

    private func removeEquivalentDuplicateRevisions() throws -> Set<String> {
        guard let handle else { throw SQLiteStoreError.open("本地资料库未打开。") }
        let duplicateIDs = try { () throws -> [String] in
            var statement: OpaquePointer?
            let sql = "SELECT id,kind,object_id,revision,payload FROM revisions ORDER BY kind,object_id,revision,created_at,id"
            guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
                throw SQLiteStoreError.statement(String(cString: sqlite3_errmsg(handle)))
            }
            defer { sqlite3_finalize(statement) }
            var previousKind: String?
            var previousObjectID: String?
            var previousRevision: Int?
            var seenPayloads = Set<Data>()
            var ids: [String] = []
            while true {
                switch sqlite3_step(statement) {
                case SQLITE_ROW:
                    guard let id = sqlite3_column_text(statement, 0),
                          let kind = sqlite3_column_text(statement, 1),
                          let objectID = sqlite3_column_text(statement, 2),
                          let payload = sqlite3_column_blob(statement, 4) else { continue }
                    let kindValue = String(cString: kind)
                    let objectIDValue = String(cString: objectID)
                    let revisionValue = Int(sqlite3_column_int64(statement, 3))
                    if previousKind != kindValue || previousObjectID != objectIDValue || previousRevision != revisionValue {
                        previousKind = kindValue
                        previousObjectID = objectIDValue
                        previousRevision = revisionValue
                        seenPayloads.removeAll(keepingCapacity: true)
                    }
                    let data = Data(bytes: payload, count: Int(sqlite3_column_bytes(statement, 4)))
                    let canonical = (try? WorkspacePortableArchive.canonicalPayload(data)) ?? data
                    if !seenPayloads.insert(canonical).inserted { ids.append(String(cString: id)) }
                case SQLITE_DONE:
                    return ids
                default:
                    throw SQLiteStoreError.statement(String(cString: sqlite3_errmsg(handle)))
                }
            }
        }()
        guard !duplicateIDs.isEmpty else { return [] }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, "DELETE FROM revisions WHERE id=?", -1, &statement, nil) == SQLITE_OK, let statement else {
            throw SQLiteStoreError.statement(String(cString: sqlite3_errmsg(handle)))
        }
        defer { sqlite3_finalize(statement) }
        for id in duplicateIDs {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
            bind(id, to: statement, at: 1)
            guard sqlite3_step(statement) == SQLITE_DONE else { throw SQLiteStoreError.statement(String(cString: sqlite3_errmsg(handle))) }
        }
        return Set(duplicateIDs)
    }

    private func documentsAreEquivalent(_ left: Data, _ right: Data) -> Bool {
        guard let lhs = try? decoder.decode(WorkspaceDocument.self, from: left),
              let rhs = try? decoder.decode(WorkspaceDocument.self, from: right) else { return false }
        return lhs.path == rhs.path && lhs.title == rhs.title && lhs.content == rhs.content
    }

    private func hasImportedArchive(_ exportID: String) throws -> Bool {
        guard let handle else { throw SQLiteStoreError.open("本地数据库未打开。") }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, "SELECT 1 FROM imported_archives WHERE export_id=?", -1, &statement, nil) == SQLITE_OK, let statement else {
            throw SQLiteStoreError.statement(String(cString: sqlite3_errmsg(handle)))
        }
        defer { sqlite3_finalize(statement) }
        bind(exportID, to: statement, at: 1)
        return sqlite3_step(statement) == SQLITE_ROW
    }

    private func hasEquivalentConflict(_ conflict: SyncConflictRecord) throws -> Bool {
        guard let handle else { throw SQLiteStoreError.open("本地数据库未打开。") }
        var statement: OpaquePointer?
        let sql = "SELECT local_payload,remote_payload FROM sync_conflicts WHERE workspace_id=? AND kind=? AND object_id=?"
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw SQLiteStoreError.statement(String(cString: sqlite3_errmsg(handle)))
        }
        defer { sqlite3_finalize(statement) }
        bind(conflict.workspaceID, to: statement, at: 1); bind(conflict.kind, to: statement, at: 2)
        bind(conflict.objectID, to: statement, at: 3)
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW:
                guard let localBlob = sqlite3_column_blob(statement, 0),
                      let remoteBlob = sqlite3_column_blob(statement, 1) else { continue }
                let local = Data(bytes: localBlob, count: Int(sqlite3_column_bytes(statement, 0)))
                let remote = Data(bytes: remoteBlob, count: Int(sqlite3_column_bytes(statement, 1)))
                if (payloadsAreEquivalent(local, conflict.localPayload) && payloadsAreEquivalent(remote, conflict.remotePayload)) ||
                    (payloadsAreEquivalent(local, conflict.remotePayload) && payloadsAreEquivalent(remote, conflict.localPayload)) {
                    return true
                }
            case SQLITE_DONE:
                return false
            default:
                throw SQLiteStoreError.statement(String(cString: sqlite3_errmsg(handle)))
            }
        }
    }

    private func registerImportedArchive(_ exportID: String) throws {
        guard let handle else { throw SQLiteStoreError.open("本地数据库未打开。") }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, "INSERT INTO imported_archives(export_id,imported_at) VALUES(?,?)", -1, &statement, nil) == SQLITE_OK, let statement else {
            throw SQLiteStoreError.statement(String(cString: sqlite3_errmsg(handle)))
        }
        defer { sqlite3_finalize(statement) }
        bind(exportID, to: statement, at: 1); sqlite3_bind_double(statement, 2, Date.now.timeIntervalSince1970)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw SQLiteStoreError.statement(String(cString: sqlite3_errmsg(handle))) }
    }

    private func updateOutboxPayload(eventID: String, payload: Data, state: String) throws {
        guard let handle else { throw SQLiteStoreError.open("本地资料库未打开。") }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, "UPDATE outbox SET payload=?,state=? WHERE event_id=?", -1, &statement, nil) == SQLITE_OK, let statement else {
            throw SQLiteStoreError.statement(String(cString: sqlite3_errmsg(handle)))
        }
        defer { sqlite3_finalize(statement) }
        bind(payload, to: statement, at: 1); bind(state, to: statement, at: 2); bind(eventID, to: statement, at: 3)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw SQLiteStoreError.statement(String(cString: sqlite3_errmsg(handle))) }
    }

    private func updateRecordRevision(kind: String, id: String, revision: Int) throws {
        guard let handle else { throw SQLiteStoreError.open("本地资料库未打开。") }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, "UPDATE records SET revision=MAX(revision,?) WHERE kind=? AND id=?", -1, &statement, nil) == SQLITE_OK, let statement else {
            throw SQLiteStoreError.statement(String(cString: sqlite3_errmsg(handle)))
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, sqlite3_int64(revision)); bind(kind, to: statement, at: 2); bind(id, to: statement, at: 3)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw SQLiteStoreError.statement(String(cString: sqlite3_errmsg(handle))) }
    }

    private func migrateLegacyOutboxEvents() throws {
        guard let handle else { throw SQLiteStoreError.open("本地资料库未打开。") }
        var statement: OpaquePointer?
        let sql = "SELECT event_id,kind,object_id,payload,created_at FROM outbox WHERE event_id NOT IN (SELECT event_id FROM sync_events) ORDER BY rowid"
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw SQLiteStoreError.statement(String(cString: sqlite3_errmsg(handle)))
        }
        try execute("BEGIN IMMEDIATE")
        do {
            var revisionsByObject: [String: Int] = [:]
            var latestByObject: [String: Int] = [:]
            while sqlite3_step(statement) == SQLITE_ROW {
                guard let eventID = sqlite3_column_text(statement, 0), let kind = sqlite3_column_text(statement, 1),
                      let objectID = sqlite3_column_text(statement, 2), let payload = sqlite3_column_blob(statement, 3) else { continue }
                let kindValue = String(cString: kind)
                let objectIDValue = String(cString: objectID)
                let key = "\(kindValue)\u{0}\(objectIDValue)"
                let baseRevision = revisionsByObject[key] ?? 0
                let revision = baseRevision + 1
                revisionsByObject[key] = revision
                latestByObject[key] = revision
                let envelope = SyncEnvelope(
                    eventID: String(cString: eventID), workspaceID: workspaceID, deviceID: deviceID,
                    deviceSequence: try nextDeviceSequence(), objectID: objectIDValue, kind: kindValue,
                    baseRevision: baseRevision, revision: revision, appendsRevision: false,
                    payload: Data(bytes: payload, count: Int(sqlite3_column_bytes(statement, 3))),
                    createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 4))
                )
                try insertSyncEnvelope(envelope)
                try updateOutboxPayload(eventID: envelope.eventID, payload: try encoder.encode(envelope), state: "pending")
                try setSyncCursor(workspaceID: workspaceID, deviceID: deviceID, sequence: envelope.deviceSequence)
            }
            sqlite3_finalize(statement)
            for (key, revision) in latestByObject {
                let parts = key.components(separatedBy: "\u{0}")
                guard parts.count == 2 else { continue }
                try updateRecordRevision(kind: parts[0], id: parts[1], revision: revision)
            }
            try execute("COMMIT")
        } catch {
            sqlite3_finalize(statement)
            _ = try? execute("ROLLBACK")
            throw error
        }
    }

    private func insertOutbox(_ envelope: SyncEnvelope) throws {
        guard let handle else { throw SQLiteStoreError.open("本地数据库未打开。") }
        var statement: OpaquePointer?
        let sql = "INSERT INTO outbox(event_id,kind,object_id,revision,payload,created_at,state) VALUES(?,?,?,?,?,?, 'pending')"
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw SQLiteStoreError.statement(String(cString: sqlite3_errmsg(handle)))
        }
        defer { sqlite3_finalize(statement) }
        bind(envelope.eventID, to: statement, at: 1); bind(envelope.kind, to: statement, at: 2); bind(envelope.objectID, to: statement, at: 3)
        sqlite3_bind_int64(statement, 4, sqlite3_int64(envelope.revision)); bind(try encoder.encode(envelope), to: statement, at: 5)
        sqlite3_bind_double(statement, 6, envelope.createdAt.timeIntervalSince1970)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw SQLiteStoreError.statement(String(cString: sqlite3_errmsg(handle))) }
    }

    private func bind(_ value: String, to statement: OpaquePointer, at index: Int32) {
        sqlite3_bind_text(statement, index, value, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
    }

    private func bind(_ value: Data, to statement: OpaquePointer, at index: Int32) {
        _ = value.withUnsafeBytes { bytes in
            sqlite3_bind_blob(statement, index, bytes.baseAddress, Int32(bytes.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        }
    }
}
