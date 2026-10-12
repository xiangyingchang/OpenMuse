import CryptoKit
import Foundation
import ZIPFoundation

/// Portable on-disk layout: a manifest, one JSON object per line, and chat/artifact media as separate files.
public enum WorkspacePortableArchive {
    public static let maximumCompressedBytes = WorkspaceArchive.maximumArchiveBytes
    private static let maximumEntryCount = 250_000
    private static let maximumManifestBytes = 1_000_000
    private static let fixedPathsV1: Set<String> = ["records.jsonl", "revisions.jsonl", "conflicts.jsonl"]
    private static let fixedPathsV2 = fixedPathsV1.union(["agent-workspaces.jsonl"])

    public static func encode(_ archive: WorkspaceArchive) throws -> Data {
        try archive.validate()

        let includesConversations = !archive.manifest.omittedKinds.contains(RecordKind.conversation)
        let normalizedArchive = try WorkspaceArchive.make(
            from: try canonicalized(archive.payload),
            includeConversations: includesConversations,
            attachmentFiles: archive.attachmentFiles,
            agentWorkspaceFiles: archive.agentWorkspaceFiles,
            exportID: archive.manifest.exportID,
            createdAt: archive.manifest.createdAt
        )

        var files: [String: Data] = [
            "records.jsonl": try encodeJSONL(normalizedArchive.payload.records.map(PortableRecordLine.init)),
            "revisions.jsonl": try encodeJSONL(normalizedArchive.payload.revisions.map(PortableRevisionLine.init)),
            "conflicts.jsonl": try encodeJSONL(normalizedArchive.payload.conflicts.map(PortableConflictLine.init))
        ]
        if !normalizedArchive.agentWorkspaceFiles.isEmpty {
            files["agent-workspaces.jsonl"] = try encodeJSONL(normalizedArchive.agentWorkspaceFiles)
        }
        for attachment in normalizedArchive.attachmentFiles {
            if let artifactID = attachment.artifactID {
                guard ArtifactAssetStore.isSafeID(artifactID), ArtifactAssetStore.isSafeID(attachment.id) else {
                    throw WorkspaceArchiveError.invalidRecords
                }
                files["artifact-assets/\(artifactID)/\(attachment.id).bin"] = attachment.data
            } else {
                guard AttachmentRecord.isSafeIdentifier(attachment.id) else { throw WorkspaceArchiveError.invalidRecords }
                files["attachments/\(attachment.id).bin"] = attachment.data
            }
        }
        let descriptors = files.map { path, data in
            PortableFileDescriptor(path: path, byteCount: data.count, sha256: digest(data))
        }.sorted { $0.path < $1.path }
        let portableManifest = PortableManifest(
            formatVersion: normalizedArchive.agentWorkspaceFiles.isEmpty ? 1 : 2,
            minimumReaderVersion: normalizedArchive.agentWorkspaceFiles.isEmpty ? 1 : 2,
            exportID: normalizedArchive.manifest.exportID,
            createdAt: normalizedArchive.manifest.createdAt,
            includesConversations: includesConversations,
            recordCount: normalizedArchive.manifest.recordCount,
            revisionCount: normalizedArchive.manifest.revisionCount,
            conflictCount: normalizedArchive.manifest.conflictCount,
            includedKinds: normalizedArchive.manifest.includedKinds,
            omittedKinds: normalizedArchive.manifest.omittedKinds,
            archivePayloadSHA256: digest(try encodeJSON(descriptors)),
            files: descriptors
        )
        let manifestData = try encodeJSON(portableManifest)
        guard manifestData.count <= maximumManifestBytes else { throw WorkspaceArchiveError.tooLarge }
        files["manifest.json"] = manifestData

        let totalBytes = files.values.reduce(0) { $0 + $1.count }
        guard totalBytes <= WorkspaceArchive.maximumArchiveBytes else { throw WorkspaceArchiveError.tooLarge }
        return try zip(files)
    }

