import Foundation
import XCTest
@testable import OpenMuseCore

final class OnDeviceAgentAttachmentAccessTests: XCTestCase {
    func testAttachmentAccessIsReadOnlyAndLimitedToCurrentConversation() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenMuseAgentAttachmentAccess-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try AttachmentStore(rootURL: directory)
        let current = try store.importData(
            Data("恩施旅行：每天留出自由时间。".utf8),
            displayName: "trip.md", mediaType: "text/markdown",
            conversationID: "conversation-current", messageID: "message-current", id: "current-attachment"
        )
        let other = try store.importData(
            Data("另一段私密对话内容。".utf8),
            displayName: "other.txt", mediaType: "text/plain",
            conversationID: "conversation-other", messageID: "message-other", id: "other-attachment"
        )
        let access = try OnDeviceAgentAttachmentAccess(
            conversationID: "conversation-current",
            records: [current, other],
            store: store
        )

        let listing = access.list()
        XCTAssertEqual(listing.totalCount, 1)
        XCTAssertEqual(listing.items.map(\.id), [current.id])
        XCTAssertFalse(listing.isTruncated)

        let content = try access.readText(id: current.id)
        XCTAssertEqual(content.attachment.displayName, "trip.md")
        XCTAssertTrue(content.extractedText.contains("每天留出自由时间"))
        XCTAssertThrowsError(try access.readText(id: other.id)) {
            XCTAssertEqual($0 as? OnDeviceAgentAttachmentAccessError, .notFound)
        }
        XCTAssertThrowsError(try access.readText(id: "../other-attachment")) {
            XCTAssertEqual($0 as? OnDeviceAgentAttachmentAccessError, .notFound)
        }
    }

    func testListingAndExtractedTextHaveExplicitBounds() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenMuseAgentAttachmentBounds-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try AttachmentStore(rootURL: directory)
        var records: [AttachmentRecord] = []
        for index in 0..<OnDeviceAgentAttachmentAccess.maximumListedAttachments + 2 {
            var record = try store.importData(
                Data(String(repeating: "旅行计划。", count: 3).utf8),
                displayName: "trip-\(index).txt", mediaType: "text/plain",
                conversationID: "conversation", messageID: "message-\(index)", id: "attachment-\(index)"
            )
            record.createdAt = Date(timeIntervalSince1970: TimeInterval(index))
            records.append(record)
        }
        let access = try OnDeviceAgentAttachmentAccess(conversationID: "conversation", records: records, store: store)

        let listing = access.list()
        XCTAssertEqual(listing.totalCount, records.count)
        XCTAssertEqual(listing.items.count, OnDeviceAgentAttachmentAccess.maximumListedAttachments)
        XCTAssertTrue(listing.isTruncated)
        XCTAssertEqual(listing.items.first?.id, "attachment-41", "Most recent attachments should appear first.")

        let excerpt = try access.readText(id: "attachment-41", maximumBytes: 5).extractedText
        XCTAssertTrue(excerpt.contains("[附件文本已截断]"))
        XCTAssertFalse(excerpt.contains("�"), "Truncation must preserve valid UTF-8.")
        XCTAssertThrowsError(try access.readText(id: "attachment-41", maximumBytes: 0)) {
            XCTAssertEqual($0 as? OnDeviceAgentAttachmentAccessError, .invalidLimit)
        }
    }
}
