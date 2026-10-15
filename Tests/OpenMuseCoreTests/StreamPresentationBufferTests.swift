import XCTest
@testable import OpenMuseCore

final class StreamPresentationBufferTests: XCTestCase {
    func testProviderDeltasAreCoalescedAndDrainedInOrder() {
        var buffer = StreamPresentationBuffer()
        buffer.append("先到的片段")
        buffer.append("，后到的片段。")

        XCTAssertEqual(buffer.pendingCharacterCount, 12)
        XCTAssertEqual(buffer.drain(), "先到的片段，后到的片段。")
        XCTAssertFalse(buffer.hasPendingText)
        XCTAssertEqual(buffer.pendingCharacterCount, 0)
    }

    func testReadableNewlineCanFlushACompleteBatchEarly() {
        var buffer = StreamPresentationBuffer()
        buffer.append(String(repeating: "路线内容", count: 13) + "\n")

        XCTAssertTrue(buffer.shouldFlushAtParagraphBoundary(presentedCharacterCount: 0))
    }

    func testShortOrAlreadyLongRepliesDoNotForceParagraphFlush() {
        var buffer = StreamPresentationBuffer()
        buffer.append("短行\n")
        XCTAssertFalse(buffer.shouldFlushAtParagraphBoundary(presentedCharacterCount: 0))

        buffer.append(String(repeating: "补充", count: 24))
        XCTAssertFalse(buffer.shouldFlushAtParagraphBoundary(presentedCharacterCount: 5_000))
    }

    func testRefreshIntervalIncreasesOnlyForRenderingLoad() {
        XCTAssertEqual(
            StreamPresentationBuffer.refreshIntervalNanoseconds(presentedCharacterCount: 0),
            48_000_000
        )
        XCTAssertEqual(
            StreamPresentationBuffer.refreshIntervalNanoseconds(presentedCharacterCount: 1_000),
            64_000_000
        )
        XCTAssertEqual(
            StreamPresentationBuffer.refreshIntervalNanoseconds(presentedCharacterCount: 5_000),
            96_000_000
        )
    }

    func testFinalDrainReturnsTheWholePendingTailImmediately() {
        var buffer = StreamPresentationBuffer()
        let finalText = String(repeating: "完整回复内容。", count: 40)
        buffer.append(finalText)

        XCTAssertEqual(buffer.drain(), finalText)
        XCTAssertFalse(buffer.hasPendingText)
    }
}
