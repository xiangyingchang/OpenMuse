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
            ("动态", "从你选择的来源里，慢慢发现值得了解的内容。"),
            ("点子", "从你正在做的事里，找一个值得尝试的小步。"),
            ("目标", "从聊天里发现，和你一起往前推。"),
            ("资源库", "可以回到聊天继续修改的成果。"),
            ("聊天", "先连接一个模型，就可以开始聊天")
        ]

        for (section, expectedText) in sections {
            app.buttons[section].tap()
            XCTAssertTrue(app.staticTexts[expectedText].waitForExistence(timeout: 3), "Expected the \(section) section to render its heading or empty state.")
            if section == "动态" {
                XCTAssertTrue(app.textFields["https://example.com/feed.xml"].exists)
                XCTAssertTrue(app.switches["显示文章图片"].exists)
                XCTAssertTrue(app.staticTexts["还没有新的动态"].exists)
            }
        }

        app.buttons["聊天"].tap()
        XCTAssertTrue(app.buttons["chat-add-attachment"].waitForExistence(timeout: 3))

        app.buttons["OpenMuse，查看活动、设备与身份"].tap()
        XCTAssertTrue(app.buttons["活动"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["还没有活动"].waitForExistence(timeout: 3))

        app.buttons["批准"].tap()
        XCTAssertTrue(app.staticTexts["没有待处理的批准"].waitForExistence(timeout: 3))

        app.buttons["桌面端"].tap()
        XCTAssertTrue(app.staticTexts["尚未连接 Mac"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["浏览器控制尚未接入"].exists)

        app.buttons["近期"].tap()
        XCTAssertTrue(app.staticTexts["还没有目标提醒"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["在进行中的目标里选择“设置提醒”，约定一个回来继续的时间。"].exists)

        app.buttons["身份"].tap()
        XCTAssertTrue(app.staticTexts["身份与记忆"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["当前记忆"].exists)
        XCTAssertTrue(app.staticTexts["这里管理同一份结构化记忆；过期或尚未生效的记录仍可在此查看和调整。MEMORY.md 自动维护区只展示当前有效记忆，完整且可迁移；USER.md 是精简画像，GLOBAL.md 是主题索引。明确表达可自动记录，导入或推断先经你确认；编辑同步到同一记录，撤销保留修订，彻底忘记会清除记录。"].exists)
        XCTAssertTrue(app.staticTexts["明确告诉 OpenMuse“记住……”或表达稳定偏好后，记忆会列在这里。外部资料和推断不会自动写成事实。"].exists)
        XCTAssertTrue(app.staticTexts["SOUL.md"].exists)

        app.buttons["关闭陪伴者面板"].tap()
        XCTAssertTrue(app.buttons["打开侧栏"].waitForExistence(timeout: 3))
    }

    func testMainChatIsThePrimaryTabAndOnlySideChatsAppearBelowIt() {
        app.terminate()
        app = XCUIApplication()
        app.launchArguments = ["-openmuse-ui-test-workspace", UUID().uuidString]
        app.launch()
        XCTAssertTrue(app.buttons["打开侧栏"].waitForExistence(timeout: 10))

        app.buttons["打开侧栏"].tap()
        XCTAssertTrue(app.buttons["open-primary-chat"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.buttons["open-primary-chat"].label, "聊天")
        XCTAssertEqual(app.staticTexts.matching(identifier: "primary-conversation-title").count, 0)

        app.buttons["start-side-conversation"].tap()
        app.buttons["打开侧栏"].tap()
        let sideChat = app.buttons["新旁聊"]
        XCTAssertTrue(sideChat.waitForExistence(timeout: 3))
        XCTAssertEqual(sideChat.value as? String, "当前对话")

        app.buttons["open-primary-chat"].tap()
        app.buttons["打开侧栏"].tap()
        XCTAssertEqual(app.buttons["新旁聊"].value as? String, "未选中")
        XCTAssertEqual(app.staticTexts.matching(identifier: "primary-conversation-title").count, 0)
    }

    func testDreamingPlanControlsStayReadableWhenEnabled() {
        app.terminate()
        app = XCUIApplication()
        app.launchArguments = ["-openmuse-ui-test-workspace", UUID().uuidString]
        app.launch()
        XCTAssertTrue(app.buttons["OpenMuse，查看活动、设备与身份"].waitForExistence(timeout: 10))
        app.buttons["OpenMuse，查看活动、设备与身份"].tap()
        app.buttons["身份"].tap()

        let automaticReview = app.switches["dreaming-review-auto-toggle"]
        XCTAssertTrue(automaticReview.waitForExistence(timeout: 3))
        XCTAssertFalse(app.descendants(matching: .any)["dreaming-plan-settings"].exists)
        automaticReview.tap()

        XCTAssertTrue(app.descendants(matching: .any)["dreaming-plan-settings"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "22:00")).firstMatch.exists)
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "08:00")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts["每日请求上限"].exists)
        XCTAssertTrue(app.staticTexts["每日 Token 上限"].exists)
        XCTAssertTrue(app.staticTexts["单次输出上限"].exists)
        XCTAssertTrue(app.staticTexts["20 次"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Dreaming 设置布局"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testComposerResourceEntryAndKeyboardHideBottomTabs() {
        app.buttons["聊天"].tap()
        let add = app.buttons["chat-add-attachment"]
        XCTAssertTrue(add.waitForExistence(timeout: 3))
        let composer = app.textFields["chat-composer-input"]
        XCTAssertTrue(composer.waitForExistence(timeout: 3))
        composer.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        let send = app.buttons["发送"]
        XCTAssertTrue(send.exists)
        XCTAssertEqual(add.frame.midY, send.frame.midY, accuracy: 1.5, "The plus button should share the composer centerline.")
        XCTAssertEqual(composer.frame.midY, send.frame.midY, accuracy: 1.5, "The placeholder should share the composer centerline.")
        let tabBar = app.descendants(matching: .any)["phone-tab-navigation"]
        XCTAssertFalse(tabBar.exists, "The bottom section bar should collapse while the keyboard is open.")

        add.tap()
        XCTAssertTrue(app.buttons["添加文件"].waitForExistence(timeout: 3))
    }

    func testPendingToolApprovalShowsDestinationAndFullPreviewBeforeRejection() {
        app.terminate()
        app = XCUIApplication()
        app.launchArguments = [
            "-openmuse-ui-test-workspace", UUID().uuidString,
            "-openmuse-ui-seed-tool-approval"
        ]
        app.launch()

        XCTAssertTrue(app.staticTexts["请求写入本机工作区"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["travel/outline.md"].exists)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "第一天留出自由时间")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts["将新建文件"].exists)
        let reject = app.buttons["reject-tool-approval-ui-tool-approval"]
        XCTAssertTrue(reject.exists)
        XCTAssertTrue(app.buttons["approve-tool-approval-ui-tool-approval"].exists)

        reject.tap()

        XCTAssertTrue(app.staticTexts["没有待处理的批准"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["这项确认请求已经失效；没有执行任何操作。"].exists)
    }

    func testActivityDetailsShowOperationIDInputOutputAndCopyWithoutSummaryStep() {
        app.terminate()
        app = XCUIApplication()
        app.launchArguments = [
            "-openmuse-ui-test-workspace", UUID().uuidString,
            "-openmuse-ui-seed-activity-operation"
        ]
        app.launch()

        XCTAssertTrue(app.buttons["打开侧栏"].waitForExistence(timeout: 10))
        app.buttons["OpenMuse，查看活动、设备与身份"].tap()
        app.buttons["活动"].tap()
        let row = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "活动详情测试")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()

        let details = app.buttons["查看调用参数和返回结果"]
        XCTAssertTrue(details.waitForExistence(timeout: 5))
        details.tap()
        let detailsScrollView = app.scrollViews["activity-details-scroll"]
        XCTAssertTrue(detailsScrollView.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["ui-shell-call-001"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["openmuse_phone_run_ish_command"].exists)
        XCTAssertTrue(app.staticTexts["已完成"].exists)
        XCTAssertTrue(app.staticTexts["iPhone"].exists)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "command")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "旅行资料已整理")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "开始：")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "· 结束：")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "用时 ")).firstMatch.exists)
        let copyButton = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "activity-operation-copy-")).firstMatch
        XCTAssertTrue(copyButton.exists)
        if !copyButton.isHittable { detailsScrollView.swipeUp() }
        XCTAssertTrue(copyButton.isHittable, "Expanded operation details and their copy control must remain reachable inside the activity timeline.")
        copyButton.tap()
        let copied = NSPredicate(format: "label CONTAINS %@", "已复制")
        expectation(for: copied, evaluatedWith: copyButton)
        waitForExpectations(timeout: 2)
    }

    func testCaptureDesignAuditScreenshots() {
        app.terminate()
        app = XCUIApplication()
        app.launchArguments = ["-openmuse-ui-test-workspace", UUID().uuidString]
        app.launch()
        XCTAssertTrue(app.buttons["打开侧栏"].waitForExistence(timeout: 10))
        captureScreen("chat-first-run")

        let sections = ["动态", "点子", "目标", "资源库"]
        for section in sections {
            app.buttons[section].tap()
            captureScreen("section-\(section)")
        }

        app.buttons["聊天"].tap()
        app.buttons["OpenMuse，查看活动、设备与身份"].tap()
        let companionClose = app.buttons["关闭陪伴者面板"]
        XCTAssertTrue(companionClose.waitForExistence(timeout: 3))
        XCTAssertLessThan(companionClose.frame.minY, 85, "The companion controls should sit near the top safe area, as in the Muse reference.")
        XCTAssertGreaterThanOrEqual(companionClose.frame.width, 44, "The circular control should preserve the minimum accessible hit target.")
        XCTAssertFalse(app.staticTexts["陪你把想做的事慢慢做成"].exists, "The removed fixed tagline must not return.")
        for page in ["活动", "批准", "桌面端", "近期", "身份"] {
            app.buttons[page].tap()
            captureScreen("companion-\(page)")
        }
    }

    private func captureScreen(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "OpenMuse-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
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
        XCTAssertTrue(app.switches["允许模型调用本机工具"].exists)
        XCTAssertTrue(app.switches["流式显示回复"].exists)
        XCTAssertTrue(app.staticTexts["目前支持文本对话与已提取的附件文字；图片理解和语音对话尚未接入。"].exists)
        let backupTitle = app.staticTexts["备份与恢复"]
        for _ in 0..<6 where !backupTitle.isHittable { app.swipeUp() }
        XCTAssertTrue(backupTitle.waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["选择备份文件夹"].exists)
        XCTAssertTrue(app.buttons["从备份导入"].isEnabled)
        XCTAssertFalse(app.buttons["立即备份 / 导出"].isEnabled, "Export stays unavailable until the user selects a destination.")
        XCTAssertFalse(app.switches["每天自动备份完整资料"].isEnabled, "Scheduling stays unavailable until the user selects a destination.")
        XCTAssertTrue(app.buttons["完成"].exists)
        app.buttons["完成"].tap()
    }

