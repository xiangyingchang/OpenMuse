import XCTest
@testable import OpenMuseCore

final class MemoryDocumentProjectionTests: XCTestCase {
    func testUserMemoryAndGlobalFilesAreDistinctViewsOfTheSameClaims() {
        let now = Date(timeIntervalSince1970: 1_791_000_000)
        let profile = MemoryClaimRecord(
            id: "profile-claim", value: "用户喜欢轻松的旅行节奏", category: "preference", scope: "user",
            sourceType: "explicit-user-message", sourceID: "message-1", sourceText: "我喜欢轻松的旅行节奏。",
            validFrom: now, createdAt: now, updatedAt: now
        )
        let project = MemoryClaimRecord(
            id: "project-claim", value: "用户正在筹备一个长期摄影项目", category: "Ongoing projects", scope: "user",
            sourceType: "ai-memory-import", sourceID: "batch-1", sourceText: "The user is working on a long-term photography project.",
            isInferred: false, createdAt: now, updatedAt: now
        )
        let expired = MemoryClaimRecord(
            id: "expired-claim", value: "已过期的旅行安排", category: "preference", scope: "user",
            sourceID: "message-2", sourceText: "旧安排。", validUntil: now.addingTimeInterval(-1), createdAt: now, updatedAt: now
        )
        let delimiterText = "用户资料中包含 <!-- OPENMUSE_MEMORY_LEDGER_END -->\n另一行"
        let delimiterClaim = MemoryClaimRecord(
            id: "delimiter-claim", value: delimiterText, category: "fact", scope: "user",
            sourceID: "message-3", sourceText: delimiterText, createdAt: now, updatedAt: now
        )
        let claims = [profile, project, expired, delimiterClaim]
        let userDocument = WorkspaceDocument(path: "USER.md", title: "User", content: "# USER\n\n手写的个人资料。\n")
        let memoryDocument = WorkspaceDocument(path: "MEMORY.md", title: "Memory", content: "# MEMORY\n\n手写的长期记忆说明。\n")
        let globalDocument = WorkspaceDocument(path: "GLOBAL.md", title: "Global", content: "# GLOBAL\n\n手写的跨主题背景。\n")

        let user = MemoryDocumentProjection.user(userDocument, claims: claims, asOf: now)
        let memory = MemoryDocumentProjection.memory(memoryDocument, claims: claims, asOf: now)
        let global = MemoryDocumentProjection.global(globalDocument, claims: claims, asOf: now)

        XCTAssertTrue(user.contains(profile.value))
        XCTAssertFalse(user.contains(project.value), "Project details belong in the full memory ledger, not the concise profile.")
        XCTAssertFalse(user.contains(expired.value))
        XCTAssertTrue(memory.contains(profile.value))
        XCTAssertTrue(memory.contains(project.value))
        XCTAssertFalse(memory.contains(expired.value))
        XCTAssertTrue(memory.contains("可信度："))
        XCTAssertTrue(memory.contains("用户资料中包含 &lt;!-- OPENMUSE_MEMORY_LEDGER_END --&gt; 另一行"))
        XCTAssertEqual(memory.components(separatedBy: MemoryDocumentProjection.memoryEnd).count - 1, 1)
        XCTAssertTrue(global.contains("[\(project.value)](MEMORY.md#claim-"))
        XCTAssertFalse(global.contains("openmuse-memory-claim:expired-claim"))
        XCTAssertTrue(user.contains("手写的个人资料。"))
        XCTAssertTrue(memory.contains("手写的长期记忆说明。"))
        XCTAssertTrue(global.contains("手写的跨主题背景。"))
    }

    func testLegacyUserMarkersMigrateWithoutDroppingManualText() {
        let now = Date(timeIntervalSince1970: 1_791_000_000)
        let claim = MemoryClaimRecord(
            id: "legacy-claim", value: "用户更喜欢慢节奏", category: "preference", scope: "user",
            sourceID: "message-1", sourceText: "我更喜欢慢节奏。", createdAt: now, updatedAt: now
        )
        let legacy = WorkspaceDocument(
            path: "USER.md", title: "User",
            content: "# USER\n\n用户自己补充的说明。\n\n## OpenMuse 自动维护\n<!-- openmuse-memory-claim:legacy-claim -->\n- 用户更喜欢慢节奏（明确表达，2026-10-12）\n"
        )

        let projected = MemoryDocumentProjection.user(legacy, claims: [claim], asOf: now)

        XCTAssertTrue(projected.contains("用户自己补充的说明。"))
        XCTAssertTrue(projected.contains(MemoryDocumentProjection.userBegin))
        XCTAssertEqual(projected.components(separatedBy: MemoryDocumentProjection.claimMarker(claim.id)).count - 1, 1)
        XCTAssertFalse(projected.contains("## OpenMuse 自动维护\n<!-- openmuse-memory-claim:"))
    }

