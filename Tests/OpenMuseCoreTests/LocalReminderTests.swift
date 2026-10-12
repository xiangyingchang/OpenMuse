import Foundation
import XCTest
@testable import OpenMuseCore

@MainActor
final class LocalReminderTests: XCTestCase {
    func testGoalReminderPersistsSyncableStateAndCanPauseResumeAndCancel() async throws {
        let (directory, workspace, conversation, goal) = try makeWorkspaceWithGoal()
        defer { try? FileManager.default.removeItem(at: directory) }
        let scheduler = ReminderSchedulerSpy()
        let model = OpenMuseAppModel(
            runtimeOverride: nil,
            workspaceRootOverride: workspace,
            configurationOverride: ModelConfiguration(),
            startMacBridge: false,
            reminderScheduler: scheduler
        )

        let dueAt = Date.now.addingTimeInterval(3_600)
        await model.scheduleGoalReminder(goalID: goal.id, dueAt: dueAt)

        let reminder = try XCTUnwrap(model.schedules.first)
        let persistedStore = try SQLiteStore(path: directory.appendingPathComponent("OpenMuse.sqlite"))
        XCTAssertEqual(reminder.goalID, goal.id)
        XCTAssertEqual(reminder.ownerDeviceID, persistedStore.deviceID)
        XCTAssertEqual(reminder.status, "scheduled")
        XCTAssertEqual(reminder.notificationStatus, "scheduled")
        XCTAssertEqual(scheduler.scheduled.map(\.id), [reminder.id])
        XCTAssertEqual(try persistedStore.pendingSyncEvents().last?.kind, RecordKind.schedule)

        await model.setScheduleStatus(id: reminder.id, status: "paused")
        XCTAssertEqual(model.schedules.first?.status, "paused")
        XCTAssertEqual(scheduler.removed, [reminder.id])

        await model.setScheduleStatus(id: reminder.id, status: "scheduled")
        XCTAssertEqual(model.schedules.first?.status, "scheduled")
        XCTAssertEqual(scheduler.scheduled.map(\.id), [reminder.id, reminder.id])

        await model.setScheduleStatus(id: reminder.id, status: "cancelled")
        XCTAssertEqual(model.schedules.first?.status, "cancelled")
        XCTAssertEqual(scheduler.removed, [reminder.id, reminder.id])
        XCTAssertEqual(model.conversations.first?.id, conversation.id)
    }

    func testPastReminderWaitsForAppOpenAndNeverCallsTheModel() async throws {
        let (directory, workspace, _, goal) = try makeWorkspaceWithGoal()
        defer { try? FileManager.default.removeItem(at: directory) }
        let scheduler = ReminderSchedulerSpy()
        let model = OpenMuseAppModel(
            runtimeOverride: nil,
            workspaceRootOverride: workspace,
            configurationOverride: ModelConfiguration(),
            startMacBridge: false,
            reminderScheduler: scheduler
        )

        await model.scheduleGoalReminder(goalID: goal.id, dueAt: Date.now.addingTimeInterval(-60))

        let reminder = try XCTUnwrap(model.schedules.first)
        XCTAssertEqual(reminder.status, "due")
        XCTAssertEqual(reminder.notificationStatus, "due-on-open")
        XCTAssertTrue(scheduler.scheduled.isEmpty)
        XCTAssertEqual(model.activities.count, 0)

        model.presentedSheet = .companion
        model.continueGoalFromReminder(id: reminder.id)
        XCTAssertEqual(model.selectedSection, .chat)
        XCTAssertNil(model.presentedSheet)
        XCTAssertTrue(model.draft.contains(goal.title))
        XCTAssertTrue(model.statusText?.contains("不会自动发送") == true)
    }

    private func makeWorkspaceWithGoal() throws -> (URL, URL, ConversationRecord, GoalRecord) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("OpenMuseReminder-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let workspace = directory.appendingPathComponent("workspace", isDirectory: true)
        let store = try SQLiteStore(path: directory.appendingPathComponent("OpenMuse.sqlite"))
        let conversation = ConversationRecord(title: "旅行计划")
        let goal = GoalRecord(conversationID: conversation.id, title: "恩施七日旅行", summary: "准备路线", steps: [GoalStep(title: "确定时间")])
        try store.save(conversation, kind: RecordKind.conversation, id: conversation.id)
        try store.save(goal, kind: RecordKind.goal, id: goal.id, appendRevision: true)
        return (directory, workspace, conversation, goal)
    }
}

@MainActor
private final class ReminderSchedulerSpy: LocalReminderScheduling {
    var scheduled: [ScheduleRecord] = []
    var removed: [String] = []
    var result = "scheduled"

    func schedule(_ reminder: ScheduleRecord) async -> String {
        scheduled.append(reminder)
        return result
    }

    func remove(id: String) async {
        removed.append(id)
    }
}