    public static func decode(_ data: Data) throws -> WorkspaceArchive {
        guard !data.isEmpty, data.count <= maximumCompressedBytes else { throw WorkspaceArchiveError.tooLarge }
        let zip: Archive
        do { zip = try Archive(data: data, accessMode: .read) }
        catch { throw WorkspaceArchiveError.invalidPortableArchive }

        var entries: [String: Entry] = [:]
        for entry in zip {
            guard entries.count < maximumEntryCount,
                  entry.type == .file,
                  safePath(entry.path),
                  entries[entry.path] == nil else {
                throw WorkspaceArchiveError.invalidPortableArchive
            }
            entries[entry.path] = entry
        }
        guard let manifestEntry = entries["manifest.json"], manifestEntry.uncompressedSize <= UInt64(maximumManifestBytes) else {
            throw WorkspaceArchiveError.invalidManifest
        }
        let manifestData = try extract(manifestEntry, from: zip, limit: maximumManifestBytes)
        let manifest: PortableManifest
        do { manifest = try JSONDecoder().decode(PortableManifest.self, from: manifestData) }
        catch { throw WorkspaceArchiveError.invalidManifest }
        try validate(manifest)

        let fileDescriptors = Dictionary(uniqueKeysWithValues: manifest.files.map { ($0.path, $0) })
        guard Set(entries.keys) == Set(fileDescriptors.keys).union(["manifest.json"]) else {
            throw WorkspaceArchiveError.invalidPortableArchive
        }

        var contents: [String: Data] = [:]
        for descriptor in manifest.files {
            guard let entry = entries[descriptor.path],
                  entry.uncompressedSize == UInt64(descriptor.byteCount),
                  descriptor.byteCount >= 0 else { throw WorkspaceArchiveError.invalidPortableArchive }
            let bytes = try extract(entry, from: zip, limit: descriptor.byteCount)
            guard digest(bytes) == descriptor.sha256.lowercased() else { throw WorkspaceArchiveError.checksumMismatch }
            contents[descriptor.path] = bytes
        }
        let actualDescriptors = manifest.files.map { descriptor in
            PortableFileDescriptor(path: descriptor.path, byteCount: contents[descriptor.path]?.count ?? -1, sha256: contents[descriptor.path].map(digest) ?? "")
        }.sorted { $0.path < $1.path }
        guard digest(try encodeJSON(actualDescriptors)) == manifest.archivePayloadSHA256 else {
            throw WorkspaceArchiveError.checksumMismatch
        }

        guard let recordsData = contents["records.jsonl"],
              let revisionsData = contents["revisions.jsonl"],
              let conflictsData = contents["conflicts.jsonl"] else {
            throw WorkspaceArchiveError.invalidPortableArchive
        }
        let records = try decodeJSONL(PortableRecordLine.self, from: recordsData, maximumCount: 250_000).map { try $0.snapshot() }
        let revisions = try decodeJSONL(PortableRevisionLine.self, from: revisionsData, maximumCount: 1_000_000).map { try $0.snapshot() }
        let conflicts = try decodeJSONL(PortableConflictLine.self, from: conflictsData, maximumCount: 250_000).map { try $0.conflict() }
        let agentWorkspaceFiles: [WorkspaceAgentFile]
        if manifest.formatVersion >= 2 {
            guard let data = contents["agent-workspaces.jsonl"] else { throw WorkspaceArchiveError.invalidPortableArchive }
            agentWorkspaceFiles = try decodeJSONL(WorkspaceAgentFile.self, from: data, maximumCount: 250_000)
        } else {
            agentWorkspaceFiles = []
        }
        guard records.count == manifest.recordCount,
              revisions.count == manifest.revisionCount,
              conflicts.count == manifest.conflictCount else { throw WorkspaceArchiveError.invalidManifest }

        let snapshot = WorkspaceStoreSnapshot(records: records, revisions: revisions, conflicts: conflicts)
        let artifactReferences = try WorkspaceArchive.artifactAssetReferences(in: snapshot)
        let referencesByPath = Dictionary(uniqueKeysWithValues: artifactReferences.map {
            ("artifact-assets/\($0.artifactID)/\($0.descriptor.id).bin", ($0.artifactID, $0.descriptor))
        })
        let attachments = try manifest.files.compactMap { file -> WorkspaceAttachmentFile? in
            guard let bytes = contents[file.path] else { throw WorkspaceArchiveError.invalidPortableArchive }
            if file.path.hasPrefix("attachments/") {
                let id = String(file.path.dropFirst("attachments/".count).dropLast(".bin".count))
                guard AttachmentRecord.isSafeIdentifier(id) else { throw WorkspaceArchiveError.invalidPortableArchive }
                return WorkspaceAttachmentFile(id: id, data: bytes, byteCount: bytes.count, sha256: file.sha256)
            }
            if let (artifactID, asset) = referencesByPath[file.path] {
                return WorkspaceAttachmentFile(
                    id: asset.id, data: bytes, byteCount: bytes.count, sha256: file.sha256,
                    artifactID: artifactID, mediaType: asset.mediaType
                )
            }
            return nil
        }
        let expectedMediaFileCount = manifest.files.filter { $0.path.hasPrefix("attachments/") || $0.path.hasPrefix("artifact-assets/") }.count
        guard attachments.count == expectedMediaFileCount else {
            throw WorkspaceArchiveError.invalidPortableArchive
        }

        let archive = try WorkspaceArchive.make(
            from: snapshot,
            includeConversations: manifest.includesConversations,
            attachmentFiles: attachments,
            agentWorkspaceFiles: agentWorkspaceFiles,
            exportID: manifest.exportID,
            createdAt: manifest.createdAt
        )
        guard archive.manifest.recordCount == manifest.recordCount,
              archive.manifest.revisionCount == manifest.revisionCount,
              archive.manifest.conflictCount == manifest.conflictCount,
              archive.manifest.includedKinds == manifest.includedKinds,
              archive.manifest.omittedKinds == manifest.omittedKinds else {
            throw WorkspaceArchiveError.checksumMismatch
        }
        return archive
    }

