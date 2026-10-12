import Foundation
import XCTest
@testable import OpenMuseCore

final class ActivityToolDetailPolicyTests: XCTestCase {
    func testInputRedactsSensitiveJSONFieldsAndCommonInlineCredentials() throws {
        let input = #"{"query":"weather","api_key":"sk-supersecret123456","authorization":"Bearer abc.def.ghi"}"#

        let stored = try XCTUnwrap(ActivityToolDetailPolicy.input(input))

        XCTAssertTrue(stored.contains("[已隐藏]"))
        XCTAssertFalse(stored.contains("sk-supersecret123456"))
        XCTAssertFalse(stored.contains("abc.def.ghi"))
        XCTAssertTrue(stored.contains("weather"))
    }

    func testShellCommandRedactsInlineTokensAndCapsStoredOutput() throws {
        let command = "curl -H 'Authorization: Bearer token-value-123' https://example.com?api_key=sk-privatevalue123456"
        let storedCommand = try XCTUnwrap(ActivityToolDetailPolicy.input(command))
        XCTAssertFalse(storedCommand.contains("token-value-123"))
        XCTAssertFalse(storedCommand.contains("sk-privatevalue123456"))

        let storedOutput = try XCTUnwrap(ActivityToolDetailPolicy.output(String(repeating: "x", count: 20_000)))
        XCTAssertLessThanOrEqual(storedOutput.utf8.count, ActivityToolDetailPolicy.maximumOutputBytes)
        XCTAssertTrue(storedOutput.contains("详情已截断"))
    }

    func testDisplayRemovesTerminalEscapeSequencesAndWrapsLongLines() {
        let displayed = ActivityToolDetailPolicy.display("\u{001B}[31mred\u{001B}[0m\n" + String(repeating: "x", count: 2_100))
        XCTAssertFalse(displayed.contains("\u{001B}"))
        XCTAssertTrue(displayed.contains("red"))
        XCTAssertTrue(displayed.contains("\n"))
    }

    func testActivityOperationPersistsAsItsOwnSyncableRecord() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("activity-operation-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let database = try SQLiteStore(path: root.appendingPathComponent("openmuse.sqlite"))
        let start = Date(timeIntervalSince1970: 1_000)
        let operation = ActivityOperationRecord(
            id: "activity:call-1", activityID: "activity", stepID: "phone-tool-call-1",
            group: "PHONE", toolName: "openmuse_phone_browser_search", toolCallID: "call-1", title: "搜索公开网页",
            status: "completed", inputJSON: #"{"query":"天气"}"#,
            outputText: "来源：www.google.com", startedAt: start,
            finishedAt: start.addingTimeInterval(1.25), updatedAt: start.addingTimeInterval(1.25)
        )

        XCTAssertTrue(operation.isValid)
        XCTAssertEqual(operation.duration, 1.25)
        try database.save(operation, kind: RecordKind.activityOperation, id: operation.id)
        XCTAssertEqual(try database.load(ActivityOperationRecord.self, kind: RecordKind.activityOperation), [operation])
        XCTAssertTrue(RecordKind.syncableKinds.contains(RecordKind.activityOperation))
        XCTAssertTrue(try database.exportSnapshot().records.contains { $0.kind == RecordKind.activityOperation })
        XCTAssertEqual(try database.load(ActivityOperationRecord.self, kind: RecordKind.activityOperation).first?.toolCallID, "call-1")
    }

    func testActivityOperationDetailsRoundTripThroughDeviceSyncAndPortableArchive() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("activity-operation-transfer-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try SQLiteStore(path: root.appendingPathComponent("source.sqlite"))
        let operation = ActivityOperationRecord(
            id: "activity-operation-copy-check", activityID: "activity", stepID: "phone-tool-call-copy-check",
            group: "PHONE", toolName: "openmuse_phone_run_ish_command", toolCallID: "copy-check",
            title: "运行 iSH 命令", status: "failed", inputJSON: #"{"command":"printf test"}"#,
            outputText: "部分输出", errorText: "运行失败", safeSummary: "本机隔离环境",
            startedAt: Date(timeIntervalSince1970: 10), finishedAt: Date(timeIntervalSince1970: 12),
            updatedAt: Date(timeIntervalSince1970: 12)
        )
        try source.save(operation, kind: RecordKind.activityOperation, id: operation.id, revision: 1, appendRevision: true)

        let syncPage = try source.syncEvents(after: [], workspaceID: source.workspaceID)
        let replica = try SQLiteStore(path: root.appendingPathComponent("replica.sqlite"))
        try replica.adoptWorkspaceID(source.workspaceID)
        _ = try replica.applyRemoteSyncEvents(syncPage.events, workspaceID: source.workspaceID)
        XCTAssertEqual(try replica.load(ActivityOperationRecord.self, kind: RecordKind.activityOperation).first, operation)

        let archive = try WorkspaceArchive.make(from: source.exportSnapshot(), includeConversations: false)
        let imported = try SQLiteStore(path: root.appendingPathComponent("imported.sqlite"))
        _ = try imported.importSnapshot(WorkspaceArchive.decode(archive.encoded()))
        XCTAssertEqual(try imported.load(ActivityOperationRecord.self, kind: RecordKind.activityOperation).first, operation)
    }

    func testActivityOperationDecodesRecordsCreatedBeforeToolCallIDWasAdded() throws {
        let operation = ActivityOperationRecord(
            id: "legacy-operation", activityID: "activity", stepID: "phone-tool-legacy",
            group: "PHONE", toolName: "openmuse_phone_browser_search", title: "搜索公开网页",
            status: "completed", startedAt: Date(timeIntervalSince1970: 10),
            finishedAt: Date(timeIntervalSince1970: 11), updatedAt: Date(timeIntervalSince1970: 11)
        )
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(operation)) as? [String: Any])
        json.removeValue(forKey: "toolCallID")
        let legacyData = try JSONSerialization.data(withJSONObject: json)

        let decoded = try JSONDecoder().decode(ActivityOperationRecord.self, from: legacyData)

        XCTAssertNil(decoded.toolCallID)
        XCTAssertEqual(decoded.id, operation.id)
    }
}
