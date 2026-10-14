import XCTest
@testable import OpenMuseCore

final class ConversationTemporalContextTests: XCTestCase {
    func testTonightIsAnchoredToEachMessageLocalDateAcrossShanghaiMidnight() throws {
        let zone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let yesterday = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 10, day: 13, hour: 23, minute: 40
        )))
        let today = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 10, day: 14, hour: 0, minute: 20
        )))
        let oldMessage = MessageRecord(
            conversationID: "main", role: .user, content: "今晚训练暂停。",
            createdAt: yesterday, timeZoneIdentifier: zone.identifier
        )
        let newMessage = MessageRecord(
            conversationID: "main", role: .user, content: "今晚训练也暂停。",
            createdAt: today, timeZoneIdentifier: zone.identifier
        )

        let oldContext = ConversationTemporalContext.annotate(
            message: oldMessage, content: oldMessage.content, fallbackTimeZoneIdentifier: zone.identifier
        )
        let newContext = ConversationTemporalContext.annotate(
            message: newMessage, content: newMessage.content, fallbackTimeZoneIdentifier: zone.identifier
        )

        XCTAssertTrue(oldContext.contains("2026-10-13 23:40:00"))
        XCTAssertTrue(newContext.contains("2026-10-14 00:20:00"))
        XCTAssertTrue(ConversationTemporalContext.turnInstructions(
            createdAt: today, timeZoneIdentifier: zone.identifier
        ).contains("不能把旧消息的日期锚点沿用到本轮"))
    }

    func testMissingLegacyZoneUsesExplicitApproximateLocalTime() throws {
        let zone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let date = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 10, day: 13, hour: 23, minute: 40
        )))

        let metadata = ConversationTemporalContext.messageMetadata(
            createdAt: date,
            timeZoneIdentifier: nil,
            fallbackTimeZoneIdentifier: zone.identifier
        )

        XCTAssertTrue(metadata.contains("2026-10-13 23:40:00"))
        XCTAssertTrue(metadata.contains("Asia/Shanghai"))
        XCTAssertTrue(metadata.contains("原始时区未记录，按本轮时区近似换算"))
    }

    func testLegacyMessagePayloadDecodesWithoutTimeZoneField() throws {
        let original = MessageRecord(
            conversationID: "main", role: .user, content: "今晚暂停。",
            createdAt: Date(timeIntervalSince1970: 1_792_000_000)
        )
        let data = try JSONEncoder().encode(original)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "timeZoneIdentifier")
        let legacyPayload = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(MessageRecord.self, from: legacyPayload)

        XCTAssertNil(decoded.timeZoneIdentifier)
        XCTAssertEqual(decoded.content, original.content)
        XCTAssertEqual(decoded.createdAt, original.createdAt)
    }
}
