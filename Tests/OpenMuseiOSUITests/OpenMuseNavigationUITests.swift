import XCTest

final class OpenMuseNavigationUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["打开侧栏"].waitForExistence(timeout: 10))
    }

    func testPrimarySectionsAndCompanionPanel() {
        let sections: [(String, String)] = [
            ("动态", "按照你的兴趣，慢慢发现值得了解的内容。"),
            ("点子", "从你正在做的事里，找一个值得尝试的小步。"),
            ("目标", "从聊天里发现，和你一起往前推。"),
            ("资源库", "可以回到聊天继续修改的成果。"),
            ("聊天", "先连接一个模型，就可以开始聊天")
        ]

        for (section, expectedText) in sections {
            app.buttons[section].tap()
            XCTAssertTrue(app.staticTexts[expectedText].waitForExistence(timeout: 3), "Expected the \(section) section to render its heading or empty state.")
        }

        app.buttons["OpenMuse，查看活动、设备与身份"].tap()
        XCTAssertTrue(app.buttons["活动"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["还没有活动"].waitForExistence(timeout: 3))

        app.buttons["批准"].tap()
        XCTAssertTrue(app.staticTexts["没有待处理的批准"].waitForExistence(timeout: 3))

        app.buttons["桌面端"].tap()
        XCTAssertTrue(app.staticTexts["尚未连接 Mac"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["浏览器控制尚未接入"].exists)

        app.buttons["近期"].tap()
        XCTAssertTrue(app.staticTexts["还没有定时任务"].waitForExistence(timeout: 3))

        app.buttons["身份"].tap()
        XCTAssertTrue(app.staticTexts["身份与记忆"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["SOUL.md"].exists)

        app.buttons["关闭陪伴者面板"].tap()
        XCTAssertTrue(app.buttons["打开侧栏"].waitForExistence(timeout: 3))
    }

    func testDrawerSearchAndModelSettingsSurface() {
        app.buttons["打开侧栏"].tap()
        XCTAssertTrue(app.textFields["搜索对话"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["聊天"].exists)
        XCTAssertTrue(app.staticTexts["旁聊"].exists)

        app.buttons["设置"].tap()
        XCTAssertTrue(app.staticTexts["模型设置"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["密钥只保存在这台设备的钥匙串。"].exists)
        XCTAssertTrue(app.textFields["模型 ID"].exists)
        XCTAssertTrue(app.secureTextFields["粘贴 API 密钥"].exists)
        XCTAssertTrue(app.buttons["完成"].exists)
        app.buttons["完成"].tap()
    }
}
