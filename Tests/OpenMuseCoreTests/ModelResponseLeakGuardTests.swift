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
}
