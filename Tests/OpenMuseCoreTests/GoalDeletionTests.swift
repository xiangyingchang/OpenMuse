import Foundation
import XCTest
@testable import OpenMuseCore

@MainActor
final class GoalDeletionTests: XCTestCase {
    func testGoalDeletionToolRequiresAnExplicitCurrentUserInstruction() {
        XCTAssertTrue(GoalDeletionIntentPolicy.allowsDeletion(in: [TranscriptMessage(role: "user", content: "不需要重复的目标，删除一个")]))
        XCTAssertTrue(GoalDeletionIntentPolicy.allowsDeletion(in: [TranscriptMessage(role: "user", content: "帮我把这个目标删掉")]))
        XCTAssertFalse(GoalDeletionIntentPolicy.allowsDeletion(in: [TranscriptMessage(role: "user", content: "为什么你没有删除目标的工具？")]))
        XCTAssertFalse(GoalDeletionIntentPolicy.allowsDeletion(in: [TranscriptMessage(role: "user", content: "不要删除目标")]))
        XCTAssertFalse(GoalDeletionIntentPolicy.allowsDeletion(in: [TranscriptMessage(role: "user", content: "我不是让你删除目标")]))
        XCTAssertFalse(GoalDeletionIntentPolicy.allowsDeletion(in: [TranscriptMessage(role: "user", content: "我希望以后有删除目标的功能")]))
        XCTAssertTrue(GoalDeletionIntentPolicy.allowsDeletion(in: [TranscriptMessage(role: "user", content: "我想删除这个重复目标")]))
        XCTAssertFalse(GoalDeletionIntentPolicy.allowsDeletion(in: [TranscriptMessage(role: "user", content: "怎么删除目标？")]))
        XCTAssertFalse(GoalDeletionIntentPolicy.allowsDeletion(in: [
            TranscriptMessage(role: "user", content: "帮我删除目标"),
            TranscriptMessage(role: "assistant", content: "我已经删除了。"),
            TranscriptMessage(role: "user", content: "为什么？")
        ]))
    }

    func testDeleteGoalRemovesRelatedTrackingAndRemindersButKeepsChatAndCompletedTask() async throws {
        let fixture = try GoalDeletionFixture()
        defer { try? FileManager.default.removeItem(at: fixture.container) }
        let seedStore = try SQLiteStore(path: fixture.container.appendingPathComponent("OpenMuse.sqlite"))
        let conversation = ConversationRecord(id: "goal-delete-chat", title: "主聊", isPrimary: true)
        try seedStore.save(conversation, kind: RecordKind.conversation, id: conversation.id)
        let goal = GoalRecord(
            id: "inferred-duplicate", conversationID: conversation.id, title: "恩施七日旅行",
            summary: "从聊天里推测的旅行目标", sourceMessageID: "goal-delete-source", sourceText: "想去恩施旅行",
            confidence: 0.45, steps: [GoalStep(title: "安排路线")]
        )
        let otherGoal = GoalRecord(
            id: "explicit-goal", conversationID: conversation.id, title: "恩施七日旅行",
            summary: "用户明确提出的旅行计划", sourceMessageID: "explicit-source", sourceText: "帮我规划恩施七日旅行",
            confidence: 1, steps: [GoalStep(title: "确定日期")]
        )
        try seedStore.save(goal, kind: RecordKind.goal, id: goal.id, revision: 1, appendRevision: true)
        try seedStore.save(otherGoal, kind: RecordKind.goal, id: otherGoal.id, revision: 1, appendRevision: true)
        let message = MessageRecord(id: "goal-delete-message", conversationID: conversation.id, role: .user, content: "请删掉推断出的重复目标。")
        try seedStore.save(message, kind: RecordKind.message, id: message.id)
        let reminder = ScheduleRecord(id: "goal-delete-reminder", goalID: goal.id, title: goal.title, dueAt: .now.addingTimeInterval(3_600), ownerDeviceID: seedStore.deviceID)
        try seedStore.save(reminder, kind: RecordKind.schedule, id: reminder.id)
        let event = GoalProgressEventRecord(goalID: goal.id, sourceMessageID: message.id, action: "step-completed", stepID: goal.steps[0].id)
        try seedStore.save(event, kind: RecordKind.goalProgressEvent, id: event.id)
        let feedback = IdeaFeedbackRecord(goalID: goal.id, action: "later")
        try seedStore.save(feedback, kind: RecordKind.ideaFeedback, id: feedback.id)
        let task = TaskExecutionRecord(id: "completed-goal-task", goalID: goal.id, conversationID: conversation.id, status: "completed", runEpoch: 1, ownerDeviceID: seedStore.deviceID)
        try seedStore.save(task, kind: RecordKind.executionTask, id: task.id, revision: 1, appendRevision: true)

        let scheduler = GoalDeletionReminderScheduler()
        let model = OpenMuseAppModel(
            runtimeOverride: nil,
            workspaceRootOverride: fixture.container.appendingPathComponent("workspace", isDirectory: true),
            configurationOverride: nil,
            startMacBridge: false,
            reminderScheduler: scheduler
        )

        let deleted = await model.deleteGoal(id: goal.id)
        XCTAssertTrue(deleted)
        XCTAssertEqual(model.goals.map(\.id), [otherGoal.id])
        XCTAssertTrue(model.schedules.isEmpty)
        XCTAssertTrue(model.goalProgressEvents.isEmpty)
        XCTAssertTrue(model.ideaFeedback.isEmpty)
        XCTAssertEqual(model.messages.map(\.id), [message.id])
        XCTAssertNil(model.executionTasks.first(where: { $0.id == task.id })?.goalID)
        let removedIDs = scheduler.removedIDs
        XCTAssertEqual(removedIDs, [reminder.id])

        let verifyStore = try SQLiteStore(path: fixture.container.appendingPathComponent("OpenMuse.sqlite"))
        XCTAssertTrue(try verifyStore.load(GoalRecord.self, kind: RecordKind.goal).contains(where: { $0.id == otherGoal.id }))
        XCTAssertFalse(try verifyStore.load(GoalRecord.self, kind: RecordKind.goal).contains(where: { $0.id == goal.id }))
        XCTAssertTrue(try verifyStore.load(DeletionTombstoneRecord.self, kind: RecordKind.deletionTombstone).contains {
            $0.recordKind == RecordKind.goal && $0.recordID == goal.id
        })
        XCTAssertEqual(try verifyStore.load(TaskExecutionRecord.self, kind: RecordKind.executionTask).first?.goalID, nil)
        XCTAssertFalse(try verifyStore.load(MessageRecord.self, kind: RecordKind.message).isEmpty)
    }

