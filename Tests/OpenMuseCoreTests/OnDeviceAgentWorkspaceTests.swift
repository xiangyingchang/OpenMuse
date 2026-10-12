import Foundation
import XCTest
@testable import OpenMuseCore

final class OnDeviceAgentWorkspaceTests: XCTestCase {
    func testWritePreflightShowsExactChangeWithoutCreatingDirectoriesOrFiles() throws {
        let fixture = try makePreflightWorkspace()
        let proposed = "# 恩施路线草稿\n留出自由时间。"

        let preview = try fixture.workspace.preflightWrite(path: "travel/outline.md", content: proposed)

        XCTAssertEqual(preview.path, "travel/outline.md")
        XCTAssertEqual(preview.byteCount, Data(proposed.utf8).count)
        XCTAssertFalse(preview.replacesExistingFile)
        XCTAssertNil(preview.existingFileSHA256)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.workspace.rootURL.appendingPathComponent("travel", isDirectory: true).path))
        XCTAssertThrowsError(try fixture.workspace.readFile(path: "travel/outline.md"))
    }

    func testWritePreflightDetectsOverwriteAndRechecksItsFingerprint() throws {
        let fixture = try makePreflightWorkspace()
        try fixture.workspace.writeFile(path: "trip.md", content: "旧行程")

        let preview = try fixture.workspace.preflightWrite(path: "trip.md", content: "新行程")

        XCTAssertTrue(preview.replacesExistingFile)
        XCTAssertEqual(preview.existingFileByteCount, Data("旧行程".utf8).count)
        XCTAssertNotNil(preview.existingFileSHA256)
        try fixture.workspace.writeFile(path: "trip.md", content: "被其他步骤改过")
        let changed = try fixture.workspace.preflightWrite(path: "trip.md", content: "新行程")
        XCTAssertNotEqual(preview.existingFileSHA256, changed.existingFileSHA256)
    }

    private func makePreflightWorkspace() throws -> (root: URL, workspace: OnDeviceAgentWorkspace) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("OpenMuse-Preflight-\(UUID().uuidString)", isDirectory: true)
        let workspace = try OnDeviceAgentWorkspace(rootURL: root, conversationID: "approval-test")
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return (root, workspace)
    }

    func testConversationWorkspacesAreIsolatedAndSupportNestedTextFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("OpenMuseAgentWorkspace-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try OnDeviceAgentWorkspace(rootURL: root, conversationID: "conversation-one")
        let second = try OnDeviceAgentWorkspace(rootURL: root, conversationID: "conversation-two")

        let byteCount = try first.writeFile(path: "travel/outline.md", content: "# 恩施路线草稿\n\n留出休息时间。")

        XCTAssertGreaterThan(byteCount, 0)
        XCTAssertEqual(try first.readFile(path: "travel/outline.md"), "# 恩施路线草稿\n\n留出休息时间。")
        XCTAssertEqual(try first.listFiles(), ["travel/outline.md"])
        XCTAssertEqual(try second.listFiles(), [])
        XCTAssertThrowsError(try second.readFile(path: "travel/outline.md")) {
            XCTAssertEqual($0 as? OnDeviceAgentWorkspaceError, .notFound)
        }
    }

    func testWorkspaceRejectsTraversalUnsupportedExtensionsAndOversizedFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("OpenMuseAgentWorkspaceBounds-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = try OnDeviceAgentWorkspace(rootURL: root, conversationID: "conversation")

        for path in ["../outside.md", "/outside.md", "nested/../../outside.md", "nested\\outside.md", ".secret.md"] {
            XCTAssertThrowsError(try workspace.writeFile(path: path, content: "no"), "Rejected path: \(path)")
        }
        XCTAssertThrowsError(try workspace.writeFile(path: "script.sh", content: "echo unsafe")) {
            XCTAssertEqual($0 as? OnDeviceAgentWorkspaceError, .unsupportedFileType)
        }
        XCTAssertThrowsError(try workspace.writeFile(path: "large.txt", content: String(repeating: "x", count: OnDeviceAgentWorkspace.maximumFileBytes + 1))) {
            XCTAssertEqual($0 as? OnDeviceAgentWorkspaceError, .fileTooLarge)
        }
        XCTAssertThrowsError(try workspace.writeFile(path: "bad.txt", content: "invalid\0text")) {
            XCTAssertEqual($0 as? OnDeviceAgentWorkspaceError, .invalidText)
        }
    }

    func testWorkspaceDoesNotFollowSymlinkedDirectories() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("OpenMuseAgentWorkspaceSymlink-\(UUID().uuidString)", isDirectory: true)
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent("OpenMuseAgentWorkspaceOutside-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outside)
        }
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let workspace = try OnDeviceAgentWorkspace(rootURL: root, conversationID: "conversation")
        try FileManager.default.createSymbolicLink(at: workspace.rootURL.appendingPathComponent("linked", isDirectory: true), withDestinationURL: outside)

        XCTAssertThrowsError(try workspace.writeFile(path: "linked/outside.md", content: "must stay outside"))
        XCTAssertThrowsError(try workspace.readFile(path: "linked/outside.md"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: outside.appendingPathComponent("outside.md").path))

        let outsideFile = outside.appendingPathComponent("private.txt")
        try Data("private".utf8).write(to: outsideFile)
        try FileManager.default.createSymbolicLink(at: workspace.rootURL.appendingPathComponent("linked-file.txt"), withDestinationURL: outsideFile)
        XCTAssertThrowsError(try workspace.readFile(path: "linked-file.txt"))
        XCTAssertThrowsError(try workspace.writeFile(path: "linked-file.txt", content: "overwrite"))
    }

    func testConversationWorkspacePersistsAfterSevenDaysAndAcrossReopen() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("OpenMuseAgentWorkspacePersistence-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try OnDeviceAgentWorkspace(rootURL: root, conversationID: "long-running-task")
        try first.writeFile(path: "trip/plan.md", content: "第一版旅行计划")
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-14 * 24 * 60 * 60)],
            ofItemAtPath: first.rootURL.path
        )

        let reopened = try OnDeviceAgentWorkspace(rootURL: root, conversationID: "long-running-task")

        XCTAssertEqual(try reopened.readFile(path: "trip/plan.md"), "第一版旅行计划")
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.rootURL.path))
    }

    func testLegacyCacheWorkspaceIsMigratedWithoutDeletingItsSource() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("OpenMuseAgentWorkspaceMigration-\(UUID().uuidString)", isDirectory: true)
        let legacyRoot = root.appendingPathComponent("cache", isDirectory: true)
        let persistentRoot = root.appendingPathComponent("support", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let legacy = try OnDeviceAgentWorkspace(rootURL: legacyRoot, conversationID: "same-conversation")
        try legacy.writeFile(path: "drafts/outline.md", content: "旧版本中的草稿")

        let migrated = try OnDeviceAgentWorkspace(
            rootURL: persistentRoot,
            conversationID: "same-conversation",
            legacyCacheRootURL: legacyRoot
        )

        XCTAssertEqual(try migrated.readFile(path: "drafts/outline.md"), "旧版本中的草稿")
        XCTAssertEqual(try legacy.readFile(path: "drafts/outline.md"), "旧版本中的草稿")
    }

    func testWorkspaceCapsTheNumberOfFilesPerConversation() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("OpenMuseAgentWorkspaceFileCount-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = try OnDeviceAgentWorkspace(rootURL: root, conversationID: "conversation")

        for index in 0..<OnDeviceAgentWorkspace.maximumListedFiles {
            try workspace.writeFile(path: "draft-\(index).txt", content: "draft")
        }
        XCTAssertEqual(try workspace.listFiles().count, OnDeviceAgentWorkspace.maximumListedFiles)
        XCTAssertThrowsError(try workspace.writeFile(path: "one-too-many.txt", content: "draft")) {
            XCTAssertEqual($0 as? OnDeviceAgentWorkspaceError, .tooManyFiles)
        }
    }

    func testWorkspaceCapsTotalPersistentStoragePerConversation() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("OpenMuseAgentWorkspaceByteLimit-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = try OnDeviceAgentWorkspace(rootURL: root, conversationID: "bounded-workspace")
        let fullFile = String(repeating: "x", count: OnDeviceAgentWorkspace.maximumFileBytes)
        let fileCount = OnDeviceAgentWorkspace.maximumWorkspaceBytes / OnDeviceAgentWorkspace.maximumFileBytes

        for index in 0..<fileCount {
            try workspace.writeFile(path: "part-\(index).txt", content: fullFile)
        }
        XCTAssertEqual(try workspace.listFiles().count, fileCount)
        XCTAssertThrowsError(try workspace.writeFile(path: "overflow.txt", content: "x")) {
            XCTAssertEqual($0 as? OnDeviceAgentWorkspaceError, .workspaceTooLarge)
        }
    }
}
