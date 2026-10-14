import XCTest
@testable import OpenMuseCore

final class SideConversationContextTests: XCTestCase {
    func testExcerptContainsOnlyRecentTwoTurnsAndBoundsEachMessage() throws {
        let parentID = "parent"
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let messages = [
            MessageRecord(id: "old-user", conversationID: parentID, role: .user, content: "旧的旅行想法", createdAt: now),
            MessageRecord(id: "old-assistant", conversationID: parentID, role: .assistant, content: "旧回复", createdAt: now.addingTimeInterval(1)),
            MessageRecord(id: "recent-user", conversationID: parentID, role: .user, content: "最近我想去恩施", createdAt: now.addingTimeInterval(2)),
            MessageRecord(id: "recent-assistant", conversationID: parentID, role: .assistant, content: String(repeating: "当日路线与休息安排。", count: 100), createdAt: now.addingTimeInterval(3)),
            MessageRecord(id: "new-user", conversationID: parentID, role: .user, content: "想把节奏放慢", createdAt: now.addingTimeInterval(4)),
            MessageRecord(id: "new-assistant", conversationID: parentID, role: .assistant, content: "可以减少景点并留出休息时间。", createdAt: now.addingTimeInterval(5))
        ]

        let excerpt = try XCTUnwrap(SideConversationContext.excerpt(parentConversationID: parentID, messages: messages))

        XCTAssertFalse(excerpt.contains("旧的旅行想法"))
        XCTAssertTrue(excerpt.contains("最近我想去恩施"))
        XCTAssertTrue(excerpt.contains("想把节奏放慢"))
        XCTAssertTrue(excerpt.contains("[已截短]"))
        XCTAssertLessThanOrEqual(excerpt.filter { $0 == "\n" }.count, 6)
        XCTAssertLessThanOrEqual(excerpt.count, SideConversationContext.maximumMessages * (SideConversationContext.maximumCharactersPerMessage + 160))
        XCTAssertTrue(excerpt.contains("原始时区未记录"), "Legacy message time zones must be marked as an estimate.")
    }

    func testExcerptOmitsOtherConversationsFailedMessagesAndImportedHistory() {
        let messages = [
            MessageRecord(id: "other", conversationID: "other", role: .user, content: "其他对话内容"),
            MessageRecord(id: "failed", conversationID: "parent", role: .assistant, content: "失败输出", status: "failed"),
            MessageRecord(id: "imported", conversationID: "parent", role: .user, content: "旧导入内容", importedFrom: "ChatGPT")
        ]

        XCTAssertNil(SideConversationContext.excerpt(parentConversationID: "parent", messages: messages))
    }
}