    func testDeletingGoalIsBlockedWhileAnAssociatedTaskIsActive() async throws {
        let fixture = try GoalDeletionFixture()
        defer { try? FileManager.default.removeItem(at: fixture.container) }
        let store = try SQLiteStore(path: fixture.container.appendingPathComponent("OpenMuse.sqlite"))
        let conversation = ConversationRecord(id: "active-goal-chat", title: "主聊", isPrimary: true)
        try store.save(conversation, kind: RecordKind.conversation, id: conversation.id)
        let goal = GoalRecord(id: "active-goal", conversationID: conversation.id, title: "旅行", summary: "", steps: [])
        try store.save(goal, kind: RecordKind.goal, id: goal.id, revision: 1, appendRevision: true)
        let task = TaskExecutionRecord(id: "waiting-goal-task", goalID: goal.id, conversationID: conversation.id)
        try store.save(task, kind: RecordKind.executionTask, id: task.id, revision: 1, appendRevision: true)
        let model = OpenMuseAppModel(
            runtimeOverride: nil,
            workspaceRootOverride: fixture.container.appendingPathComponent("workspace", isDirectory: true),
            configurationOverride: nil,
            startMacBridge: false
        )

        let deleted = await model.deleteGoal(id: goal.id)
        XCTAssertFalse(deleted)
        XCTAssertEqual(model.goals.map(\.id), [goal.id])
        XCTAssertTrue(model.statusText?.contains("仍有关联任务") == true)
    }

    func testExplicitChatRequestInvokesDeletionToolForInferredDuplicate() async throws {
        let fixture = try GoalDeletionFixture()
        defer { try? FileManager.default.removeItem(at: fixture.container) }
        let store = try SQLiteStore(path: fixture.container.appendingPathComponent("OpenMuse.sqlite"))
        let conversation = ConversationRecord(id: "goal-tool-chat", title: "主聊", isPrimary: true)
        try store.save(conversation, kind: RecordKind.conversation, id: conversation.id)
        let inferred = GoalRecord(id: "goal-tool-inferred", conversationID: conversation.id, title: "旅行", summary: "推测记录", confidence: 0.4, steps: [])
        let explicit = GoalRecord(id: "goal-tool-explicit", conversationID: conversation.id, title: "旅行", summary: "明确记录", confidence: 1, steps: [])
        try store.save(inferred, kind: RecordKind.goal, id: inferred.id, revision: 1, appendRevision: true)
        try store.save(explicit, kind: RecordKind.goal, id: explicit.id, revision: 1, appendRevision: true)
        let configuration = ModelConfiguration(provider: .custom, endpoint: "https://goal-delete.example/v1", model: "fixture", supportsToolCalling: true)
        try SecureStore.saveAPIKey("goal-delete-test-key", for: configuration)
        defer { try? SecureStore.deleteAPIKey(for: configuration) }
        let runtime = GoalDeleteToolRuntime()
        let model = OpenMuseAppModel(
            runtimeOverride: runtime,
            workspaceRootOverride: fixture.container.appendingPathComponent("workspace", isDirectory: true),
            configurationOverride: configuration,
            startMacBridge: false
        )

        await model.send("不需要重复的目标，删除一个")

        XCTAssertEqual(model.goals.map(\.id), [explicit.id])
        let result = await runtime.recorder.snapshot()
        XCTAssertTrue(result.tools.contains("openmuse_phone_delete_goal"))
        XCTAssertEqual(result.deletedGoalID, inferred.id)
        XCTAssertTrue(result.output.contains("\"deleted\":true"))
    }
}