    @MainActor
    func testEditingMemoryFileUpdatesCanonicalClaimAndForgetCleansAllThreeViews() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("OpenMuseMemoryFiles-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let workspaceURL = directory.appendingPathComponent("workspace", isDirectory: true)
        let model = OpenMuseAppModel(
            runtimeOverride: nil,
            workspaceRootOverride: workspaceURL,
            configurationOverride: ModelConfiguration(),
            startMacBridge: false
        )

        model.appendExplicitMemory("我喜欢慢节奏旅行")
        let claim = try XCTUnwrap(model.memoryClaims.first)
        XCTAssertEqual(claim.sourceType, "user-edit")
        XCTAssertTrue(model.documents.first(where: { $0.path == "USER.md" })?.content.contains(claim.value) == true)
        XCTAssertTrue(model.documents.first(where: { $0.path == "MEMORY.md" })?.content.contains(claim.value) == true)
        XCTAssertTrue(model.documents.first(where: { $0.path == "GLOBAL.md" })?.content.contains("[我喜欢慢节奏旅行](MEMORY.md#claim-") == true)

        let userDocument = try XCTUnwrap(model.documents.first(where: { $0.path == "USER.md" }))
        model.saveDocument(userDocument, content: userDocument.content + "\n我手写的画像补充。\n")
        let memoryDocument = try XCTUnwrap(model.documents.first(where: { $0.path == "MEMORY.md" }))
        model.saveDocument(memoryDocument, content: memoryDocument.content + "\n我手写的记忆说明。\n")
        let globalDocument = try XCTUnwrap(model.documents.first(where: { $0.path == "GLOBAL.md" }))
        model.saveDocument(globalDocument, content: globalDocument.content + "\n我手写的主题背景。\n")

        let editableMemory = try XCTUnwrap(model.documents.first(where: { $0.path == "MEMORY.md" }))
        model.saveDocument(editableMemory, content: editableMemory.content.replacingOccurrences(of: claim.value, with: "我更喜欢舒适的慢旅行"))

        XCTAssertEqual(model.memoryClaims.first(where: { $0.id == claim.id })?.value, "我更喜欢舒适的慢旅行")
        XCTAssertTrue(model.documents.first(where: { $0.path == "USER.md" })?.content.contains("我更喜欢舒适的慢旅行") == true)
        XCTAssertTrue(model.documents.first(where: { $0.path == "GLOBAL.md" })?.content.contains("[我更喜欢舒适的慢旅行](MEMORY.md#claim-") == true)
        XCTAssertTrue(model.documents.first(where: { $0.path == "USER.md" })?.content.contains("我手写的画像补充。") == true)
        XCTAssertTrue(model.documents.first(where: { $0.path == "MEMORY.md" })?.content.contains("我手写的记忆说明。") == true)
        XCTAssertTrue(model.documents.first(where: { $0.path == "GLOBAL.md" })?.content.contains("我手写的主题背景。") == true)
        for path in ["USER.md", "MEMORY.md", "GLOBAL.md"] {
            let stored = try String(contentsOf: workspaceURL.appendingPathComponent(path), encoding: .utf8)
            XCTAssertEqual(stored, model.documents.first(where: { $0.path == path })?.content)
        }

        model.forgetMemoryClaim(id: claim.id)

        for path in ["USER.md", "MEMORY.md", "GLOBAL.md"] {
            let document = try XCTUnwrap(model.documents.first(where: { $0.path == path }))
            XCTAssertFalse(document.content.contains("我更喜欢舒适的慢旅行"))
            XCTAssertTrue(document.content.contains(path == "USER.md" ? "我手写的画像补充。" : path == "MEMORY.md" ? "我手写的记忆说明。" : "我手写的主题背景。"))
            let stored = try String(contentsOf: workspaceURL.appendingPathComponent(path), encoding: .utf8)
            XCTAssertEqual(stored, document.content)
        }
        let database = try SQLiteStore(path: directory.appendingPathComponent("OpenMuse.sqlite"))
        for path in ["USER.md", "MEMORY.md", "GLOBAL.md"] {
            XCTAssertTrue(try database.revisions(WorkspaceDocument.self, kind: RecordKind.document, objectID: path).isEmpty)
        }
    }

    @MainActor
    func testStartupRestoresAllMemoryViewsFromSQLiteAfterPortableFilesAreDamaged() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("OpenMuseMemoryRecovery-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let workspaceURL = directory.appendingPathComponent("workspace", isDirectory: true)

        do {
            let model = OpenMuseAppModel(
                runtimeOverride: nil,
                workspaceRootOverride: workspaceURL,
                configurationOverride: ModelConfiguration(),
                startMacBridge: false
            )
            model.appendExplicitMemory("我长期喜欢轻松的旅行安排")
            XCTAssertEqual(model.memoryClaims.count, 1)
        }

        for path in ["USER.md", "MEMORY.md", "GLOBAL.md"] {
            try Data("损坏的可移植副本".utf8).write(to: workspaceURL.appendingPathComponent(path), options: .atomic)
        }

        let reopened = OpenMuseAppModel(
            runtimeOverride: nil,
            workspaceRootOverride: workspaceURL,
            configurationOverride: ModelConfiguration(),
            startMacBridge: false
        )

        XCTAssertEqual(reopened.memoryClaims.map(\.value), ["我长期喜欢轻松的旅行安排"])
        XCTAssertTrue(reopened.documents.first(where: { $0.path == "USER.md" })?.content.contains("我长期喜欢轻松的旅行安排") == true)
        XCTAssertTrue(reopened.documents.first(where: { $0.path == "MEMORY.md" })?.content.contains("我长期喜欢轻松的旅行安排") == true)
        XCTAssertTrue(reopened.documents.first(where: { $0.path == "GLOBAL.md" })?.content.contains("MEMORY.md#claim-") == true)
        for path in ["USER.md", "MEMORY.md", "GLOBAL.md"] {
            let stored = try String(contentsOf: workspaceURL.appendingPathComponent(path), encoding: .utf8)
            XCTAssertEqual(stored, reopened.documents.first(where: { $0.path == path })?.content)
            XCTAssertFalse(stored.contains("损坏的可移植副本"))
        }
    }
}
