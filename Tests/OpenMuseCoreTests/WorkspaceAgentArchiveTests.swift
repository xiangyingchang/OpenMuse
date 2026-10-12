import Foundation
import XCTest
@testable import OpenMuseCore

final class WorkspaceAgentArchiveTests: XCTestCase {
    func testPortableArchiveRoundTripsAgentWorkspaceOnlyWithConversations() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let conversation = ConversationRecord(id: "agent-chat", title: "恩施旅行")
        let record = try snapshot(conversation, kind: RecordKind.conversation, createdAt: now)
        let file = WorkspaceAgentFile(conversationID: conversation.id, path: "travel/outline.md", data: Data("七天行程草稿".utf8))
        let payload = WorkspaceStoreSnapshot(records: [record], revisions: [])

        let full = try WorkspaceArchive.make(
            from: payload,
            includeConversations: true,
            agentWorkspaceFiles: [file],
            exportID: "agent-workspace-portable"
        )
        XCTAssertEqual(full.manifest.formatVersion, 2)
        XCTAssertTrue(full.manifest.includedKinds.contains(RecordKind.agentWorkspace))
        let portable = try WorkspacePortableArchive.encode(full)
        let restored = try WorkspaceArchive.decodePackage(portable)
        XCTAssertEqual(restored.agentWorkspaceFiles, [file])

        let recordsOnly = try WorkspaceArchive.make(
            from: payload,
            includeConversations: false,
            agentWorkspaceFiles: [file],
            exportID: "agent-workspace-without-chat"
        )
        XCTAssertTrue(recordsOnly.agentWorkspaceFiles.isEmpty)
        XCTAssertTrue(recordsOnly.manifest.omittedKinds.contains(RecordKind.agentWorkspace))
        let restoredWithoutChat = try WorkspaceArchive.decodePackage(WorkspacePortableArchive.encode(recordsOnly))
        XCTAssertTrue(restoredWithoutChat.agentWorkspaceFiles.isEmpty)
    }

    func testSnapshotIncludesOnlyExistingWorkspacesForRequestedConversations() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("OpenMuseAgentArchiveSource-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let included = try OnDeviceAgentWorkspace(rootURL: root, conversationID: "included-chat")
        let excluded = try OnDeviceAgentWorkspace(rootURL: root, conversationID: "excluded-chat")
        try included.writeFile(path: "draft.md", content: "只迁移这个对话")
        try excluded.writeFile(path: "private.md", content: "不在请求列表")

        let files = try AgentWorkspaceArchiveManager.snapshotExisting(rootURL: root, conversationIDs: ["included-chat"])

        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(files.first?.conversationID, "included-chat")
        XCTAssertEqual(files.first?.path, "draft.md")
        XCTAssertEqual(String(data: try XCTUnwrap(files.first?.data), encoding: .utf8), "只迁移这个对话")
    }

    func testRestorePreservesLocalConflictAndIsIdempotent() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("OpenMuseAgentArchiveRestore-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let importedData = Data("源设备的计划".utf8)
        let file = WorkspaceAgentFile(conversationID: "restore-chat", path: "travel/plan.md", data: importedData)
        let local = try OnDeviceAgentWorkspace(rootURL: root.appendingPathComponent("workspaces", isDirectory: true), conversationID: file.conversationID)
        try local.writeFile(path: file.path, content: "本机较新的计划")

        let first = try AgentWorkspaceArchiveManager.restore(
            [file], rootURL: local.rootURL.deletingLastPathComponent(), exportID: "source-export"
        )
        let restored = try OnDeviceAgentWorkspace(rootURL: local.rootURL.deletingLastPathComponent(), conversationID: file.conversationID)
        XCTAssertEqual(first.importedFiles, 1)
        XCTAssertEqual(first.preservedConflicts, 1)
        XCTAssertEqual(try restored.readFile(path: file.path), "本机较新的计划")
        let conflictPath = try XCTUnwrap(try restored.listFiles().first(where: { $0.hasPrefix("_openmuse_import_conflicts/") }))
        XCTAssertEqual(try restored.readFile(path: conflictPath), "源设备的计划")

        let second = try AgentWorkspaceArchiveManager.restore(
            [file], rootURL: local.rootURL.deletingLastPathComponent(), exportID: "source-export"
        )
        XCTAssertEqual(second.importedFiles, 0)
        XCTAssertEqual(try restored.readFile(path: file.path), "本机较新的计划")
        XCTAssertEqual(try restored.readFile(path: conflictPath), "源设备的计划")
    }

    func testRestoreDoesNotReportAnExistingConflictAsNewWhenItAddsAnotherFile() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("OpenMuseAgentArchiveConflictCount-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let conversationID = "conflict-count-chat"
        let files = [
            WorkspaceAgentFile(conversationID: conversationID, path: "travel/plan.md", data: Data("导入计划".utf8)),
            WorkspaceAgentFile(conversationID: conversationID, path: "travel/notes.md", data: Data("补充笔记".utf8))
        ]
        let local = try OnDeviceAgentWorkspace(rootURL: root, conversationID: conversationID)
        try local.writeFile(path: "travel/plan.md", content: "本机计划")

        let first = try AgentWorkspaceArchiveManager.restore(files, rootURL: root, exportID: "conflict-count-export")
        XCTAssertEqual(first.preservedConflicts, 1)
        try FileManager.default.removeItem(at: local.rootURL.appendingPathComponent("travel/notes.md"))

        let retry = try AgentWorkspaceArchiveManager.restore(files, rootURL: root, exportID: "conflict-count-export")
        XCTAssertEqual(retry.importedFiles, 1)
        XCTAssertEqual(retry.preservedConflicts, 0)
    }

    func testArchiveRejectsAgentWorkspaceTraversalOrChecksumTampering() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_100)
        let conversation = ConversationRecord(id: "validation-chat", title: "校验")
        let record = try snapshot(conversation, kind: RecordKind.conversation, createdAt: now)
        let file = WorkspaceAgentFile(conversationID: conversation.id, path: "safe.md", data: Data("safe".utf8))
        let archive = try WorkspaceArchive.make(
            from: WorkspaceStoreSnapshot(records: [record], revisions: []),
            includeConversations: true,
            agentWorkspaceFiles: [file]
        )
        let invalidPath = WorkspaceAgentFile(conversationID: conversation.id, path: "../outside.md", data: file.data)
        var tamperedJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(file)) as? [String: Any])
        tamperedJSON["sha256"] = String(repeating: "0", count: 64)
        let invalidHash = try JSONDecoder().decode(WorkspaceAgentFile.self, from: JSONSerialization.data(withJSONObject: tamperedJSON))

        XCTAssertThrowsError(try WorkspaceArchive.make(
            from: archive.payload,
            includeConversations: true,
            agentWorkspaceFiles: [invalidPath]
        ))
        let tampered = WorkspaceArchive(
            manifest: archive.manifest,
            payload: archive.payload,
            attachmentFiles: archive.attachmentFiles,
            agentWorkspaceFiles: [invalidHash]
        )
        XCTAssertThrowsError(try tampered.validate())
    }

    private func snapshot<T: Encodable>(_ value: T, kind: String, createdAt: Date) throws -> WorkspaceRecordSnapshot {
        let id: String
        if let conversation = value as? ConversationRecord { id = conversation.id }
        else { throw WorkspaceArchiveError.invalidRecords }
        return WorkspaceRecordSnapshot(
            kind: kind, recordID: id, revision: 1,
            payload: try JSONEncoder().encode(value), createdAt: createdAt, updatedAt: createdAt
        )
    }
}
