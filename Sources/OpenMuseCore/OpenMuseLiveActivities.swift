import Foundation

public enum OpenMuseLiveActivityPhase: String, Codable, CaseIterable, Hashable, Sendable {
    case preparing
    case readingContext
    case replying
    case processing
    case saving
    case remoteMac
    case awaitingConfirmation
    case waitingForApp
    case completed
    case failed
    case stopped

    public var title: String {
        switch self {
        case .preparing: "正在开始"
        case .readingContext: "正在查看相关资料"
        case .replying: "正在组织回复"
        case .processing: "正在处理任务"
        case .saving: "正在整理结果"
        case .remoteMac: "家里的 Mac 正在处理"
        case .awaitingConfirmation: "等待你的确认"
        case .waitingForApp: "等待任务结果"
        case .completed: "已完成"
        case .failed: "遇到问题"
        case .stopped: "已停止"
        }
    }

    public var compactTitle: String {
        switch self {
        case .preparing: "开始中"
        case .readingContext: "读资料"
        case .replying: "回复中"
        case .processing: "处理中"
        case .saving: "整理中"
        case .remoteMac: "电脑处理中"
        case .awaitingConfirmation: "待确认"
        case .waitingForApp: "等待中"
        case .completed: "已完成"
        case .failed: "有问题"
        case .stopped: "已停止"
        }
    }

    public static func current(stage: String, status: String = "running") -> Self {
        switch status {
        case "completed": return .completed
        case "failed": return .failed
        case "cancelled", "rejected", "denied": return .stopped
        case "waiting_approval": return .awaitingConfirmation
        default: break
        }

        if stage.localizedCaseInsensitiveContains("确认") || stage.localizedCaseInsensitiveContains("批准") {
            return .awaitingConfirmation
        }
        if stage.localizedCaseInsensitiveContains("等待") || stage.localizedCaseInsensitiveContains("暂停") {
            return .waitingForApp
        }
        if stage.localizedCaseInsensitiveContains("Mac") || stage.localizedCaseInsensitiveContains("电脑") {
            return .remoteMac
        }
        if stage.localizedCaseInsensitiveContains("资料") || stage.localizedCaseInsensitiveContains("读取") || stage.localizedCaseInsensitiveContains("查看") {
            return .readingContext
        }
        if stage.localizedCaseInsensitiveContains("保存") || stage.localizedCaseInsensitiveContains("整理") {
            return .saving
        }
        if stage.localizedCaseInsensitiveContains("回复") || stage.localizedCaseInsensitiveContains("生成") || stage.localizedCaseInsensitiveContains("理解") {
            return .replying
        }
        if stage.localizedCaseInsensitiveContains("开始") { return .preparing }
        return .processing
    }
}

#if os(iOS)
import ActivityKit

@available(iOS 17.0, *)
public struct OpenMuseTaskActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var phase: OpenMuseLiveActivityPhase
        public var updatedAt: Date

        public init(phase: OpenMuseLiveActivityPhase, updatedAt: Date = .now) {
            self.phase = phase
            self.updatedAt = updatedAt
        }
    }

    /// An internal task identifier only. User prompts and conversation titles never leave the app.
    public var taskID: String

    public init(taskID: String) {
        self.taskID = taskID
    }
}

@available(iOS 17.0, *)
@MainActor
public final class OpenMuseLiveActivityController {
    public static let shared = OpenMuseLiveActivityController()

    private var activeActivity: Activity<OpenMuseTaskActivityAttributes>?
    private var activeTaskID: String?
    private var queuedOperation: Task<Void, Never>?

    private init() {}

    public func start(activityID: String, phase: OpenMuseLiveActivityPhase) {
        enqueue { [weak self] in await self?.startNow(activityID: activityID, phase: phase) }
    }

    public func update(activityID: String, phase: OpenMuseLiveActivityPhase) {
        enqueue { [weak self] in await self?.updateNow(activityID: activityID, phase: phase) }
    }

    public func finish(activityID: String, status: String, stage: String) {
        let phase = OpenMuseLiveActivityPhase.current(stage: stage, status: status)
        enqueue { [weak self] in await self?.finishNow(activityID: activityID, status: status, phase: phase) }
    }

    private func enqueue(_ operation: @escaping @MainActor () async -> Void) {
        let previous = queuedOperation
        queuedOperation = Task { @MainActor in
            await previous?.value
            await operation()
        }
    }

    private func startNow(activityID: String, phase: OpenMuseLiveActivityPhase) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        if let existing = Activity<OpenMuseTaskActivityAttributes>.activities.first(where: { $0.attributes.taskID == activityID }) {
            activeActivity = existing
            activeTaskID = activityID
            await existing.update(content(for: phase))
            return
        }

        for previous in Activity<OpenMuseTaskActivityAttributes>.activities {
            await previous.end(nil, dismissalPolicy: .immediate)
        }
        do {
            let activity = try Activity.request(
                attributes: OpenMuseTaskActivityAttributes(taskID: activityID),
                content: content(for: phase),
                pushType: nil
            )
            activeActivity = activity
            activeTaskID = activityID
        } catch {
            // The task remains fully available in OpenMuse's activity history when Live Activities are disabled.
        }
    }

    private func updateNow(activityID: String, phase: OpenMuseLiveActivityPhase) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let activity = activeActivity ?? Activity<OpenMuseTaskActivityAttributes>.activities.first(where: { $0.attributes.taskID == activityID })
        guard activeTaskID == nil || activeTaskID == activityID,
              let activity, activity.attributes.taskID == activityID else { return }
        activeActivity = activity
        activeTaskID = activityID
        await activity.update(content(for: phase))
    }

    private func finishNow(activityID: String, status: String, phase: OpenMuseLiveActivityPhase) async {
        let activity = activeActivity ?? Activity<OpenMuseTaskActivityAttributes>.activities.first(where: { $0.attributes.taskID == activityID })
        guard activeTaskID == nil || activeTaskID == activityID,
              let activity, activity.attributes.taskID == activityID else { return }
        if ["completed", "failed", "cancelled", "rejected", "denied"].contains(status) {
            await activity.end(content(for: phase), dismissalPolicy: .after(.now.addingTimeInterval(5)))
            activeActivity = nil
            activeTaskID = nil
        } else {
            activeActivity = activity
            activeTaskID = activityID
            await activity.update(content(for: phase))
        }
    }

    private func content(for phase: OpenMuseLiveActivityPhase) -> ActivityContent<OpenMuseTaskActivityAttributes.ContentState> {
        ActivityContent(
            state: .init(phase: phase),
            staleDate: .now.addingTimeInterval(5 * 60)
        )
    }
}
#endif
