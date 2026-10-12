import Foundation

enum MaintenanceResourcePolicy {
    static func requestReservation(prompt: [TranscriptMessage], outputTokens: Int) -> Int {
        let inputBytes = prompt.reduce(0) { $0 + $1.content.utf8.count }
        // One token per three UTF-8 bytes is deliberately conservative for a mixed Chinese/English prompt.
        return max(1, (inputBytes + 2) / 3) + max(0, outputTokens)
    }

    static func canReserveAutomaticRequest(
        plan: MaintenancePreferences,
        requestsUsed: Int,
        tokensReserved: Int,
        additionalTokens: Int
    ) -> Bool {
        requestsUsed < plan.maximumRequestsPerDay &&
        tokensReserved >= 0 && additionalTokens >= 0 &&
        tokensReserved <= plan.maximumTokensPerDay - additionalTokens
    }

    static func usageDayStart(for date: Date, plan: MaintenancePreferences) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: plan.timeZoneIdentifier) ?? .current
        return calendar.startOfDay(for: date)
    }

    static func pauseReason(
        isScheduled: Bool,
        lowPowerMode: Bool,
        thermalState: ProcessInfo.ThermalState
    ) -> String? {
        guard isScheduled else { return nil }
        if lowPowerMode { return "设备处于低电量模式，已暂停自动回顾。" }
        if thermalState == .serious || thermalState == .critical {
            return "设备温度较高，已暂停自动回顾。"
        }
        return nil
    }

    static func currentPauseReason(isScheduled: Bool) -> String? {
        let process = ProcessInfo.processInfo
        return pauseReason(
            isScheduled: isScheduled,
            lowPowerMode: process.isLowPowerModeEnabled,
            thermalState: process.thermalState
        )
    }
}
