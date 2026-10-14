import XCTest
@testable import OpenMuseCore

final class ModelInputContextBuilderTests: XCTestCase {
    func testCombinedInputStaysInsideWindowAndKeepsLatestRequestAndContextOrder() {
        let latest = "请记住当前请求：OpenMuse-LATEST-TRIP-REQUEST。" + String(repeating: "请只保留与本轮相关的安排。", count: 80)
        let snapshot = ModelInputContextBuilder.build(
            systemPrompt: "使命与安全边界。" + String(repeating: "先核对资料，再自然回答。", count: 100),
            referenceData: "记忆资料。" + String(repeating: "旅行偏好：慢节奏。", count: 100),
            parentContext: [TranscriptMessage(role: "user", content: "主聊摘录：用户希望去恩施旅行。")],
            recentMessages: [
                TranscriptMessage(role: "user", content: String(repeating: "很久以前的无关内容。", count: 2_000)),
                TranscriptMessage(role: "assistant", content: "较早回复。"),
                TranscriptMessage(role: "user", content: latest)
            ],
            contextWindow: 2_048
        )

        XCTAssertLessThanOrEqual(snapshot.estimatedInputTokens, snapshot.inputBudgetTokens)
        XCTAssertEqual(snapshot.inputBudgetTokens, ModelInputContextBuilder.inputBudget(contextWindow: 2_048))
        XCTAssertEqual(snapshot.messages.first?.role, "system")
        XCTAssertTrue(snapshot.messages.first?.content.contains("安全边界") == true)
        XCTAssertTrue(snapshot.messages.contains(where: { $0.content.contains("OpenMuse-LATEST-TRIP-REQUEST") }))
        XCTAssertTrue(snapshot.messages.last?.content.contains("OpenMuse-LATEST-TRIP-REQUEST") == true)
        XCTAssertFalse(snapshot.messages.dropFirst().contains(where: { $0.content == "记忆资料。" + String(repeating: "旅行偏好：慢节奏。", count: 100) }))
        XCTAssertTrue(snapshot.truncated)
        XCTAssertTrue(snapshot.historyTruncated)
        XCTAssertTrue(snapshot.currentMessageTruncated)
        XCTAssertFalse(snapshot.messages.contains(where: { $0.content.contains("较早回复") }), "Old chat must yield to the latest request when the combined context is full.")
    }

    func testLargeCurrentRequestIsMarkedAsTruncatedWithoutDroppingItsBeginningOrEndingBoundary() throws {
        let largeRequest = "当前问题 OPENMUSE-CURRENT-HEAD。" + String(repeating: "附件与历史内容。", count: 3_000) + "OPENMUSE-CURRENT-TAIL"
        let snapshot = ModelInputContextBuilder.build(
            systemPrompt: "系统边界。" + String(repeating: "行为规则。", count: 80),
            referenceData: "记忆资料。",
            parentContext: [],
            recentMessages: [TranscriptMessage(role: "user", content: largeRequest)],
            contextWindow: 2_048
        )
        let fittedCurrent = try XCTUnwrap(snapshot.messages.last?.content)

        XCTAssertLessThanOrEqual(snapshot.estimatedInputTokens, snapshot.inputBudgetTokens)
        XCTAssertTrue(fittedCurrent.contains("OPENMUSE-CURRENT-HEAD"))
        XCTAssertTrue(fittedCurrent.contains("OPENMUSE-CURRENT-TAIL"))
        XCTAssertTrue(fittedCurrent.contains("本条消息因模型上下文窗口限制已截短"))
        XCTAssertTrue(snapshot.truncated)
    }

    func testReferenceDataIsEmbeddedInCurrentUserTurnInsteadOfBecomingAnExtraTurn() throws {
        let snapshot = ModelInputContextBuilder.build(
            systemPrompt: "系统边界。",
            referenceData: "USER.md：用户偏好轻松的肩背训练。",
            parentContext: [],
            recentMessages: [
                TranscriptMessage(role: "assistant", content: "上次我们聊了网球。"),
                TranscriptMessage(role: "user", content: "明天准备练个肩背。")
            ],
            contextWindow: 4_096
        )
        let current = try XCTUnwrap(snapshot.messages.last)

        XCTAssertEqual(snapshot.messages.map(\.role), ["system", "assistant", "user"])
        XCTAssertTrue(current.content.contains(ModelPromptEnvelope.referenceOpen))
        XCTAssertTrue(current.content.contains("USER.md：用户偏好轻松的肩背训练。"))
        XCTAssertTrue(current.content.contains(ModelPromptEnvelope.currentOpen))
        XCTAssertTrue(current.content.range(of: ModelPromptEnvelope.referenceClose)!.lowerBound < current.content.range(of: ModelPromptEnvelope.currentOpen)!.lowerBound)
        XCTAssertTrue(current.content.hasSuffix("明天准备练个肩背。\n\(ModelPromptEnvelope.currentClose)"))
    }

    func testOutputReservationScalesDownForSmallerModelsAndCapsAtFourThousandNinetySix() {
        XCTAssertEqual(ModelInputContextBuilder.outputTokenLimit(contextWindow: 2_048), 256)
        XCTAssertEqual(ModelInputContextBuilder.outputTokenLimit(contextWindow: 32_000), 4_000)
        XCTAssertEqual(ModelInputContextBuilder.outputTokenLimit(contextWindow: 100_000), 4_096)
    }
}
