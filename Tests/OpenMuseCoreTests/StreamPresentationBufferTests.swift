import XCTest
@testable import OpenMuseCore

final class StreamPresentationBufferTests: XCTestCase {
    func testChineseTextUsesReadableCharacterUnitsAndSentencePauses() throws {
        var buffer = StreamPresentationBuffer()
        buffer.append("你好。")

        let first = try XCTUnwrap(buffer.takeNextUnit(streamIsFinished: true))
        XCTAssertEqual(first.text, "你")
        XCTAssertEqual(first.delayNanoseconds, StreamPresentationBuffer.baseDelayNanoseconds)

        let second = try XCTUnwrap(buffer.takeNextUnit(streamIsFinished: true))
        XCTAssertEqual(second.text, "好。")
        XCTAssertEqual(
            second.delayNanoseconds,
            StreamPresentationBuffer.baseDelayNanoseconds + StreamPresentationBuffer.sentencePauseNanoseconds
        )
        XCTAssertNil(buffer.takeNextUnit(streamIsFinished: true))
    }

    func testEnglishWordsStayTogetherUntilTheWordIsComplete() throws {
        var buffer = StreamPresentationBuffer()
        buffer.append("Hello")
        XCTAssertNil(buffer.takeNextUnit(streamIsFinished: false))

        buffer.append(" world!")
        let hello = try XCTUnwrap(buffer.takeNextUnit(streamIsFinished: false))
        XCTAssertEqual(hello.text, "Hello ")
        let world = try XCTUnwrap(buffer.takeNextUnit(streamIsFinished: true))
        XCTAssertEqual(world.text, "world!")
    }

    func testFinishedStreamReleasesAnUnterminatedFinalWord() throws {
        var buffer = StreamPresentationBuffer()
        buffer.append("OpenMuse")

        let finalWord = try XCTUnwrap(buffer.takeNextUnit(streamIsFinished: true))
        XCTAssertEqual(finalWord.text, "OpenMuse")
        XCTAssertFalse(buffer.hasPendingText)
    }

    func testFastForwardReturnsAllRemainingTextInOrder() throws {
        var buffer = StreamPresentationBuffer()
        buffer.append("前文，中间内容。")
        let first = try XCTUnwrap(buffer.takeNextUnit(streamIsFinished: false))
        XCTAssertEqual(first.text, "前")
        XCTAssertEqual(buffer.drain(), "文，中间内容。")
        XCTAssertFalse(buffer.hasPendingText)
    }
}
