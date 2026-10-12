import Foundation
import XCTest
@testable import OpenMuseCore

final class ConversationContinuityTests: XCTestCase {
    func testLegacyPrimarySessionsMergeWithoutLosingTheirRelatedRecords() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenMusePrimaryChat-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try SQLiteStore(path: directory.appendingPathComponent("state.sqlite"))
        let firstDate = Date(timeIntervalSince1970: 1_700_000_000)
        let secondDate = firstDate.addingTimeInterval(60)
        let first = ConversationRecord(id: "main-first", title: "你好", createdAt: firstDate, updatedAt: secondDate)
        let second = ConversationRecord(id: "main-second", title: "恩施旅行", createdAt: secondDate, updatedAt: secondDate.addingTimeInterval(60))
        let side = ConversationRecord(id: "side-route", title: "路线细节", parentConversationID: second.id, createdAt: secondDate)
        let imported = ConversationRecord(id: "imported-chat", title: "旧 ChatGPT 对话", importedFrom: "ChatGPT", createdAt: firstDate)
        for conversation in [first, second, side, imported] {
            try store.save(conversation, kind: RecordKind.conversation, id: conversation.id)
        }

        let firstMessage = MessageRecord(id: "message-first", conversationID: first.id, role: .user, content: "你好", createdAt: firstDate)
        let secondMessage = MessageRecord(id: "message-second", conversationID: second.id, role: .user, content: "帮我规划恩施七日旅行", createdAt: firstDate, attachmentIDs: ["travel-attachment"])
        let importedMessage = MessageRecord(id: "message-imported", conversationID: imported.id, role: .user, content: "Imported history")
        for message in [firstMessage, secondMessage, importedMessage] {
            try store.save(message, kind: RecordKind.message, id: message.id)
        }

        let goal = GoalRecord(id: "travel-goal", conversationID: second.id, title: "恩施旅行", summary: "7天", steps: [])
        let artifact = ArtifactRecord(id: "travel-artifact", title: "恩施行程", conversationID: second.id, goalID: goal.id, content: "草案")
        let activity = ActivityRecord(id: "travel-activity", conversationID: second.id, title: "规划恩施七日旅行", stage: "已完成", status: "completed")
        let task = TaskExecutionRecord(id: "travel-task", goalID: goal.id, conversationID: second.id)
        let attachment = AttachmentRecord(
            id: "travel-attachment", conversationID: second.id, messageID: secondMessage.id,
            displayName: "travel.md", mediaType: "text/markdown", byteCount: 9,
            sha256: String(repeating: "a", count: 64)
        )
        try store.save(goal, kind: RecordKind.goal, id: goal.id)
        try store.save(artifact, kind: RecordKind.artifact, id: artifact.id)
        try store.save(activity, kind: RecordKind.task, id: activity.id)
        try store.save(task, kind: RecordKind.executionTask, id: task.id)
        try store.save(attachment, kind: RecordKind.attachment, id: attachment.id)

        let primary = try ConversationContinuity.ensurePrimary(in: store)

        XCTAssertEqual(primary.id, first.id)
        XCTAssertEqual(primary.title, "主聊")
        XCTAssertEqual(primary.isPrimary, true)
        XCTAssertEqual(primary.createdAt, firstDate)
        XCTAssertEqual(primary.updatedAt, second.updatedAt)
        XCTAssertEqual(try XCTUnwrap(store.load(ConversationRecord.self, kind: RecordKind.conversation).first(where: { $0.id == second.id })).isArchived, true)
        XCTAssertEqual(try XCTUnwrap(store.load(ConversationRecord.self, kind: RecordKind.conversation).first(where: { $0.id == side.id })).parentConversationID, first.id)
        XCTAssertEqual(try XCTUnwrap(store.load(ConversationRecord.self, kind: RecordKind.conversation).first(where: { $0.id == imported.id })).isArchived, nil)
        XCTAssertEqual(try store.load(MessageRecord.self, kind: RecordKind.message).first(where: { $0.id == firstMessage.id })?.conversationID, first.id)
        XCTAssertEqual(try store.load(MessageRecord.self, kind: RecordKind.message).first(where: { $0.id == secondMessage.id })?.conversationID, first.id)
        XCTAssertEqual(try store.load(AttachmentRecord.self, kind: RecordKind.attachment).first?.conversationID, first.id)
        XCTAssertEqual(try store.load(MessageRecord.self, kind: RecordKind.message).first(where: { $0.id == importedMessage.id })?.conversationID, imported.id)
        XCTAssertEqual(try store.load(GoalRecord.self, kind: RecordKind.goal).first?.conversationID, first.id)
        XCTAssertEqual(try store.load(ArtifactRecord.self, kind: RecordKind.artifact).first?.conversationID, first.id)
        XCTAssertEqual(try store.load(ActivityRecord.self, kind: RecordKind.task).first?.conversationID, first.id)
        XCTAssertEqual(try store.load(TaskExecutionRecord.self, kind: RecordKind.executionTask).first?.conversationID, first.id)
        XCTAssertEqual(ConversationContinuity.orderedMessages([secondMessage, firstMessage]).map(\.id), [firstMessage.id, secondMessage.id])

