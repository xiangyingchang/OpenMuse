import Foundation
import XCTest
@testable import OpenMuseCore

final class ConversationDeletionTests: XCTestCase {
    @MainActor
    func testDeletingSideChatTombstonesMessagesAndAttachmentsAndKeepsLinkedWork() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("OpenMuseDeleteSideChat-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let workspace = directory.appendingPathComponent("workspace", isDirectory: true)
        let databasePath = directory.appendingPathComponent("OpenMuse.sqlite")
        let store = try SQLiteStore(path: databasePath)
        let primary = ConversationRecord(id: "delete-test-primary", title: "主聊", isPrimary: true, isArchived: false)
        let side = ConversationRecord(id: "delete-test-side", title: "旅行旁聊", parentConversationID: primary.id)
        let child = ConversationRecord(id: "delete-test-child", title: "路线旁聊", parentConversationID: side.id)
        let userMessage = MessageRecord(
            id: "delete-test-user-message", conversationID: side.id, role: .user,
            content: "帮我比较两条路线。", attachmentIDs: ["delete-test-attachment"]
        )
        let assistantMessage = MessageRecord(
            id: "delete-test-assistant-message", conversationID: side.id, role: .assistant,
            content: "我整理了两条路线。"
        )
        try store.save(primary, kind: RecordKind.conversation, id: primary.id)
        try store.save(side, kind: RecordKind.conversation, id: side.id)
        try store.save(child, kind: RecordKind.conversation, id: child.id)
        try store.save(userMessage, kind: RecordKind.message, id: userMessage.id)
        try store.save(assistantMessage, kind: RecordKind.message, id: assistantMessage.id)

        let attachmentStore = try AttachmentStore(rootURL: workspace.appendingPathComponent("attachments", isDirectory: true))
        let attachment = try attachmentStore.importData(
            Data("route notes".utf8), displayName: "routes.txt", mediaType: "text/plain",
            conversationID: side.id, messageID: userMessage.id, id: "delete-test-attachment"
        )
        try store.save(attachment, kind: RecordKind.attachment, id: attachment.id)

        let goal = GoalRecord(
            id: "delete-test-goal", conversationID: side.id, title: "准备旅行",
            summary: "比较路线后再确定。", sourceMessageID: userMessage.id, sourceText: userMessage.content, steps: []
        )
        let artifact = ArtifactRecord(
            id: "delete-test-artifact", title: "旅行草稿", conversationID: side.id, goalID: goal.id,
            content: "七日计划草稿", sourceMessageIDs: [userMessage.id, assistantMessage.id],
            travelPlanVariants: [TravelPlanVariantRecord(title: "七日版", content: "草稿", sourceMessageIDs: [assistantMessage.id])]
        )
        let activity = ActivityRecord(
            id: "delete-test-activity", conversationID: side.id, sourceMessageID: userMessage.id,
            title: "整理旅行路线", stage: "已完成", status: "completed"
        )
        let operation = ActivityOperationRecord(
            id: "delete-test-operation", activityID: activity.id, stepID: "step-1", group: "PHONE",
            toolName: "openmuse_phone_run_ish_command", title: "读取路线", status: "completed", outputText: "已完成"
        )
        let task = TaskExecutionRecord(
            id: "delete-test-task", goalID: goal.id, conversationID: side.id,
            status: "completed", runEpoch: 1, ownerDeviceID: "test-device"
        )
        let memory = MemoryClaimRecord(
            id: "delete-test-memory", value: "喜欢慢节奏旅行", sourceID: userMessage.id,
            sourceText: "旅行时不想每天排满。"
        )
        try store.save(goal, kind: RecordKind.goal, id: goal.id)
        try store.save(artifact, kind: RecordKind.artifact, id: artifact.id)
        try store.save(activity, kind: RecordKind.task, id: activity.id)
        try store.save(operation, kind: RecordKind.activityOperation, id: operation.id)
        try store.save(task, kind: RecordKind.executionTask, id: task.id)
        try store.save(memory, kind: RecordKind.memoryClaim, id: memory.id)

        let model = OpenMuseAppModel(
            runtimeOverride: nil,
            workspaceRootOverride: workspace,
            configurationOverride: ModelConfiguration(),
            startMacBridge: false
        )
        model.openConversation(side.id)

        XCTAssertTrue(model.deleteSideConversation(id: side.id))
        XCTAssertEqual(model.statusText, "旁聊和附件已删除；活动、目标、成果和已确认记忆仍保留。")
        XCTAssertEqual(model.currentConversationID, primary.id)
        XCTAssertFalse(model.conversations.contains(where: { $0.id == side.id }))
        XCTAssertTrue(model.messages.isEmpty)

        let result = try SQLiteStore(path: databasePath)
        let tombstones = try result.load(DeletionTombstoneRecord.self, kind: RecordKind.deletionTombstone)
        XCTAssertTrue(tombstones.contains { $0.recordKind == RecordKind.conversation && $0.recordID == side.id })
        XCTAssertTrue(tombstones.contains { $0.recordKind == RecordKind.message && $0.recordID == userMessage.id })
        XCTAssertTrue(tombstones.contains { $0.recordKind == RecordKind.message && $0.recordID == assistantMessage.id })
        XCTAssertTrue(tombstones.contains { $0.recordKind == RecordKind.attachment && $0.recordID == attachment.id })
        XCTAssertTrue(try result.load(MessageRecord.self, kind: RecordKind.message).isEmpty)
        XCTAssertTrue(try result.load(AttachmentRecord.self, kind: RecordKind.attachment).isEmpty)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: workspace.appendingPathComponent("attachments", isDirectory: true).path).isEmpty)

        let keptChild = try XCTUnwrap(result.load(ConversationRecord.self, kind: RecordKind.conversation).first(where: { $0.id == child.id }))
        XCTAssertEqual(keptChild.parentConversationID, primary.id)
        let keptGoal = try XCTUnwrap(result.load(GoalRecord.self, kind: RecordKind.goal).first(where: { $0.id == goal.id }))
        XCTAssertEqual(keptGoal.conversationID, primary.id)
        XCTAssertNil(keptGoal.sourceMessageID)
        XCTAssertNil(keptGoal.sourceText)
        let keptArtifact = try XCTUnwrap(result.load(ArtifactRecord.self, kind: RecordKind.artifact).first(where: { $0.id == artifact.id }))
        XCTAssertEqual(keptArtifact.conversationID, primary.id)
        XCTAssertNil(keptArtifact.sourceMessageIDs)
        XCTAssertNil(keptArtifact.travelPlanVariants?.first?.sourceMessageIDs)
        XCTAssertEqual(try result.load(ActivityRecord.self, kind: RecordKind.task).first?.conversationID, primary.id)
        XCTAssertEqual(try result.load(ActivityOperationRecord.self, kind: RecordKind.activityOperation).first, operation)
        XCTAssertEqual(try result.load(TaskExecutionRecord.self, kind: RecordKind.executionTask).first?.conversationID, primary.id)
        XCTAssertEqual(try result.load(MemoryClaimRecord.self, kind: RecordKind.memoryClaim), [memory])
    }

    @MainActor
    func testSideChatWithRunningWorkCannotBeDeleted() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("OpenMuseKeepRunningSideChat-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let workspace = directory.appendingPathComponent("workspace", isDirectory: true)
        let databasePath = directory.appendingPathComponent("OpenMuse.sqlite")
        let store = try SQLiteStore(path: databasePath)
        let primary = ConversationRecord(id: "running-delete-primary", title: "主聊", isPrimary: true, isArchived: false)
        let side = ConversationRecord(id: "running-delete-side", title: "正在执行", parentConversationID: primary.id)
        let message = MessageRecord(id: "running-delete-message", conversationID: side.id, role: .user, content: "继续处理。")
        let activity = ActivityRecord(id: "running-delete-activity", conversationID: side.id, title: "执行中", stage: "正在处理")
        try store.save(primary, kind: RecordKind.conversation, id: primary.id)
        try store.save(side, kind: RecordKind.conversation, id: side.id)
        try store.save(message, kind: RecordKind.message, id: message.id)
        try store.save(activity, kind: RecordKind.task, id: activity.id)

        let model = OpenMuseAppModel(
            runtimeOverride: nil,
            workspaceRootOverride: workspace,
            configurationOverride: ModelConfiguration(),
            startMacBridge: false
        )

        XCTAssertFalse(model.deleteSideConversation(id: side.id))
        XCTAssertTrue(model.conversations.contains(where: { $0.id == side.id }))
        XCTAssertEqual(try store.load(MessageRecord.self, kind: RecordKind.message).first?.id, message.id)
        XCTAssertTrue(model.statusText?.contains("正在进行") == true)
    }

    @MainActor
    func testDeletingSideChatAboveLegacyTombstoneLimitIsAtomic() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("OpenMuseDeleteLargeSideChat-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let workspace = directory.appendingPathComponent("workspace", isDirectory: true)
        let databasePath = directory.appendingPathComponent("OpenMuse.sqlite")
        let store = try SQLiteStore(path: databasePath)
        let primary = ConversationRecord(id: "large-delete-primary", title: "主聊", isPrimary: true, isArchived: false)
        let side = ConversationRecord(id: "large-delete-side", title: "长旁聊", parentConversationID: primary.id)
        try store.save(primary, kind: RecordKind.conversation, id: primary.id)
        try store.save(side, kind: RecordKind.conversation, id: side.id)
        for index in 0..<501 {
            let message = MessageRecord(
                id: "large-delete-message-\(index)", conversationID: side.id,
                role: index.isMultiple(of: 2) ? .user : .assistant, content: "消息 \(index)"
            )
            try store.save(message, kind: RecordKind.message, id: message.id)
        }

        let model = OpenMuseAppModel(
            runtimeOverride: nil,
            workspaceRootOverride: workspace,
            configurationOverride: ModelConfiguration(),
            startMacBridge: false
        )

        XCTAssertTrue(model.deleteSideConversation(id: side.id))
        XCTAssertFalse(model.conversations.contains(where: { $0.id == side.id }))
        let result = try SQLiteStore(path: databasePath)
        let tombstones = try result.load(DeletionTombstoneRecord.self, kind: RecordKind.deletionTombstone)
        XCTAssertEqual(tombstones.filter { $0.recordKind == RecordKind.message }.count, 501)
        XCTAssertTrue(tombstones.contains { $0.recordKind == RecordKind.conversation && $0.recordID == side.id })
        XCTAssertTrue(try result.load(MessageRecord.self, kind: RecordKind.message).isEmpty)
    }
}