#if !targetEnvironment(simulator)
    func testSignedDeviceISHRuntimeRunsTheApprovedEnvironmentCheck() {
        app.terminate()
        app = XCUIApplication()
        app.launchArguments = ["-openmuse-ish-smoke-test"]
        app.launch()

        let runButton = app.buttons["ish-smoke-run"]
        XCTAssertTrue(runButton.waitForExistence(timeout: 10))
        runButton.tap()

        let result = app.staticTexts["ish-smoke-result"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        let finished = NSPredicate(format: "label CONTAINS %@", "SHELL_EXIT=")
        expectation(for: finished, evaluatedWith: result)
        waitForExpectations(timeout: 50)

        let report = result.label
        XCTAssertTrue(report.contains("SHELL_EXIT=0"), report)
        XCTAssertTrue(report.contains("3.24.2"), report)
        XCTAssertFalse(report.contains("TIMED_OUT=true"), report)
    }
#endif

    func testMemoryImportShowsTheBundledPromptAndPasteArea() {
        app.buttons["OpenMuse，查看活动、设备与身份"].tap()
        app.buttons["身份"].tap()
        for _ in 0..<3 where !app.buttons["从其他 AI 导入记忆"].exists {
            app.swipeUp()
        }
        let importButton = app.buttons["从其他 AI 导入记忆"]
        XCTAssertTrue(importButton.waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["导入 ChatGPT 聊天记录"].exists)
        importButton.tap()

        XCTAssertTrue(app.staticTexts["导入记忆"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["复制"].exists)
        XCTAssertTrue(app.textViews["其他 AI 的记忆回复"].exists)
    }

    func testMemoryValidityEditorExposesAccessibleDateControls() {
        app.terminate()
        app = XCUIApplication()
        app.launchArguments = [
            "-openmuse-ui-test-workspace", UUID().uuidString,
            "-openmuse-ui-seed-memory-validity"
        ]
        app.launch()

        XCTAssertTrue(app.buttons["打开侧栏"].waitForExistence(timeout: 10))
        app.buttons["OpenMuse，查看活动、设备与身份"].tap()
        app.buttons["身份"].tap()
        let validity = app.staticTexts["memory-validity-ui-memory-validity"]
        for _ in 0..<5 where !validity.exists { app.swipeUp() }
        XCTAssertTrue(validity.waitForExistence(timeout: 3))

        app.buttons["记忆处理"].firstMatch.tap()
        app.buttons["设置有效期"].tap()
        let fromToggle = app.switches["memory-valid-from-toggle-ui-memory-validity"]
        let untilToggle = app.switches["memory-valid-until-toggle-ui-memory-validity"]
        XCTAssertTrue(fromToggle.waitForExistence(timeout: 3))
        XCTAssertTrue(untilToggle.exists)
        XCTAssertTrue(app.datePickers["memory-valid-from-picker-ui-memory-validity"].exists)
        XCTAssertTrue(app.datePickers["memory-valid-until-picker-ui-memory-validity"].exists)
        XCTAssertTrue(app.buttons["memory-validity-save-ui-memory-validity"].exists)
    }

    func testTravelArtifactDetailShowsCoverageSourcesAndAssumptions() {
        app.terminate()
        app = XCUIApplication()
        app.launchArguments += [
            "-openmuse-ui-test-workspace", UUID().uuidString,
            "-openmuse-ui-seed-travel-artifact"
        ]
        app.launch()

        XCTAssertTrue(app.buttons["打开侧栏"].waitForExistence(timeout: 10))
        app.buttons["资源库"].tap()
        let artifact = app.buttons["artifact-ui-travel-artifact"]
        XCTAssertTrue(artifact.waitForExistence(timeout: 5))
        artifact.tap()

        XCTAssertTrue(app.staticTexts["artifact-coverage-days"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["artifact-coverage-days"].label, "3 / 7 天")
        XCTAssertEqual(app.staticTexts["artifact-source-count"].label, "参考 3 条对话消息")
        XCTAssertTrue(app.staticTexts["待确认"].exists)
        XCTAssertEqual(app.staticTexts["artifact-assumption-0"].label, "暂按两人同行")
        XCTAssertEqual(app.staticTexts["artifact-assumption-1"].label, "出发日期尚未确定")
        XCTAssertTrue(app.buttons["构件操作"].exists)
    }

    func testTravelArtifactCanSwitchBetweenPreservedPlanAlternatives() {
        app.terminate()
        app = XCUIApplication()
        app.launchArguments += [
            "-openmuse-ui-test-workspace", UUID().uuidString,
            "-openmuse-ui-seed-travel-artifact"
        ]
        app.launch()

        XCTAssertTrue(app.buttons["打开侧栏"].waitForExistence(timeout: 10))
        app.buttons["资源库"].tap()
        let artifact = app.buttons["artifact-ui-travel-artifact"]
        XCTAssertTrue(artifact.waitForExistence(timeout: 5))
        artifact.tap()

        let coverage = app.staticTexts["artifact-coverage-days"]
        XCTAssertTrue(coverage.waitForExistence(timeout: 5))
        XCTAssertEqual(coverage.label, "3 / 7 天")
        XCTAssertTrue(app.staticTexts["artifact-variant-difference"].label.contains("5天"))
        let fiveDayOption = app.segmentedControls.buttons["5天方案"]
        XCTAssertTrue(fiveDayOption.waitForExistence(timeout: 3))
        fiveDayOption.tap()
        XCTAssertEqual(coverage.label, "5 / 5 天")
        XCTAssertTrue(app.staticTexts["artifact-variant-difference"].label.contains("7天"))
    }

    func testArtifactCanBePermanentlyDeletedFromItsPreview() {
        app.terminate()
        app = XCUIApplication()
        app.launchArguments += [
            "-openmuse-ui-test-workspace", UUID().uuidString,
            "-openmuse-ui-seed-travel-artifact"
        ]
        app.launch()

        XCTAssertTrue(app.buttons["打开侧栏"].waitForExistence(timeout: 10))
        app.buttons["资源库"].tap()
        let artifact = app.buttons["artifact-ui-travel-artifact"]
        XCTAssertTrue(artifact.waitForExistence(timeout: 5))
        artifact.tap()
        app.buttons["构件操作"].tap()
        app.buttons["永久删除构件…"].tap()
        app.buttons["永久删除"].tap()

        XCTAssertTrue(app.staticTexts["成果会留在这里"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["artifact-ui-travel-artifact"].exists)
    }

    func testWebArtifactRendersAndKeepsInteractionInsideItsLocalView() {
        app.terminate()
        app = XCUIApplication()
        app.launchArguments = [
            "-openmuse-ui-test-workspace", UUID().uuidString,
            "-openmuse-ui-seed-web-artifact"
        ]
        app.launch()

        XCTAssertTrue(app.buttons["打开侧栏"].waitForExistence(timeout: 10))
        app.buttons["资源库"].tap()
        let artifact = app.buttons["artifact-ui-web-artifact"]
        XCTAssertTrue(artifact.waitForExistence(timeout: 5))
        artifact.tap()
        XCTAssertTrue(app.staticTexts["沙箱页面已加载"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["网页已离线载入"].exists)
        let toggle = app.buttons["切换状态"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        toggle.tap()
        XCTAssertTrue(app.staticTexts["交互仍在本地沙箱"].waitForExistence(timeout: 5))
        let externalLink = app.links["打开外部景区页面"]
        XCTAssertTrue(externalLink.waitForExistence(timeout: 5))
        externalLink.tap()
        let externalLinkAlert = app.alerts["在浏览器打开链接？"]
        XCTAssertTrue(externalLinkAlert.waitForExistence(timeout: 5))
        XCTAssertTrue(externalLinkAlert.staticTexts["将打开 example.invalid。请确认网址和页面。"].exists)
        externalLinkAlert.buttons["取消"].tap()
        XCTAssertTrue(app.staticTexts["交互仍在本地沙箱"].exists)
    }

    func testGoalProgressShowsItsSourceAndOpensTheRelatedConversation() {
        app.terminate()
        app = XCUIApplication()
        app.launchArguments += [
            "-openmuse-ui-test-workspace", UUID().uuidString,
            "-openmuse-ui-seed-goal-progress"
        ]
        app.launch()

        XCTAssertTrue(app.buttons["打开侧栏"].waitForExistence(timeout: 10))
        app.buttons["目标"].tap()
        XCTAssertTrue(app.staticTexts["goal-progress-heading"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["来自 OpenMuse 保存的计划"].exists)
        XCTAssertTrue(app.staticTexts["我已把第一版七日路线保存为草稿；出发日期和住宿仍待确认。"].exists)

        let openConversation = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "goal-progress-open-")
        ).firstMatch
        XCTAssertTrue(openConversation.exists)
        openConversation.tap()
        XCTAssertTrue(app.staticTexts["我已把第一版七日路线保存为草稿；出发日期和住宿仍待确认。"].waitForExistence(timeout: 5))
    }

    func testPersonaRevisionShowsItsSourceAndCanBeUndone() {
        app.terminate()
        app = XCUIApplication()
        app.launchArguments = [
            "-openmuse-ui-test-workspace", UUID().uuidString,
            "-openmuse-ui-seed-persona-revision"
        ]
        app.launch()

        XCTAssertTrue(app.buttons["打开侧栏"].waitForExistence(timeout: 10))
        app.buttons["OpenMuse，查看活动、设备与身份"].tap()
        app.buttons["身份"].tap()

        let habit = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "保持轻松自然，像一起商量")).firstMatch
        for _ in 0..<4 where !habit.exists { app.swipeUp() }
        XCTAssertTrue(habit.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "英语学习陪伴太严肃了")).firstMatch.exists)

        let undo = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "persona-revision-undo-")).firstMatch
        XCTAssertTrue(undo.exists)
        undo.tap()
        XCTAssertTrue(app.staticTexts["已撤销"].waitForExistence(timeout: 3))
    }

    func testDreamingProposalShowsItsSourceAndCanBeRejected() {
        app.terminate()
        app = XCUIApplication()
        app.launchArguments = [
            "-openmuse-ui-test-workspace", UUID().uuidString,
            "-openmuse-ui-seed-dreaming-review"
        ]
        app.launch()

        XCTAssertTrue(app.buttons["打开侧栏"].waitForExistence(timeout: 10))
        app.buttons["OpenMuse，查看活动、设备与身份"].tap()
        app.buttons["身份"].tap()

        let proposalTitle = app.staticTexts["旅行节奏偏好"]
        for _ in 0..<6 where !proposalTitle.exists { app.swipeUp() }
        XCTAssertTrue(proposalTitle.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["你可能更喜欢留出休息时间的旅行计划。"].exists)
        XCTAssertTrue(app.staticTexts["原话依据：「我喜欢旅行轻松一点，别把每天排满。」"].exists)
        XCTAssertTrue(app.staticTexts["来源：我喜欢旅行轻松一点，别把每天排满。"].exists)

        let reject = app.buttons["dreaming-proposal-reject-ui-dream-proposal"]
        XCTAssertTrue(reject.exists)
        reject.tap()
        XCTAssertTrue(app.staticTexts["未采用"].waitForExistence(timeout: 3))
    }

    func testDreamingGoalStepProposalClearlyRequiresUserAcceptance() {
        app.terminate()
        app = XCUIApplication()
        app.launchArguments = [
            "-openmuse-ui-test-workspace", UUID().uuidString,
            "-openmuse-ui-seed-goal-step-proposal"
        ]
        app.launch()

        XCTAssertTrue(app.buttons["打开侧栏"].waitForExistence(timeout: 10))
        app.buttons["OpenMuse，查看活动、设备与身份"].tap()
        app.buttons["身份"].tap()

        let proposalTitle = app.staticTexts["先挑两处备选景点"]
        for _ in 0..<6 where !proposalTitle.exists { app.swipeUp() }
        XCTAssertTrue(proposalTitle.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["目标：恩施旅行"].exists)
        XCTAssertTrue(app.staticTexts["原话依据：「先挑两三个轻松的景点，之后再看交通。」"].exists)
        XCTAssertTrue(app.staticTexts["来源：先挑两三个轻松的景点，之后再看交通。"].exists)

        let addStep = app.buttons["dreaming-proposal-accept-ui-goal-step-proposal"]
        XCTAssertEqual(addStep.label, "加入目标步骤")
        addStep.tap()
        XCTAssertTrue(app.staticTexts["已采纳"].waitForExistence(timeout: 3))
    }

    func testDreamingMemoryUpdateShowsOldAndNewClaimsAndRequiresAcceptance() {
        app.terminate()
        app = XCUIApplication()
        app.launchArguments = [
            "-openmuse-ui-test-workspace", UUID().uuidString,
            "-openmuse-ui-seed-memory-update-proposal"
        ]
        app.launch()

        XCTAssertTrue(app.buttons["打开侧栏"].waitForExistence(timeout: 10))
        app.buttons["OpenMuse，查看活动、设备与身份"].tap()
        app.buttons["身份"].tap()

        let proposalTitle = app.staticTexts["旅行节奏偏好可能变化"]
        for _ in 0..<7 where !proposalTitle.exists { app.swipeUp() }
        XCTAssertTrue(proposalTitle.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["当前记忆：「旅行计划要留出足够休息时间」"].exists)
        XCTAssertTrue(app.staticTexts["旅行计划可以多安排一两个地方，不必每天留很多休息时间。"].exists)
        XCTAssertTrue(app.staticTexts["原话依据：「不用每天都留很多休息时间，可以多安排一两个地方」"].exists)

        let accept = app.buttons["dreaming-proposal-accept-ui-memory-update-proposal"]
        XCTAssertEqual(accept.label, "确认更新记忆")
        accept.tap()
        XCTAssertTrue(app.staticTexts["已采纳"].waitForExistence(timeout: 3))
    }
}
