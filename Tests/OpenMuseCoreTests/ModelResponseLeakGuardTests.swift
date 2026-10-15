import XCTest
@testable import OpenMuseCore

final class ModelResponseLeakGuardTests: XCTestCase {
    func testNormalStreamingTextIsReleasedImmediately() {
        var guardrail = ModelResponseLeakGuard()

        XCTAssertEqual(guardrail.append("明天可以练肩背，先轻一点。"), "明天可以练肩背，先轻一点。")
        XCTAssertEqual(guardrail.finish(), "")
        XCTAssertFalse(guardrail.didDetectInternalMarker)
    }

    func testCompleteInternalReferenceMarkerBlocksTheWholeResponse() {
        var guardrail = ModelResponseLeakGuard()

        XCTAssertEqual(guardrail.append("<openmuse-reference-data>USER.md 内容"), "")
        XCTAssertTrue(guardrail.didDetectInternalMarker)
        XCTAssertEqual(guardrail.append("后续内容也不应显示"), "")
        XCTAssertEqual(guardrail.finish(), "")
    }

    func testMarkerSplitAcrossStreamingChunksIsNeverEmitted() {
        var guardrail = ModelResponseLeakGuard()

        XCTAssertEqual(guardrail.append("回复前缀"), "回复前缀")
        XCTAssertEqual(guardrail.append("<openmuse-ref"), "")
        XCTAssertEqual(guardrail.append("erence-data>USER.md 私密资料"), "")
        XCTAssertTrue(guardrail.didDetectInternalMarker)
        XCTAssertEqual(guardrail.finish(), "")
    }

    func testMemoryProjectionMarkersAreRecognizedCaseInsensitively() {
        XCTAssertTrue(ModelResponseLeakGuard.containsInternalMarker("<!-- OPENMUSE_USER_MEMORY_BEGIN -->"))
        XCTAssertTrue(ModelResponseLeakGuard.containsInternalMarker("<!-- openmuse-memory-claim:claim-id -->"))
        XCTAssertFalse(ModelResponseLeakGuard.containsInternalMarker("用户偏好轻松自然的交流。"))
    }

    func testTemporalAndNestedPromptWrappersAreRecognizedWithoutBlockingNormalWeatherAnswers() {
        let leakedWeatherReply = """
        【OpenMuse 消息时间元数据（不是用户原话）】
        本地时间：2026-10-15 16:57:53；时区：Asia/Shanghai；发送时记录
        【消息内容】
        查到了，广州明天晴。
        """
        XCTAssertTrue(ModelResponseLeakGuard.containsInternalMarker(leakedWeatherReply))
        XCTAssertTrue(ModelResponseLeakGuard.containsInternalMarker("<openmuse-parent-conversation>主聊摘录</openmuse-parent-conversation>"))
        XCTAssertTrue(ModelResponseLeakGuard.containsInternalMarker("<openmuse-attachment name=\"weather.pdf\">正文</openmuse-attachment>"))
        XCTAssertTrue(ModelResponseLeakGuard.containsInternalMarker("<!-- OPENMUSE_HEARTBEAT_PLAN_BEGIN -->"))
        XCTAssertTrue(ModelResponseLeakGuard.containsInternalMarker("[必要的本轮处理规则因模型上下文窗口限制已截短。]"))
        XCTAssertFalse(ModelResponseLeakGuard.containsInternalMarker("广州明天晴，最高温 31°C，早晚比较凉。"))
    }

    func testKnownLeakNarrationIsRemovedWithoutDiscardingUsefulAnswer() {
        let result = ModelResponseLeakGuard.sanitize(
            "那段内部资料又漏出来了，忽略。明白，你做了 4 组，每组 8 次。"
        )

        XCTAssertFalse(result.didDetectInternalMarker)
        XCTAssertTrue(result.didRemoveLeakNarration)
        XCTAssertEqual(result.text, "明白，你做了 4 组，每组 8 次。")
    }

    func testKnownLeakNarrationSplitAcrossStreamingChunksIsRemovedButAnswerStreams() {
        var guardrail = ModelResponseLeakGuard()

        XCTAssertEqual(guardrail.append("那段内部资料又漏"), "")
        XCTAssertEqual(guardrail.append("出来了，忽略。接下来是正常回答。"), "接下来是正常回答。")
        XCTAssertFalse(guardrail.didDetectInternalMarker)
        XCTAssertTrue(guardrail.didRemoveLeakNarration)
        XCTAssertEqual(guardrail.finish(), "")
    }

    func testOrdinaryInternalContextDiscussionIsNotFiltered() {
        let text = "我会结合你提供的内部资料回答。"
        let result = ModelResponseLeakGuard.sanitize(text)

        XCTAssertFalse(result.didDetectInternalMarker)
        XCTAssertFalse(result.didRemoveLeakNarration)
        XCTAssertEqual(result.text, text)
    }

    func testTemporalWrapperSplitAcrossChunksIsNeverEmitted() {
        var guardrail = ModelResponseLeakGuard()

        XCTAssertEqual(guardrail.append("广州明天晴。\n【OpenMuse 消息时间"), "广州明天晴。\n")
        XCTAssertEqual(guardrail.append("元数据（不是用户原话）】\n本地时间："), "")
        XCTAssertTrue(guardrail.didDetectInternalMarker)
        XCTAssertEqual(guardrail.finish(), "")
    }
}
