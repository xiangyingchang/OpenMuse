import XCTest
@testable import OpenMuseCore

final class PhoneAlarmCommandTests: XCTestCase {
    private let shanghai = try! XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
    private let now = try! XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-12T08:15:00+08:00"))

    func testOneTimeClockTimeSelectsNextOccurrenceInDeviceTimeZone() throws {
        let command = try PhoneAlarmCommand.parse(
            arguments: ["set", "--time", "07:30", "--label", "起床"],
            now: now,
            timeZone: shanghai
        )
        let expected = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-13T07:30:00+08:00"))
        XCTAssertEqual(command, .set(time: expected, label: "起床"))
    }

    func testOneTimeISO8601PreservesExplicitOffset() throws {
        let command = try PhoneAlarmCommand.parse(
            arguments: ["set", "--time", "2026-10-13T07:30+08:00", "--label", "出发"],
            now: now,
            timeZone: shanghai
        )
        let expected = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-13T07:30:00+08:00"))
        XCTAssertEqual(command, .set(time: expected, label: "出发"))
    }

    func testOneTimeISO8601AcceptsOptionalSecondsWithExplicitOffset() throws {
        let command = try PhoneAlarmCommand.parse(
            arguments: ["set", "--time", "2026-10-13T07:30:45+08:00", "--label", "出发"],
            now: now,
            timeZone: shanghai
        )
        let expected = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-13T07:30:45+08:00"))
        XCTAssertEqual(command, .set(time: expected, label: "出发"))
    }

    func testOneTimeLocalISO8601AcceptsOptionalSeconds() throws {
        let command = try PhoneAlarmCommand.parse(
            arguments: ["set", "--time", "2026-10-13T07:30:45", "--label", "出发"],
            now: now,
            timeZone: shanghai
        )
        let expected = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-13T07:30:45+08:00"))
        XCTAssertEqual(command, .set(time: expected, label: "出发"))
    }

    func testOneTimeAlarmRejectsPastAndInvalidCalendarDate() {
        XCTAssertThrowsError(try PhoneAlarmCommand.parse(
            arguments: ["set", "--time", "2026-10-12T07:00+08:00"], now: now, timeZone: shanghai
        ))
        XCTAssertThrowsError(try PhoneAlarmCommand.parse(
            arguments: ["set", "--time", "2026-02-30T07:00"], now: now, timeZone: shanghai
        ))
    }

    func testRecurringAlarmMapsDailyWeekdaysAndWeekends() throws {
        XCTAssertEqual(
            try PhoneAlarmCommand.parse(arguments: ["set", "--time", "08:00", "--repeat", "daily"], now: now, timeZone: shanghai),
            .repeatAlarm(hour: 8, minute: 0, weekdays: [1, 2, 3, 4, 5, 6, 7], label: "OpenMuse 闹钟")
        )
        XCTAssertEqual(
            try PhoneAlarmCommand.parse(arguments: ["set", "--time", "08:00", "--repeat", "weekdays"], now: now, timeZone: shanghai),
            .repeatAlarm(hour: 8, minute: 0, weekdays: [2, 3, 4, 5, 6], label: "OpenMuse 闹钟")
        )
        XCTAssertEqual(
            try PhoneAlarmCommand.parse(arguments: ["set", "--time", "08:00", "--repeat", "weekends"], now: now, timeZone: shanghai),
            .repeatAlarm(hour: 8, minute: 0, weekdays: [1, 7], label: "OpenMuse 闹钟")
        )
        XCTAssertThrowsError(try PhoneAlarmCommand.parse(
            arguments: ["set", "--time", "2026-10-13T08:00+08:00", "--repeat", "daily"], now: now, timeZone: shanghai
        ))
    }

    func testTimerDurationParsingAndTwentyFourHourLimit() throws {
        XCTAssertEqual(try PhoneAlarmCommand.parse(arguments: ["timer", "--duration", "1h30m", "--label", "煮茶"]), .timer(seconds: 5_400, label: "煮茶"))
        XCTAssertEqual(try PhoneAlarmCommand.parse(arguments: ["timer", "--duration", "300"]), .timer(seconds: 300, label: "OpenMuse 计时器"))
        XCTAssertEqual(try PhoneAlarmCommand.parse(arguments: ["timer", "--duration", "24h"]), .timer(seconds: 86_400, label: "OpenMuse 计时器"))
        XCTAssertThrowsError(try PhoneAlarmCommand.parse(arguments: ["timer", "--duration", "24h1s"]))
        XCTAssertThrowsError(try PhoneAlarmCommand.parse(arguments: ["timer", "--duration", "1m1h"]))
        XCTAssertThrowsError(try PhoneAlarmCommand.parse(arguments: ["timer", "--duration", "999999999999h"]))
        XCTAssertThrowsError(try PhoneAlarmCommand.parse(arguments: ["timer", "--duration", "999999999999m"]))
        XCTAssertThrowsError(try PhoneAlarmCommand.parse(arguments: ["timer", "--duration", "0"]))
    }

    func testListAndCancelCommands() throws {
        let id = try XCTUnwrap(UUID(uuidString: "72C54555-4DA6-4E6C-8C6F-68A0C4E0E6E1"))
        XCTAssertEqual(try PhoneAlarmCommand.parse(arguments: ["list"]), .list)
        XCTAssertEqual(try PhoneAlarmCommand.parse(arguments: ["cancel", id.uuidString]), .cancel(id))
        XCTAssertEqual(try PhoneAlarmCommand.parse(arguments: ["cancel", "all"]), .cancel(nil))
        XCTAssertThrowsError(try PhoneAlarmCommand.parse(arguments: ["cancel", "bad-id"]))
    }

    func testMalformedArgumentsAreRejected() {
        XCTAssertThrowsError(try PhoneAlarmCommand.parse(arguments: ["set", "--time", "25:99"]))
        XCTAssertThrowsError(try PhoneAlarmCommand.parse(arguments: ["set", "--time", "07:00", "--time", "08:00"]))
        XCTAssertThrowsError(try PhoneAlarmCommand.parse(arguments: ["set", "--time", "07:00", "--repeat", "monthly"]))
        XCTAssertThrowsError(try PhoneAlarmCommand.parse(arguments: ["timer", "--duration", "5m", "--label", "   "]))
    }
}
