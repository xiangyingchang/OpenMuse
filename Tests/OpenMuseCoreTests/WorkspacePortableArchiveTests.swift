import CryptoKit
import Foundation
import XCTest
import ZIPFoundation
@testable import OpenMuseCore

final class WorkspacePortableArchiveTests: XCTestCase {
    func testPortableZipRoundTripsJSONLHistoryConflictsAndSeparateAttachmentBytes() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let conversation = ConversationRecord(id: "portable-conversation", title: "旅行计划", createdAt: now, updatedAt: now)
        let message = MessageRecord(id: "portable-message", conversationID: conversation.id, role: .user, content: "看看附件", createdAt: now, attachmentIDs: ["portable-file"])
        let document = WorkspaceDocument(path: "GLOBAL.md", title: "GLOBAL", content: "便携记忆", revision: 2, updatedAt: now)
        let olderDocument = WorkspaceDocument(path: "GLOBAL.md", title: "GLOBAL", content: "旧版本", revision: 1, updatedAt: now.addingTimeInterval(-60))
        let attachmentBytes = Data("可迁移的附件原文".utf8)
        let attachment = AttachmentRecord(
            id: "portable-file", conversationID: conversation.id, messageID: message.id,
            displayName: "trip.txt", mediaType: "text/plain", byteCount: attachmentBytes.count,
            sha256: Self.digest(attachmentBytes), createdAt: now
        )
        let conflictLocal = try JSONEncoder().encode(document)
        let conflictRemote = try JSONEncoder().encode(WorkspaceDocument(path: "GLOBAL.md", title: "GLOBAL", content: "另一版", revision: 2, updatedAt: now))
        let conflict = SyncConflictRecord(
            id: "portable-conflict", eventID: "event-1", workspaceID: "workspace-1", objectID: "GLOBAL.md",
            kind: RecordKind.document, localRevision: 2, remoteRevision: 2,
            localPayload: conflictLocal, remotePayload: conflictRemote, createdAt: now
        )
        let records = try [
            Self.snapshot(conversation, recordID: conversation.id, kind: RecordKind.conversation, revision: 1, createdAt: now, updatedAt: now),
            Self.snapshot(message, recordID: message.id, kind: RecordKind.message, revision: 1, createdAt: now, updatedAt: now),
            Self.snapshot(attachment, recordID: attachment.id, kind: RecordKind.attachment, revision: 1, createdAt: now, updatedAt: now),
            Self.snapshot(document, recordID: document.path, kind: RecordKind.document, revision: 2, createdAt: now, updatedAt: now)
        ]
        let revisions = [
            WorkspaceRevisionSnapshot(kind: RecordKind.document, recordID: document.path, revision: 1, payload: try JSONEncoder().encode(olderDocument), createdAt: olderDocument.updatedAt),
            WorkspaceRevisionSnapshot(kind: RecordKind.document, recordID: document.path, revision: 2, payload: conflictLocal, createdAt: now)
        ]
        let archive = try WorkspaceArchive.make(
            from: WorkspaceStoreSnapshot(records: records, revisions: revisions, conflicts: [conflict]),
            includeConversations: true,
            attachmentFiles: [WorkspaceAttachmentFile(id: attachment.id, data: attachmentBytes, byteCount: attachmentBytes.count, sha256: attachment.sha256)]
        )

        let portable = try WorkspacePortableArchive.encode(archive)
        XCTAssertTrue(portable.starts(with: [0x50, 0x4b]))
        let paths = try Self.entries(in: portable).keys.sorted()
        XCTAssertEqual(paths, ["attachments/portable-file.bin", "conflicts.jsonl", "manifest.json", "records.jsonl", "revisions.jsonl"])

