import Foundation
import XCTest
@testable import OpenMuseCore

final class MaintenanceResourcePolicyTests: XCTestCase {
    func testScheduledWorkPausesInLowPowerOrSeriousThermalState() {
        XCTAssertEqual(
            MaintenanceResourcePolicy.pauseReason(isScheduled: true, lowPowerMode: true, thermalState: .nominal),
            "设备处于低电量模式，已暂停自动回顾。"
        )
        XCTAssertEqual(
            MaintenanceResourcePolicy.pauseReason(isScheduled: true, lowPowerMode: false, thermalState: .serious),
            "设备温度较高，已暂停自动回顾。"
        )
        XCTAssertEqual(
            MaintenanceResourcePolicy.pauseReason(isScheduled: true, lowPowerMode: false, thermalState: .critical),
            "设备温度较高，已暂停自动回顾。"
        )
    }

    func testUserStartedWorkIsNotSilentlyBlockedByResourcePolicy() {
        XCTAssertNil(MaintenanceResourcePolicy.pauseReason(isScheduled: false, lowPowerMode: true, thermalState: .critical))
        XCTAssertNil(MaintenanceResourcePolicy.pauseReason(isScheduled: true, lowPowerMode: false, thermalState: .nominal))
    }

    func testAutomaticRequestBudgetReservesInputAndMaximumOutputBeforeSending() {
        let plan = MaintenancePreferences(maximumRequestsPerDay: 2, maximumTokensPerDay: 2_000)
        XCTAssertTrue(MaintenanceResourcePolicy.canReserveAutomaticRequest(plan: plan, requestsUsed: 1, tokensReserved: 900, additionalTokens: 1_100))
        XCTAssertFalse(MaintenanceResourcePolicy.canReserveAutomaticRequest(plan: plan, requestsUsed: 2, tokensReserved: 0, additionalTokens: 100))
        XCTAssertFalse(MaintenanceResourcePolicy.canReserveAutomaticRequest(plan: plan, requestsUsed: 1, tokensReserved: 1_000, additionalTokens: 1_001))
        let reservation = MaintenanceResourcePolicy.requestReservation(
            prompt: [TranscriptMessage(role: "user", content: "恩施旅行计划")], outputTokens: 900
        )
        XCTAssertEqual(reservation, ("恩施旅行计划".utf8.count + 2) / 3 + 900)
    }

    func testHeartbeatPlanUsesItsTimeZoneAndSkipPolicyHasOneHourWindow() throws {
        let plan = MaintenancePreferences(
            enabled: true, quietHoursStart: 22, quietHoursEnd: 8,
            timeZoneIdentifier: "Asia/Shanghai", missedRunPolicy: "skip"
        )
        let formatter = ISO8601DateFormatter()
        let due = try XCTUnwrap(formatter.date(from: "2026-10-10T00:00:00Z")) // 08:00 in Shanghai
        XCTAssertTrue(plan.permitsMissedRun(at: due.addingTimeInterval(30 * 60)))
        XCTAssertFalse(plan.permitsMissedRun(at: due.addingTimeInterval(61 * 60)))
        XCTAssertTrue(plan.allowsRun(at: due.addingTimeInterval(30 * 60)))
        XCTAssertFalse(plan.allowsRun(at: due.addingTimeInterval(-30 * 60)))
    }

    func testLegacyMaintenancePreferencesDecodeWithSafeDefaults() throws {
        let data = Data(#"{"enabled":true,"quietHoursStart":21,"quietHoursEnd":7}"#.utf8)
        let plan = try JSONDecoder().decode(MaintenancePreferences.self, from: data)
        XCTAssertTrue(plan.enabled)
        XCTAssertEqual(plan.quietHoursStart, 21)
        XCTAssertEqual(plan.quietHoursEnd, 7)
        XCTAssertEqual(plan.maximumRequestsPerDay, 20)
        XCTAssertEqual(plan.maximumTokensPerDay, 20_000)
        XCTAssertEqual(plan.maximumOutputTokensPerRun, 900)
    }
}