private struct GoalDeletionFixture {
    let container: URL

    init() throws {
        container = FileManager.default.temporaryDirectory.appendingPathComponent("OpenMuseGoalDeletion-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
    }
}

@MainActor
private final class GoalDeletionReminderScheduler: LocalReminderScheduling {
    private(set) var removedIDs: [String] = []

    func schedule(_ reminder: ScheduleRecord) async -> String { "scheduled" }
    func remove(id: String) async { removedIDs.append(id) }
}

private struct GoalDeleteToolRuntime: ToolCallingModelRuntime {
    let recorder = GoalDeleteToolRecorder()

    func reply(systemPrompt: String, messages: [TranscriptMessage], configuration: ModelConfiguration, apiKey: String) async throws -> String {
        "This fixture expects function calls."
    }

    func replyWithTools(
        systemPrompt: String,
        messages: [TranscriptMessage],
        configuration: ModelConfiguration,
        apiKey: String,
        tools: [ModelToolDefinition],
        execute: @escaping @Sendable (ModelToolInvocation) async throws -> String,
        onDelta: @escaping @Sendable (String) async -> Void,
        onToolEvent: @escaping @Sendable (ModelToolExecutionEvent) async -> Void
    ) async throws -> ModelRuntimeReply {
        await recorder.setTools(tools.map(\.name))
        let list = ModelToolInvocation(id: "goal-list", name: "openmuse_phone_list_goals", argumentsJSON: "{}")
        await onToolEvent(ModelToolExecutionEvent(toolCallID: list.id, toolName: list.name, relativePath: nil, status: "started"))
        let output = try await execute(list)
        await onToolEvent(ModelToolExecutionEvent(toolCallID: list.id, toolName: list.name, relativePath: nil, status: "completed", outputText: output))
        guard tools.contains(where: { $0.name == "openmuse_phone_delete_goal" }),
              let data = output.data(using: .utf8),
              let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let goals = payload["goals"] as? [[String: Any]],
              let inferred = goals.first(where: { ($0["provenance"] as? String) == "从对话推断" }),
              let goalID = inferred["goal_id"] as? String else {
            throw ModelRuntimeError.server("本轮没有明确授权删除工具，或目标来源无法区分。")
        }
        let deletion = ModelToolInvocation(
            id: "goal-delete",
            name: "openmuse_phone_delete_goal",
            argumentsJSON: try String(decoding: JSONSerialization.data(withJSONObject: ["goal_id": goalID]), as: UTF8.self)
        )
        await onToolEvent(ModelToolExecutionEvent(toolCallID: deletion.id, toolName: deletion.name, relativePath: nil, status: "started", inputJSON: deletion.argumentsJSON))
        let deleted = try await execute(deletion)
        await recorder.setDeletedGoal(goalID, output: deleted)
        await onToolEvent(ModelToolExecutionEvent(toolCallID: deletion.id, toolName: deletion.name, relativePath: nil, status: "completed", inputJSON: deletion.argumentsJSON, outputText: deleted))
        let text = "已删除重复的推断目标；你明确提出的目标和聊天记录仍保留。"
        await onDelta(text)
        return ModelRuntimeReply(text: text)
    }
}

private actor GoalDeleteToolRecorder {
    private var tools: [String] = []
    private var deletedGoalID: String?
    private var output = ""

    func setTools(_ tools: [String]) { self.tools = tools }
    func setDeletedGoal(_ id: String, output: String) {
        deletedGoalID = id
        self.output = output
    }
    func snapshot() -> (tools: [String], deletedGoalID: String?, output: String) {
        (tools, deletedGoalID, output)
    }
}