        let jsonLines = try Self.entries(in: portable)["records.jsonl"]!
        let firstLine = try XCTUnwrap(String(data: jsonLines, encoding: .utf8)?.split(separator: "\n").first)
        let recordObject = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(firstLine.utf8)) as? [String: Any])
        XCTAssertTrue(recordObject["payload"] is [String: Any], "JSONL payloads must stay structured JSON objects.")

        let restored = try WorkspaceArchive.decodePackage(portable)
        XCTAssertEqual(restored.manifest.exportID, archive.manifest.exportID)
        XCTAssertEqual(restored.payload.records.map(\.recordID).sorted(), archive.payload.records.map(\.recordID).sorted())
        XCTAssertEqual(restored.payload.revisions.count, 2)
        XCTAssertEqual(restored.payload.conflicts.count, 1)
        XCTAssertEqual(restored.attachmentFiles.first?.data, attachmentBytes)
        let restoredMessage = try XCTUnwrap(restored.payload.records.first(where: { $0.kind == RecordKind.message }).map { try JSONDecoder().decode(MessageRecord.self, from: $0.payload) })
        XCTAssertEqual(restoredMessage.attachmentIDs, [attachment.id])

        let legacyJSON = try archive.encoded()
        XCTAssertEqual(try WorkspaceArchive.decodePackage(legacyJSON).manifest.exportID, archive.manifest.exportID)
    }

    func testPortableZipRoundTripsArtifactImageAssetsWithoutConversations() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_100)
        let bytes = Data([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x01, 0x02])
        let descriptor = ArtifactAssetDescriptor(id: "trip-map-image", mediaType: "image/png", byteCount: bytes.count, sha256: Self.digest(bytes))
        let artifact = ArtifactRecord(
            id: "portable-web-artifact", title: "旅行地图", kind: "web", conversationID: "omitted-conversation",
            goalID: nil, content: #"<img src="openmuse-asset://trip-map-image">"#, assetReferences: [descriptor], updatedAt: now
        )
        let snapshot = WorkspaceStoreSnapshot(
            records: [try Self.snapshot(artifact, recordID: artifact.id, kind: RecordKind.artifact, revision: 1, createdAt: now, updatedAt: now)],
            revisions: [], conflicts: []
        )
        let file = WorkspaceAttachmentFile(
            id: descriptor.id, data: bytes, byteCount: bytes.count, sha256: descriptor.sha256,
            artifactID: artifact.id, mediaType: descriptor.mediaType
        )
        let archive = try WorkspaceArchive.make(from: snapshot, includeConversations: false, attachmentFiles: [file])

        let portable = try WorkspacePortableArchive.encode(archive)
        XCTAssertEqual(
            try Self.entries(in: portable).keys.sorted(),
            ["artifact-assets/portable-web-artifact/trip-map-image.bin", "conflicts.jsonl", "manifest.json", "records.jsonl", "revisions.jsonl"]
        )
        let restored = try WorkspaceArchive.decodePackage(portable)
        XCTAssertEqual(restored.attachmentFiles, [file])
        XCTAssertFalse(restored.manifest.omittedKinds.contains(RecordKind.artifact))
        XCTAssertTrue(restored.manifest.omittedKinds.contains(RecordKind.conversation))
    }

    func testPortableWorkspaceRetainsAssetsReferencedOnlyByArtifactConflictVersions() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_200)
        let artifactID = "conflicted-artifact"
        let localBytes = Data([1, 2, 3])
        let remoteBytes = Data([4, 5, 6])
        let localAsset = ArtifactAssetDescriptor(id: "local-version-image", mediaType: "image/png", byteCount: localBytes.count, sha256: Self.digest(localBytes))
        let remoteAsset = ArtifactAssetDescriptor(id: "remote-version-image", mediaType: "image/jpeg", byteCount: remoteBytes.count, sha256: Self.digest(remoteBytes))
        let current = ArtifactRecord(id: artifactID, title: "旅行计划", kind: "web", conversationID: "conversation", goalID: nil, content: "<html></html>", updatedAt: now)
        let local = ArtifactRecord(id: artifactID, title: "旅行计划", kind: "web", conversationID: "conversation", goalID: nil, content: "local", assetReferences: [localAsset], updatedAt: now)
        let remote = ArtifactRecord(id: artifactID, title: "旅行计划", kind: "web", conversationID: "conversation", goalID: nil, content: "remote", assetReferences: [remoteAsset], updatedAt: now)
        let conflict = SyncConflictRecord(
            id: "artifact-conflict", eventID: "artifact-conflict-event", workspaceID: "workspace", objectID: artifactID,
            kind: RecordKind.artifact, localRevision: 2, remoteRevision: 2,
            localPayload: try JSONEncoder().encode(local), remotePayload: try JSONEncoder().encode(remote), createdAt: now
        )
        let snapshot = WorkspaceStoreSnapshot(
            records: [try Self.snapshot(current, recordID: artifactID, kind: RecordKind.artifact, revision: 1, createdAt: now, updatedAt: now)],
            revisions: [], conflicts: [conflict]
        )
        let files = [
            WorkspaceAttachmentFile(id: localAsset.id, data: localBytes, byteCount: localBytes.count, sha256: localAsset.sha256, artifactID: artifactID, mediaType: localAsset.mediaType),
            WorkspaceAttachmentFile(id: remoteAsset.id, data: remoteBytes, byteCount: remoteBytes.count, sha256: remoteAsset.sha256, artifactID: artifactID, mediaType: remoteAsset.mediaType)
        ]

        let portable = try WorkspacePortableArchive.encode(WorkspaceArchive.make(from: snapshot, includeConversations: false, attachmentFiles: files))
        let restored = try WorkspaceArchive.decodePackage(portable)
        XCTAssertEqual(Set(restored.attachmentFiles.map(\.id)), Set([localAsset.id, remoteAsset.id]))
        XCTAssertEqual(Set(restored.attachmentFiles.map(\.data)), Set([localBytes, remoteBytes]))
    }

    func testImportingTheSamePortablePackageTwiceUsesStableExportIdentity() throws {
        let document = WorkspaceDocument(path: "USER.md", title: "USER", content: "已确认偏好", revision: 1)
        let archive = try WorkspaceArchive.make(
            from: WorkspaceStoreSnapshot(records: [try Self.snapshot(document, recordID: document.path, kind: RecordKind.document, revision: 1, createdAt: .now, updatedAt: .now)], revisions: [], conflicts: []),
            includeConversations: false
        )
        let package = try WorkspacePortableArchive.encode(archive)
        let decoded = try WorkspaceArchive.decodePackage(package)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("OpenMusePortableImport-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try SQLiteStore(path: root.appendingPathComponent("workspace.sqlite"))

        XCTAssertFalse(try store.importSnapshot(decoded).duplicateArchive)
        XCTAssertTrue(try store.importSnapshot(try WorkspaceArchive.decodePackage(package)).duplicateArchive)
        XCTAssertEqual(try store.load(WorkspaceDocument.self, kind: RecordKind.document).first?.content, "已确认偏好")
    }

    func testPortablePackageRejectsModifiedFileAndUnsafeZipPath() throws {
        let document = WorkspaceDocument(path: "USER.md", title: "USER", content: "内容", revision: 1)
        let archive = try WorkspaceArchive.make(
            from: WorkspaceStoreSnapshot(records: [try Self.snapshot(document, recordID: document.path, kind: RecordKind.document, revision: 1, createdAt: .now, updatedAt: .now)], revisions: [], conflicts: []),
            includeConversations: false
        )
        let package = try WorkspacePortableArchive.encode(archive)
        var files = try Self.entries(in: package)
        files["records.jsonl"]![0] ^= 1
        XCTAssertThrowsError(try WorkspacePortableArchive.decode(Self.zip(files)))

        let malicious = [
            "records.jsonl": Data(), "revisions.jsonl": Data(), "conflicts.jsonl": Data(), "../escape.txt": Data("x".utf8)
        ]
        let manifest = TestManifest(
            formatVersion: 1, minimumReaderVersion: 1, exportID: "bad", createdAt: .now,
            includesConversations: false, recordCount: 0, revisionCount: 0, conflictCount: 0,
            includedKinds: [], omittedKinds: [], archivePayloadSHA256: String(repeating: "0", count: 64),
            files: malicious.map { TestFileDescriptor(path: $0.key, byteCount: $0.value.count, sha256: Self.digest($0.value)) }
        )
        var maliciousFiles = malicious
        maliciousFiles["manifest.json"] = try JSONEncoder().encode(manifest)
        XCTAssertThrowsError(try WorkspacePortableArchive.decode(Self.zip(maliciousFiles)))
    }

    func testPortableManifestRejectsAgentWorkspacePathInVersionOne() throws {
        let baseFiles = [
            "records.jsonl": Data(),
            "revisions.jsonl": Data(),
            "conflicts.jsonl": Data(),
            "agent-workspaces.jsonl": Data()
        ]
        let manifest = TestManifest(
            formatVersion: 1, minimumReaderVersion: 1, exportID: "legacy-with-agent-workspace",
            createdAt: .now, includesConversations: false, recordCount: 0, revisionCount: 0,
            conflictCount: 0, includedKinds: [], omittedKinds: [],
            archivePayloadSHA256: String(repeating: "0", count: 64),
            files: baseFiles.map { TestFileDescriptor(path: $0.key, byteCount: $0.value.count, sha256: Self.digest($0.value)) }
        )
        var entries = baseFiles
        entries["manifest.json"] = try JSONEncoder().encode(manifest)

        XCTAssertThrowsError(try WorkspacePortableArchive.decode(Self.zip(entries)))
    }

    func testPortableVersionTwoRequiresWorkspaceJSONL() throws {
        let files = [
            "records.jsonl": Data(),
            "revisions.jsonl": Data(),
            "conflicts.jsonl": Data()
        ]
        let manifest = TestManifest(
            formatVersion: 2, minimumReaderVersion: 2, exportID: "v2-without-workspaces",
            createdAt: .now, includesConversations: true, recordCount: 0, revisionCount: 0,
            conflictCount: 0, includedKinds: [], omittedKinds: [],
            archivePayloadSHA256: String(repeating: "0", count: 64),
            files: files.map { TestFileDescriptor(path: $0.key, byteCount: $0.value.count, sha256: Self.digest($0.value)) }
        )
        var entries = files
        entries["manifest.json"] = try JSONEncoder().encode(manifest)

        XCTAssertThrowsError(try WorkspacePortableArchive.decode(Self.zip(entries)))
    }

    private static func snapshot<T: Encodable>(_ value: T, recordID: String, kind: String, revision: Int, createdAt: Date, updatedAt: Date) throws -> WorkspaceRecordSnapshot {
        WorkspaceRecordSnapshot(kind: kind, recordID: recordID, revision: revision, payload: try JSONEncoder().encode(value), createdAt: createdAt, updatedAt: updatedAt)
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func entries(in data: Data) throws -> [String: Data] {
        let archive = try Archive(data: data, accessMode: .read)
        var output: [String: Data] = [:]
        for entry in archive {
            var bytes = Data()
            _ = try archive.extract(entry) { bytes.append($0) }
            output[entry.path] = bytes
        }
        return output
    }

    private static func zip(_ entries: [String: Data]) throws -> Data {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("OpenMusePortableTest-\(UUID().uuidString).zip")
        defer { try? FileManager.default.removeItem(at: url) }
        do {
            let archive = try Archive(url: url, accessMode: .create)
            for (path, contents) in entries.sorted(by: { $0.key < $1.key }) {
                try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(contents.count), compressionMethod: .deflate) { position, size in
                    let lower = Int(position)
                    return contents.subdata(in: lower..<min(lower + size, contents.count))
                }
            }
        }
        return try Data(contentsOf: url)
    }

    private struct TestManifest: Encodable {
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
        let files: [TestFileDescriptor]
    }

    private struct TestFileDescriptor: Encodable {
        let path: String
        let byteCount: Int
        let sha256: String
    }
}