    private static func validate(_ manifest: PortableManifest) throws {
        guard [1, 2].contains(manifest.formatVersion),
              manifest.minimumReaderVersion >= 1,
              manifest.minimumReaderVersion <= 2 else {
            throw WorkspaceArchiveError.unsupportedVersion
        }
        let fixedPaths = manifest.formatVersion == 1 ? fixedPathsV1 : fixedPathsV2
        guard !manifest.exportID.isEmpty, manifest.exportID.count <= 100,
              manifest.recordCount >= 0, manifest.recordCount <= 250_000,
              manifest.revisionCount >= 0, manifest.revisionCount <= 1_000_000,
              manifest.conflictCount >= 0, manifest.conflictCount <= 250_000,
              manifest.files.count >= fixedPaths.count, manifest.files.count <= maximumEntryCount,
              manifest.archivePayloadSHA256.count == 64, manifest.archivePayloadSHA256.allSatisfy(\.isHexDigit),
              Set(manifest.includedKinds).count == manifest.includedKinds.count,
              Set(manifest.omittedKinds).count == manifest.omittedKinds.count else {
            throw WorkspaceArchiveError.invalidManifest
        }
        let paths = manifest.files.map(\.path)
        guard Set(paths).count == paths.count,
              !paths.contains("manifest.json"),
              fixedPaths.isSubset(of: Set(paths)),
              manifest.formatVersion != 1 || !paths.contains("agent-workspaces.jsonl"),
              manifest.files.allSatisfy({ safePath($0.path) && $0.byteCount >= 0 && $0.byteCount <= WorkspaceArchive.maximumArchiveBytes && $0.sha256.count == 64 && $0.sha256.allSatisfy(\.isHexDigit) }),
              manifest.files.filter({ $0.path.hasPrefix("attachments/") }).count <= 10_000,
              manifest.files.filter({ $0.path.hasPrefix("artifact-assets/") }).count <= 10_000 else {
            throw WorkspaceArchiveError.invalidManifest
        }
        let attachmentPaths = manifest.files.filter { $0.path.hasPrefix("attachments/") }.map(\.path)
        guard attachmentPaths.allSatisfy({ path in
            let file = String(path.dropFirst("attachments/".count))
            return file.hasSuffix(".bin") && AttachmentRecord.isSafeIdentifier(String(file.dropLast(".bin".count)))
        }) else { throw WorkspaceArchiveError.invalidManifest }
        let artifactAssetPaths = manifest.files.filter { $0.path.hasPrefix("artifact-assets/") }.map(\.path)
        guard artifactAssetPaths.allSatisfy({ path in
            let parts = path.split(separator: "/")
            return parts.count == 3 && parts[0] == "artifact-assets" && parts[2].hasSuffix(".bin") &&
                ArtifactAssetStore.isSafeID(String(parts[1])) &&
                ArtifactAssetStore.isSafeID(String(parts[2].dropLast(".bin".count)))
        }) else { throw WorkspaceArchiveError.invalidManifest }
        let bytes = manifest.files.reduce(0) { $0 + $1.byteCount }
        guard bytes <= WorkspaceArchive.maximumArchiveBytes else { throw WorkspaceArchiveError.tooLarge }
    }

