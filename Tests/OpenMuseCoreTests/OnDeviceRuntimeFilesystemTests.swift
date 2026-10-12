import Foundation
import XCTest
@testable import OpenMuseCore

final class OnDeviceRuntimeFilesystemTests: XCTestCase {
    func testPreparesOpenMinisStyleMountsWithReadOnlyAttachments() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let mounts = try fixture.runtime.prepareMounts()

        XCTAssertEqual(mounts.map(\.area), OnDeviceRuntimeArea.allCases)
        XCTAssertEqual(mounts.map(\.guestPath), [
            "/var/minis/offloads", "/var/minis/attachments",
            "/var/minis/workspace", "/var/minis/browser"
        ])
        XCTAssertEqual(mounts.first(where: { $0.area == .attachments })?.access, .readOnly)
        XCTAssertTrue(mounts.filter { $0.area != .attachments }.allSatisfy { $0.access == .readWrite })
        XCTAssertTrue(mounts.allSatisfy { $0.hostURL.path.hasPrefix(fixture.runtime.sessionRootURL.path + "/") })
        XCTAssertNotEqual(mounts.first(where: { $0.area == .workspace })?.hostURL, fixture.workspace.rootURL)
    }

    func testGuestWorkspaceIsScratchAndCannotBypassApprovedWorkspaceWrites() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let guestWorkspace = try fixture.runtime.directory(for: .workspace)
        try Data("unreviewed guest output".utf8).write(to: guestWorkspace.appendingPathComponent("travel.md"))

        XCTAssertEqual(try fixture.workspace.listFiles(), [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.workspace.rootURL.appendingPathComponent("travel.md").path))
    }

    func testRuntimeAreasPersistPerConversationAndStayOutOfTextWorkspaceListings() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let browser = try fixture.runtime.directory(for: .browser)
        try Data("page snapshot".utf8).write(to: browser.appendingPathComponent("snapshot.html"))

        let reopened = try OnDeviceRuntimeFilesystem(
            rootURL: fixture.runtimeRoot,
            conversationID: "travel-chat"
        )
        let reopenedBrowser = try reopened.directory(for: .browser)

        XCTAssertEqual(try String(contentsOf: reopenedBrowser.appendingPathComponent("snapshot.html"), encoding: .utf8), "page snapshot")
        XCTAssertEqual(try fixture.workspace.listFiles(), [])
    }

    func testRuntimeAreasAreIsolatedBetweenConversations() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let otherRuntime = try OnDeviceRuntimeFilesystem(
            rootURL: fixture.runtimeRoot,
            conversationID: "other-chat"
        )
        try Data("private to one session".utf8).write(to: try fixture.runtime.directory(for: .offloads).appendingPathComponent("result.txt"))

        XCTAssertFalse(FileManager.default.fileExists(atPath: try otherRuntime.directory(for: .offloads).appendingPathComponent("result.txt").path))
        XCTAssertNotEqual(fixture.runtime.sessionRootURL, otherRuntime.sessionRootURL)
    }

    func testStagesOnlyCurrentConversationAttachmentsWithOpaqueNamesAndRefreshesOldFiles() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = try AttachmentStore(rootURL: fixture.base.appendingPathComponent("attachment-store", isDirectory: true))
        let current = try store.importData(
            Data("trip notes".utf8),
            displayName: "../恩施 行程",
            mediaType: "text/markdown",
            conversationID: "travel-chat",
            messageID: "message-1",
            id: "attachment-current"
        )
        _ = try store.importData(
            Data("other chat secret".utf8),
            displayName: "private",
            mediaType: "text/plain",
            conversationID: "other-chat",
            messageID: "message-2",
            id: "attachment-other"
        )
        let guestDirectory = try fixture.runtime.directory(for: .attachments)
        try Data("stale".utf8).write(to: guestDirectory.appendingPathComponent("stale.txt"))

        try fixture.runtime.stageAttachments([current], conversationID: "travel-chat", store: store)

        let staged = try FileManager.default.contentsOfDirectory(at: guestDirectory, includingPropertiesForKeys: nil)
        XCTAssertEqual(staged.count, 1)
        XCTAssertTrue(staged[0].lastPathComponent.hasPrefix("attachment-current-"))
        XCTAssertEqual(staged[0].pathExtension, "md")
        XCTAssertEqual(try Data(contentsOf: staged[0]), Data("trip notes".utf8))

        try fixture.runtime.stageAttachments([], conversationID: "travel-chat", store: store)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(at: guestDirectory, includingPropertiesForKeys: nil), [])
    }

    func testRejectsSymlinkedRuntimeArea() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let attachments = try fixture.runtime.directory(for: .attachments)
        try FileManager.default.removeItem(at: attachments)
        let outside = fixture.base.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: false)
        try FileManager.default.createSymbolicLink(at: attachments, withDestinationURL: outside)

        XCTAssertThrowsError(try fixture.runtime.prepareMounts()) {
            XCTAssertEqual($0 as? OnDeviceRuntimeFilesystemError, .unsafeArea(.attachments))
        }
    }

    func testRejectsEmptyConversationID() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        XCTAssertThrowsError(try OnDeviceRuntimeFilesystem(
            rootURL: fixture.runtimeRoot,
            conversationID: " \n"
        )) {
            XCTAssertEqual($0 as? OnDeviceRuntimeFilesystemError, .invalidConversation)
        }
    }
}

private final class Fixture {
    let base: URL
    var runtimeRoot: URL { base.appendingPathComponent("runtime", isDirectory: true) }
    var workspaceBase: URL { base.appendingPathComponent("workspaces", isDirectory: true) }
    let workspace: OnDeviceAgentWorkspace
    let runtime: OnDeviceRuntimeFilesystem

    init() throws {
        let fixtureBase = FileManager.default.temporaryDirectory.appendingPathComponent("OpenMuseRuntimeFilesystem-\(UUID().uuidString)", isDirectory: true)
        base = fixtureBase
        try FileManager.default.createDirectory(at: fixtureBase, withIntermediateDirectories: true)
        let workspace = try OnDeviceAgentWorkspace(
            rootURL: fixtureBase.appendingPathComponent("workspaces", isDirectory: true),
            conversationID: "travel-chat"
        )
        self.workspace = workspace
        runtime = try OnDeviceRuntimeFilesystem(
            rootURL: fixtureBase.appendingPathComponent("runtime", isDirectory: true),
            conversationID: "travel-chat"
        )
    }

    func remove() { try? FileManager.default.removeItem(at: base) }
}
