import XCTest
@testable import OpenMuseCore

final class OpenMuseLiveActivityPhaseTests: XCTestCase {
    func testProgressStagesUseShortNonSensitiveLabels() {
        XCTAssertEqual(OpenMuseLiveActivityPhase.current(stage: "正在查看与你有关的资料"), .readingContext)
        XCTAssertEqual(OpenMuseLiveActivityPhase.current(stage: "正在生成回复"), .replying)
        XCTAssertEqual(OpenMuseLiveActivityPhase.current(stage: "家里的 Mac 正在通过 Pi 处理这项任务。"), .remoteMac)
        XCTAssertEqual(OpenMuseLiveActivityPhase.current(stage: "暂时收不到家里的 Mac 进度；仍在等待任务结果。"), .waitingForApp)
        XCTAssertEqual(OpenMuseLiveActivityPhase.waitingForApp.title, "等待任务结果")
        XCTAssertEqual(OpenMuseLiveActivityPhase.current(stage: "等待你检查路径和完整正文", status: "waiting_approval"), .awaitingConfirmation)
        XCTAssertFalse(OpenMuseLiveActivityPhase.replying.title.contains("用户问题"))
        XCTAssertFalse(OpenMuseLiveActivityPhase.replying.compactTitle.contains("用户问题"))
    }

    func testTerminalTaskStatesMapToClearLabels() {
        XCTAssertEqual(OpenMuseLiveActivityPhase.current(stage: "已回复", status: "completed"), .completed)
        XCTAssertEqual(OpenMuseLiveActivityPhase.current(stage: "模型调用失败", status: "failed"), .failed)
        XCTAssertEqual(OpenMuseLiveActivityPhase.current(stage: "已停止", status: "cancelled"), .stopped)
    }
}
