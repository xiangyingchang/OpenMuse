import ActivityKit
import AlarmKit
import Foundation
import OpenMuseCore
import SwiftUI

private struct OpenMuseAlarmMetadata: AlarmMetadata {
    let label: String
}

private struct OpenMuseStoredAlarm: Codable {
    let label: String
    let kind: String
    let scheduledAt: Date?
    let repeatWeekdays: [Int]?
    let createdAt: Date
}

private struct OpenMuseAlarmKitFailure: LocalizedError {
    let stage: String
    let underlying: Error

    var errorDescription: String? {
        let error = underlying as NSError
        return "AlarmKit 在\(stage)失败（\(error.domain)，代码 \(error.code)）：\(underlying.localizedDescription)"
    }
}

/// iSH native offload for system alarms. iOS AlarmKit authorization is the
/// one-time permission boundary; OpenMuse adds no per-command approval.
@MainActor
enum IOSPhoneAlarmOffload {
    private static let storageKey = "org.openmuse.ios.alarmkit.records.v1"

    static func perform(arguments: [String]) async -> String {
        do {
            let command = try PhoneAlarmCommand.parse(arguments: arguments)
            try Task.checkCancellation()
            guard #available(iOS 26.0, *) else {
                return failure("本机闹钟需要 iOS 26 或更新版本；当前设备的目标提醒仍可使用。")
            }
            // A compatible iPad app can run in visionOS with an iOS-version
            // compatibility value of 26+, while AlarmKit is not loadable there.
            // Match OpenMinis' fail-closed runtime probe so entering Swift APIs
            // whose generic metadata references AlarmKit cannot crash the app.
            guard NSClassFromString("AKAlarmAuthorization") != nil else {
                return failure("当前 Apple 系统环境未提供 AlarmKit；没有创建闹钟或计时器。")
            }
            return try await perform(command)
        } catch is CancellationError {
            return failure("闹钟操作已取消。")
        } catch let error as OpenMuseAlarmKitFailure {
            return failure(error.localizedDescription)
        } catch {
            return failure(error.localizedDescription)
        }
    }

    @available(iOS 26.0, *)
    private static func perform(_ command: PhoneAlarmCommand) async throws -> String {
        let manager = AlarmManager.shared
        switch command {
        case .list:
            let alarms = try manager.alarms
            let ids = Set(alarms.map { $0.id.uuidString })
            let records = loadRecords().filter { ids.contains($0.key) }
            save(records)
            let items: [[String: Any]] = alarms.map { alarm in
                let record = records[alarm.id.uuidString]
                return [
                    "id": alarm.id.uuidString,
                    "label": record?.label ?? "OpenMuse 闹钟",
                    "kind": record?.kind ?? (alarm.countdownDuration == nil ? "alarm" : "timer"),
                    "state": stateName(alarm.state),
                    "schedule": scheduleDescription(alarm.schedule, fallback: record?.scheduledAt, weekdays: record?.repeatWeekdays)
                ]
            }
            return success(["action": "list", "alarms": items, "count": items.count])

        case .cancel(let requestedID):
            let alarms = try manager.alarms
            let selected: [Alarm]
            if let requestedID {
                guard let match = alarms.first(where: { $0.id == requestedID }) else {
                    return failure("没有找到 ID 为 \(requestedID.uuidString) 的本机闹钟。")
                }
                selected = [match]
            } else {
                selected = alarms
            }
            for alarm in selected { try manager.cancel(id: alarm.id) }
            var records = loadRecords()
            for alarm in selected { records.removeValue(forKey: alarm.id.uuidString) }
            save(records)
            return success([
                "action": "cancel",
                "cancelled": selected.count,
                "message": selected.isEmpty ? "当前没有待取消的 OpenMuse 闹钟。" : "已取消 \(selected.count) 个 OpenMuse 闹钟或计时器。"
            ])

        case .set(let date, let label):
            guard try await requestAuthorization(manager) else {
                return failure("你没有授权 OpenMuse 使用系统闹钟，因此没有创建闹钟。可以在 iPhone 设置中为 OpenMuse 开启闹钟权限后重试。")
            }
            try Task.checkCancellation()
            let id = UUID()
            let configuration = AlarmManager.AlarmConfiguration.alarm(
                schedule: .fixed(date),
                attributes: makeAttributes(label: label),
                sound: .default
            )
            do {
                _ = try await manager.schedule(id: id, configuration: configuration)
            } catch {
                throw OpenMuseAlarmKitFailure(stage: "注册一次性闹钟", underlying: error)
            }
            var records = loadRecords()
            records[id.uuidString] = OpenMuseStoredAlarm(label: label, kind: "alarm", scheduledAt: date, repeatWeekdays: nil, createdAt: .now)
            save(records)
            return success([
                "action": "set",
                "id": id.uuidString,
                "label": label,
                "scheduled_at": iso8601(date),
                "message": "已在 iPhone 设置闹钟「\(label)」，时间为 \(displayTime(date))。"
            ])

        case .repeatAlarm(let hour, let minute, let weekdays, let label):
            guard try await requestAuthorization(manager) else {
                return failure("你没有授权 OpenMuse 使用系统闹钟，因此没有创建闹钟。可以在 iPhone 设置中为 OpenMuse 开启闹钟权限后重试。")
            }
            try Task.checkCancellation()
            let repeatDays = weekdays.compactMap(weekday)
            guard repeatDays.count == weekdays.count, !repeatDays.isEmpty else {
                return failure("重复日期无效，闹钟没有创建。")
            }
            let id = UUID()
            let relative = Alarm.Schedule.Relative(
                time: .init(hour: hour, minute: minute),
                repeats: .weekly(repeatDays)
            )
            let configuration = AlarmManager.AlarmConfiguration.alarm(
                schedule: .relative(relative),
                attributes: makeAttributes(label: label),
                sound: .default
            )
            do {
                _ = try await manager.schedule(id: id, configuration: configuration)
            } catch {
                throw OpenMuseAlarmKitFailure(stage: "注册重复闹钟", underlying: error)
            }
            var records = loadRecords()
            records[id.uuidString] = OpenMuseStoredAlarm(label: label, kind: "alarm", scheduledAt: nil, repeatWeekdays: weekdays, createdAt: .now)
            save(records)
            return success([
                "action": "set",
                "id": id.uuidString,
                "label": label,
                "repeat_weekdays": weekdays,
                "time": String(format: "%02d:%02d", hour, minute),
                "message": "已在 iPhone 设置重复闹钟「\(label)」，本机时间 \(String(format: "%02d:%02d", hour, minute))。"
            ])

        case .timer(let seconds, let label):
            guard try await requestAuthorization(manager) else {
                return failure("你没有授权 OpenMuse 使用系统计时器，因此没有创建计时器。可以在 iPhone 设置中为 OpenMuse 开启闹钟权限后重试。")
            }
            try Task.checkCancellation()
            let id = UUID()
            let configuration = AlarmManager.AlarmConfiguration.timer(
                duration: TimeInterval(seconds),
                attributes: makeAttributes(label: label),
                sound: .default
            )
            do {
                _ = try await manager.schedule(id: id, configuration: configuration)
            } catch {
                throw OpenMuseAlarmKitFailure(stage: "注册计时器", underlying: error)
            }
            var records = loadRecords()
            records[id.uuidString] = OpenMuseStoredAlarm(label: label, kind: "timer", scheduledAt: nil, repeatWeekdays: nil, createdAt: .now)
            save(records)
            return success([
                "action": "timer",
                "id": id.uuidString,
                "label": label,
                "duration_seconds": seconds,
                "message": "已在 iPhone 启动「\(label)」计时器，时长 \(durationDescription(seconds))。"
            ])
        }
    }

    @available(iOS 26.0, *)
    private static func requestAuthorization(_ manager: AlarmManager) async throws -> Bool {
        if manager.authorizationState == .authorized { return true }
        let state: AlarmManager.AuthorizationState
        do {
            state = try await manager.requestAuthorization()
        } catch {
            throw OpenMuseAlarmKitFailure(stage: "请求系统闹钟授权", underlying: error)
        }
        return state == .authorized
    }

    @available(iOS 26.0, *)
    private static func makeAttributes(label: String) -> AlarmAttributes<OpenMuseAlarmMetadata> {
        let title = LocalizedStringResource(stringLiteral: label)
        let stop = AlarmButton(text: "停止", textColor: .white, systemImageName: "stop.fill")
        // Match OpenMinis' native offload: ordinary alarms use alert-only
        // presentation. Countdown/paused presentations require a widget extension.
        let presentation = AlarmPresentation(alert: .init(title: title, stopButton: stop))
        return AlarmAttributes(
            presentation: presentation,
            metadata: OpenMuseAlarmMetadata(label: label),
            tintColor: Color(red: 0.28, green: 0.48, blue: 0.96)
        )
    }

    @available(iOS 26.0, *)
    private static func weekday(_ value: Int) -> Locale.Weekday? {
        switch value {
        case 1: .sunday
        case 2: .monday
        case 3: .tuesday
        case 4: .wednesday
        case 5: .thursday
        case 6: .friday
        case 7: .saturday
        default: nil
        }
    }

    @available(iOS 26.0, *)
    private static func scheduleDescription(_ schedule: Alarm.Schedule?, fallback: Date?, weekdays: [Int]?) -> String {
        guard let schedule else { return fallback.map(iso8601) ?? "计时器" }
        switch schedule {
        case .fixed(let date): return iso8601(date)
        case .relative(let relative):
            let time = String(format: "%02d:%02d", relative.time.hour, relative.time.minute)
            let names = (weekdays ?? []).sorted().compactMap(weekdayName)
            return names.isEmpty ? "\(time)（重复）" : "\(time)（每\(names.joined(separator: "、"))）"
        @unknown default: return "未识别的闹钟计划"
        }
    }

    private static func weekdayName(_ value: Int) -> String? {
        switch value {
        case 1: "周日"
        case 2: "周一"
        case 3: "周二"
        case 4: "周三"
        case 5: "周四"
        case 6: "周五"
        case 7: "周六"
        default: nil
        }
    }

    @available(iOS 26.0, *)
    private static func stateName(_ state: Alarm.State) -> String {
        switch state {
        case .scheduled: "scheduled"
        case .countdown: "countdown"
        case .paused: "paused"
        case .alerting: "alerting"
        @unknown default: "unknown"
        }
    }

    private static func loadRecords() -> [String: OpenMuseStoredAlarm] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let records = try? JSONDecoder().decode([String: OpenMuseStoredAlarm].self, from: data) else { return [:] }
        return records
    }

    private static func save(_ records: [String: OpenMuseStoredAlarm]) {
        guard let data = try? JSONEncoder().encode(records) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private static func success(_ fields: [String: Any]) -> String {
        encode(["success": true].merging(fields) { _, new in new })
    }

    private static func failure(_ message: String) -> String {
        encode(["success": false, "error": String(message.prefix(1_500))])
    }

    private static func encode(_ value: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes]) else {
            return #"{\"success\":false,\"error\":\"无法编码闹钟操作结果。\"}"#
        }
        return String(decoding: data, as: UTF8.self)
    }

    private static func iso8601(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private static func displayTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy年M月d日 HH:mm"
        return formatter.string(from: date)
    }

    private static func durationDescription(_ seconds: Int) -> String {
        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60
        let remainder = seconds % 60
        var parts: [String] = []
        if hours > 0 { parts.append("\(hours) 小时") }
        if minutes > 0 { parts.append("\(minutes) 分钟") }
        if remainder > 0 { parts.append("\(remainder) 秒") }
        return parts.joined()
    }
}
