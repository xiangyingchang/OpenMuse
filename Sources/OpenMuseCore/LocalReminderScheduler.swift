import Foundation
import UserNotifications

@MainActor
protocol LocalReminderScheduling {
    func schedule(_ reminder: ScheduleRecord) async -> String
    func remove(id: String) async
}

@MainActor
final class SystemLocalReminderScheduler: LocalReminderScheduling {
    func schedule(_ reminder: ScheduleRecord) async -> String {
        guard reminder.dueAt.timeIntervalSinceNow > 1 else { return "due-on-open" }
        let center = UNUserNotificationCenter.current()
        var settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
            guard granted else { return "permission-denied" }
            settings = await center.notificationSettings()
        }
        let notificationsAllowed: Bool
        switch settings.authorizationStatus {
        case .authorized, .provisional:
            notificationsAllowed = true
        #if os(iOS)
        case .ephemeral:
            notificationsAllowed = true
        #endif
        default:
            notificationsAllowed = false
        }
        guard notificationsAllowed else {
            return "permission-denied"
        }

        let content = UNMutableNotificationContent()
        content.title = "一起看看这个目标"
        content.body = "到了约好的时间。打开 OpenMuse，确认这件事现在还重要吗。"
        content.sound = .default
        content.userInfo = ["openmuse.schedule.id": reminder.id]
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: reminder.timeZoneID) ?? .current
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: reminder.dueAt)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: reminder.id, content: content, trigger: trigger)
        do {
            try await center.add(request)
            return "scheduled"
        } catch {
            return "unavailable"
        }
    }

    func remove(id: String) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [id])
        center.removeDeliveredNotifications(withIdentifiers: [id])
    }
}
