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

/// Local-first store. Records, revisions and the sync outbox share one SQLite transaction boundary.
public final class SQLiteStore {
    private static let currentSchemaVersion = 1
    private var handle: OpaquePointer?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let lock = NSRecursiveLock()

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
            if version == 0 { try execute("PRAGMA user_version=\(Self.currentSchemaVersion)") }
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
        lock.lock(); defer { lock.unlock() }
        guard let handle else { throw SQLiteStoreError.open("本地数据库未打开。") }
        let payload = try encoder.encode(value)
        try execute("BEGIN IMMEDIATE")
        do {
            try insert(payload, kind: kind, id: id, revision: revision)
            if appendRevision {
                try insertRevision(payload, kind: kind, objectID: id, revision: revision)
            }
            try insertOutbox(payload, kind: kind, objectID: id, revision: revision)
            try execute("COMMIT")
        } catch {
            _ = try? execute("ROLLBACK")
            throw error
        }
        _ = handle
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

    private func execute(_ sql: String) throws {
        guard let handle else { throw SQLiteStoreError.open("本地数据库未打开。") }
        var errorPointer: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(handle, sql, nil, nil, &errorPointer) == SQLITE_OK else {
            let message = errorPointer.map { String(cString: $0) } ?? String(cString: sqlite3_errmsg(handle))
            sqlite3_free(errorPointer)
            throw SQLiteStoreError.statement(message)
        }
    }

    private func insert(_ payload: Data, kind: String, id: String, revision: Int) throws {
        guard let handle else { throw SQLiteStoreError.open("本地数据库未打开。") }
        var statement: OpaquePointer?
        let sql = "INSERT INTO records(kind,id,revision,payload,created_at,updated_at) VALUES(?,?,?,?,COALESCE((SELECT created_at FROM records WHERE kind=? AND id=?),?),?) ON CONFLICT(kind,id) DO UPDATE SET revision=excluded.revision,payload=excluded.payload,updated_at=excluded.updated_at"
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw SQLiteStoreError.statement(String(cString: sqlite3_errmsg(handle)))
        }
        defer { sqlite3_finalize(statement) }
        let now = Date.now.timeIntervalSince1970
        bind(kind, to: statement, at: 1); bind(id, to: statement, at: 2)
        sqlite3_bind_int64(statement, 3, sqlite3_int64(revision)); bind(payload, to: statement, at: 4)
        bind(kind, to: statement, at: 5); bind(id, to: statement, at: 6)
        sqlite3_bind_double(statement, 7, now); sqlite3_bind_double(statement, 8, now)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw SQLiteStoreError.statement(String(cString: sqlite3_errmsg(handle))) }
    }

    private func insertRevision(_ payload: Data, kind: String, objectID: String, revision: Int) throws {
        guard let handle else { throw SQLiteStoreError.open("本地数据库未打开。") }
        var statement: OpaquePointer?
        let sql = "INSERT INTO revisions(id,kind,object_id,revision,payload,created_at) VALUES(?,?,?,?,?,?)"
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw SQLiteStoreError.statement(String(cString: sqlite3_errmsg(handle)))
        }
        defer { sqlite3_finalize(statement) }
        bind(UUID().uuidString, to: statement, at: 1); bind(kind, to: statement, at: 2); bind(objectID, to: statement, at: 3)
        sqlite3_bind_int64(statement, 4, sqlite3_int64(revision)); bind(payload, to: statement, at: 5)
        sqlite3_bind_double(statement, 6, Date.now.timeIntervalSince1970)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw SQLiteStoreError.statement(String(cString: sqlite3_errmsg(handle))) }
    }

    private func insertOutbox(_ payload: Data, kind: String, objectID: String, revision: Int) throws {
        guard let handle else { throw SQLiteStoreError.open("本地数据库未打开。") }
        var statement: OpaquePointer?
        let sql = "INSERT INTO outbox(event_id,kind,object_id,revision,payload,created_at,state) VALUES(?,?,?,?,?,?, 'pending')"
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw SQLiteStoreError.statement(String(cString: sqlite3_errmsg(handle)))
        }
        defer { sqlite3_finalize(statement) }
        bind(UUID().uuidString, to: statement, at: 1); bind(kind, to: statement, at: 2); bind(objectID, to: statement, at: 3)
        sqlite3_bind_int64(statement, 4, sqlite3_int64(revision)); bind(payload, to: statement, at: 5)
        sqlite3_bind_double(statement, 6, Date.now.timeIntervalSince1970)
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