    private static func safePath(_ path: String) -> Bool {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\"), !path.split(separator: "/").contains("..") else { return false }
        if fixedPathsV2.contains(path) || path == "manifest.json" { return true }
        if path.hasPrefix("attachments/"), path.hasSuffix(".bin") {
            let id = String(path.dropFirst("attachments/".count).dropLast(".bin".count))
            return AttachmentRecord.isSafeIdentifier(id)
        }
        if path.hasPrefix("artifact-assets/") {
            let parts = path.split(separator: "/")
            return parts.count == 3 && parts[0] == "artifact-assets" && parts[2].hasSuffix(".bin") &&
                ArtifactAssetStore.isSafeID(String(parts[1])) &&
                ArtifactAssetStore.isSafeID(String(parts[2].dropLast(".bin".count)))
        }
        return false
    }

    private static func zip(_ files: [String: Data]) throws -> Data {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("OpenMuse-\(UUID().uuidString).zip")
        defer { try? FileManager.default.removeItem(at: url) }
        do {
            let archive = try Archive(url: url, accessMode: .create)
            for (path, contents) in files.sorted(by: { $0.key < $1.key }) {
                try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(contents.count), compressionMethod: .deflate) { position, size in
                    let lower = Int(position)
                    let upper = min(lower + size, contents.count)
                    guard lower >= 0, lower <= upper else { throw WorkspaceArchiveError.invalidPortableArchive }
                    return contents.subdata(in: lower..<upper)
                }
            }
        } catch let error as WorkspaceArchiveError {
            throw error
        } catch {
            throw WorkspaceArchiveError.invalidPortableArchive
        }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard data.count <= maximumCompressedBytes else { throw WorkspaceArchiveError.tooLarge }
        return data
    }

    private static func extract(_ entry: Entry, from archive: Archive, limit: Int) throws -> Data {
        guard limit >= 0, entry.uncompressedSize <= UInt64(limit) else { throw WorkspaceArchiveError.tooLarge }
        var result = Data()
        result.reserveCapacity(Int(entry.uncompressedSize))
        do {
            _ = try archive.extract(entry, bufferSize: 16 * 1024) { chunk in
                guard result.count <= limit - chunk.count else { throw WorkspaceArchiveError.tooLarge }
                result.append(chunk)
            }
        } catch let error as WorkspaceArchiveError {
            throw error
        } catch {
            throw WorkspaceArchiveError.invalidPortableArchive
        }
        return result
    }

    private static func encodeJSON<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }

    private static func encodeJSONL<T: Encodable>(_ values: [T]) throws -> Data {
        guard !values.isEmpty else { return Data() }
        var data = Data()
        for value in values {
            data.append(try encodeJSON(value))
            data.append(0x0a)
        }
        return data
    }

    private static func canonicalized(_ snapshot: WorkspaceStoreSnapshot) throws -> WorkspaceStoreSnapshot {
        let records = try snapshot.records.map { record in
            WorkspaceRecordSnapshot(
                kind: record.kind, recordID: record.recordID, revision: record.revision,
                payload: try canonicalJSON(record.payload), createdAt: record.createdAt, updatedAt: record.updatedAt
            )
        }
        let revisions = try snapshot.revisions.map { revision in
            WorkspaceRevisionSnapshot(
                kind: revision.kind, recordID: revision.recordID, revision: revision.revision,
                payload: try canonicalJSON(revision.payload), createdAt: revision.createdAt
            )
        }
        let conflicts = try snapshot.conflicts.map { conflict in
            SyncConflictRecord(
                id: conflict.id, eventID: conflict.eventID, workspaceID: conflict.workspaceID,
                objectID: conflict.objectID, kind: conflict.kind, localRevision: conflict.localRevision,
                remoteRevision: conflict.remoteRevision,
                localPayload: try canonicalJSON(conflict.localPayload),
                remotePayload: try canonicalJSON(conflict.remotePayload), createdAt: conflict.createdAt
            )
        }
        return WorkspaceStoreSnapshot(records: records, revisions: revisions, conflicts: conflicts)
    }

    private static func canonicalJSON(_ data: Data) throws -> Data {
        let value = try JSONDecoder().decode(PortableJSONValue.self, from: data)
        return try encodeJSON(value)
    }

    static func canonicalPayload(_ data: Data) throws -> Data {
        try canonicalJSON(data)
    }

    private static func decodeJSONL<T: Decodable>(_ type: T.Type, from data: Data, maximumCount: Int) throws -> [T] {
        guard let text = String(data: data, encoding: .utf8) else { throw WorkspaceArchiveError.invalidRecords }
        if text.isEmpty { return [] }
        guard text.hasSuffix("\n") else { throw WorkspaceArchiveError.invalidRecords }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let values = lines.dropLast()
        guard values.count <= maximumCount, values.allSatisfy({ !$0.isEmpty }) else { throw WorkspaceArchiveError.invalidRecords }
        do { return try values.map { try JSONDecoder().decode(type, from: Data($0.utf8)) } }
        catch { throw WorkspaceArchiveError.invalidRecords }
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private struct PortableManifest: Codable {
        let formatVersion: Int
        let minimumReaderVersion: Int
        let exportID: String
        let createdAt: Date
        let includesConversations: Bool
        let recordCount: Int
        let revisionCount: Int
        let conflictCount: Int
        let includedKinds: [String]
        let omittedKinds: [String]
        let archivePayloadSHA256: String
        let files: [PortableFileDescriptor]
    }

    private struct PortableFileDescriptor: Codable {
        let path: String
        let byteCount: Int
        let sha256: String
    }

    private struct PortableRecordLine: Codable {
        let kind: String
        let recordID: String
        let revision: Int
        let createdAt: Date
        let updatedAt: Date
        let payload: PortableJSONValue

        init(_ record: WorkspaceRecordSnapshot) throws {
            kind = record.kind
            recordID = record.recordID
            revision = record.revision
            createdAt = record.createdAt
            updatedAt = record.updatedAt
            payload = try JSONDecoder().decode(PortableJSONValue.self, from: record.payload)
        }

        func snapshot() throws -> WorkspaceRecordSnapshot {
            WorkspaceRecordSnapshot(kind: kind, recordID: recordID, revision: revision, payload: try encodeJSON(payload), createdAt: createdAt, updatedAt: updatedAt)
        }
    }

    private struct PortableRevisionLine: Codable {
        let kind: String
        let recordID: String
        let revision: Int
        let createdAt: Date
        let payload: PortableJSONValue

        init(_ revision: WorkspaceRevisionSnapshot) throws {
            kind = revision.kind
            recordID = revision.recordID
            self.revision = revision.revision
            createdAt = revision.createdAt
            payload = try JSONDecoder().decode(PortableJSONValue.self, from: revision.payload)
        }

        func snapshot() throws -> WorkspaceRevisionSnapshot {
            WorkspaceRevisionSnapshot(kind: kind, recordID: recordID, revision: revision, payload: try encodeJSON(payload), createdAt: createdAt)
        }
    }

    private struct PortableConflictLine: Codable {
        let id: String
        let eventID: String
        let workspaceID: String
        let objectID: String
        let kind: String
        let localRevision: Int
        let remoteRevision: Int
        let localPayload: PortableJSONValue
        let remotePayload: PortableJSONValue
        let createdAt: Date

        init(_ conflict: SyncConflictRecord) throws {
            id = conflict.id
            eventID = conflict.eventID
            workspaceID = conflict.workspaceID
            objectID = conflict.objectID
            kind = conflict.kind
            localRevision = conflict.localRevision
            remoteRevision = conflict.remoteRevision
            localPayload = try JSONDecoder().decode(PortableJSONValue.self, from: conflict.localPayload)
            remotePayload = try JSONDecoder().decode(PortableJSONValue.self, from: conflict.remotePayload)
            createdAt = conflict.createdAt
        }

        func conflict() throws -> SyncConflictRecord {
            SyncConflictRecord(
                id: id, eventID: eventID, workspaceID: workspaceID, objectID: objectID, kind: kind,
                localRevision: localRevision, remoteRevision: remoteRevision,
                localPayload: try encodeJSON(localPayload), remotePayload: try encodeJSON(remotePayload), createdAt: createdAt
            )
        }
    }
}

private enum PortableJSONValue: Codable {
    case null
    case bool(Bool)
    case number(Decimal)
    case string(String)
    case array([PortableJSONValue])
    case object([String: PortableJSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Decimal.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([PortableJSONValue].self) { self = .array(value) }
        else if let value = try? container.decode([String: PortableJSONValue].self) { self = .object(value) }
        else { throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value.") }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}