        let lateSyncedMessage = MessageRecord(id: "message-late-sync", conversationID: second.id, role: .assistant, content: "同步后到达的历史回复")
        let lateSyncedSideChat = ConversationRecord(id: "side-late-sync", title: "后来同步的旁聊", parentConversationID: second.id)
        try store.save(lateSyncedMessage, kind: RecordKind.message, id: lateSyncedMessage.id)
        try store.save(lateSyncedSideChat, kind: RecordKind.conversation, id: lateSyncedSideChat.id)

        let repeated = try ConversationContinuity.ensurePrimary(in: store)
        XCTAssertEqual(repeated, primary)
        XCTAssertEqual(try store.load(MessageRecord.self, kind: RecordKind.message).count, 4)
        XCTAssertEqual(try store.load(MessageRecord.self, kind: RecordKind.message).first(where: { $0.id == lateSyncedMessage.id })?.conversationID, first.id)
        XCTAssertEqual(try store.load(ConversationRecord.self, kind: RecordKind.conversation).first(where: { $0.id == lateSyncedSideChat.id })?.parentConversationID, first.id)
    }

    func testActivityTitlesDescribeTheRequestAndPreferTrackedGoalTitles() {
        XCTAssertEqual(ActivityTitle.make(from: "能不能帮我规划一趟去恩施的旅行，7天。日期待定"), "规划一趟去恩施的旅行，7天")
        XCTAssertEqual(ActivityTitle.make(from: "随便聊聊", goalTitle: "恩施七日旅行计划"), "恩施七日旅行计划")
        XCTAssertEqual(ActivityTitle.make(from: "你好"), "你好")
        XCTAssertEqual(ActivityTitle.make(from: "   \n"), "处理分享的内容")
        let longTitle = ActivityTitle.make(from: String(repeating: "旅行规划", count: 12))
        XCTAssertEqual(longTitle.count, 28)
        XCTAssertTrue(longTitle.hasSuffix("…"))
        XCTAssertEqual(ActivityTitle.make(from: "随便聊聊", goalTitle: String(repeating: "恩施旅行", count: 12)).count, 28)
    }

    func testLegacyGenericActivityTitlesBackfillOnlyFromNearbyLocalRequests() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenMuseActivityTitleMigration-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try SQLiteStore(path: directory.appendingPathComponent("state.sqlite"))
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let main = ConversationRecord(id: "main", title: "主聊", isPrimary: true, createdAt: now, updatedAt: now)
        let imported = ConversationRecord(id: "imported", title: "Imported", importedFrom: "ChatGPT", createdAt: now, updatedAt: now)
        try store.save(main, kind: RecordKind.conversation, id: main.id)
        try store.save(imported, kind: RecordKind.conversation, id: imported.id)

        let request = MessageRecord(id: "travel-request", conversationID: main.id, role: .user, content: "帮我规划一趟去恩施的旅行，7天。", createdAt: now)
        let importedRequest = MessageRecord(id: "imported-request", conversationID: imported.id, role: .user, content: "Imported task", createdAt: now)
        try store.save(request, kind: RecordKind.message, id: request.id)
        try store.save(importedRequest, kind: RecordKind.message, id: importedRequest.id)

        let legacyActivity = ActivityRecord(id: "legacy-activity", conversationID: main.id, title: "继续聊一聊", stage: "已完成", createdAt: now.addingTimeInterval(1))
        let unmatchedActivity = ActivityRecord(id: "unmatched-activity", conversationID: main.id, title: "继续聊一聊", stage: "已完成", createdAt: now.addingTimeInterval(120))
        let importedActivity = ActivityRecord(id: "imported-activity", conversationID: imported.id, title: "继续聊一聊", stage: "已完成", createdAt: now.addingTimeInterval(1))
        for activity in [legacyActivity, unmatchedActivity, importedActivity] {
            try store.save(activity, kind: RecordKind.task, id: activity.id)
        }

        _ = try ConversationContinuity.ensurePrimary(in: store, now: now.addingTimeInterval(180))
        let activities = try store.load(ActivityRecord.self, kind: RecordKind.task)
        let repaired = try XCTUnwrap(activities.first(where: { $0.id == legacyActivity.id }))
        XCTAssertEqual(repaired.title, "规划一趟去恩施的旅行，7天")
        XCTAssertEqual(repaired.sourceMessageID, request.id)
        XCTAssertEqual(activities.first(where: { $0.id == unmatchedActivity.id })?.title, "继续聊一聊")
        XCTAssertNil(activities.first(where: { $0.id == unmatchedActivity.id })?.sourceMessageID)
        XCTAssertEqual(activities.first(where: { $0.id == importedActivity.id })?.title, "继续聊一聊")
        XCTAssertNil(activities.first(where: { $0.id == importedActivity.id })?.sourceMessageID)
    }
}
