import XCTest
@testable import OpenMuseCore

final class PhoneSandboxRuntimeTests: XCTestCase {
    func testBrowserNavigationPolicyAllowsPublicPagesAndSafeChildFrames() throws {
        let google = try XCTUnwrap(URL(string: "https://www.google.com/search?q=weather"))
        let googleFrame = try XCTUnwrap(URL(string: "https://www.google.com/recaptcha/"))
        let blobFrame = try XCTUnwrap(URL(string: "blob:https://www.google.com/1234"))
        let privateURL = try XCTUnwrap(URL(string: "https://192.168.1.10/"))
        let insecureURL = try XCTUnwrap(URL(string: "http://www.google.com/"))
        let localFrame = try XCTUnwrap(URL(string: "about:blank"))

        XCTAssertEqual(
            PhoneBrowserURLPolicy.navigationDisposition(url: google, hasTargetFrame: true, isMainFrame: true),
            .allow
        )
        XCTAssertEqual(
            PhoneBrowserURLPolicy.navigationDisposition(url: googleFrame, hasTargetFrame: true, isMainFrame: false),
            .allow
        )
        XCTAssertEqual(
            PhoneBrowserURLPolicy.navigationDisposition(url: localFrame, hasTargetFrame: true, isMainFrame: false),
            .allow
        )
        XCTAssertEqual(
            PhoneBrowserURLPolicy.navigationDisposition(url: blobFrame, hasTargetFrame: true, isMainFrame: false),
            .allow
        )
        XCTAssertEqual(
            PhoneBrowserURLPolicy.navigationDisposition(url: privateURL, hasTargetFrame: true, isMainFrame: false),
            .cancel
        )
        XCTAssertEqual(
            PhoneBrowserURLPolicy.navigationDisposition(url: insecureURL, hasTargetFrame: true, isMainFrame: false),
            .cancel
        )
        XCTAssertEqual(
            PhoneBrowserURLPolicy.navigationDisposition(url: google, hasTargetFrame: false, isMainFrame: false),
            .cancel
        )
        XCTAssertEqual(
            PhoneBrowserURLPolicy.navigationDisposition(url: localFrame, hasTargetFrame: true, isMainFrame: true),
            .reject
        )
        XCTAssertEqual(
            PhoneBrowserURLPolicy.navigationDisposition(url: privateURL, hasTargetFrame: true, isMainFrame: true),
            .reject
        )
        XCTAssertEqual(
            PhoneBrowserURLPolicy.navigationDisposition(url: insecureURL, hasTargetFrame: true, isMainFrame: true),
            .reject
        )
    }

    func testSearchDefaultsToGoogleAndUsesOnlyConfiguredDistinctFallback() {
        let suiteName = "OpenMusePhoneSearch-\(UUID().uuidString)"
        let defaults = try! XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertEqual(PhoneSearchEnginePreferences(userDefaults: defaults).enginesToTry, [.google, .bing])

        defaults.set(PhoneSearchEngine.bing.rawValue, forKey: PhoneSearchEnginePreferences.fallbackDefaultsKey)
        XCTAssertEqual(PhoneSearchEnginePreferences(userDefaults: defaults).enginesToTry, [.google, .bing])

        defaults.set(PhoneSearchEngine.google.rawValue, forKey: PhoneSearchEnginePreferences.fallbackDefaultsKey)
        XCTAssertEqual(PhoneSearchEnginePreferences(userDefaults: defaults).enginesToTry, [.google])

        defaults.set("", forKey: PhoneSearchEnginePreferences.fallbackDefaultsKey)
        XCTAssertEqual(PhoneSearchEnginePreferences(userDefaults: defaults).enginesToTry, [.google])

        defaults.removeObject(forKey: PhoneSearchEnginePreferences.fallbackDefaultsKey)
        defaults.set(PhoneSearchEngine.bing.rawValue, forKey: PhoneSearchEnginePreferences.primaryDefaultsKey)
        XCTAssertEqual(PhoneSearchEnginePreferences(userDefaults: defaults).enginesToTry, [.bing, .google])
    }

    func testSearchEngineURLsEncodeQueriesAndKeepProviderSource() throws {
        let google = try XCTUnwrap(PhoneSearchEngine.google.searchURL(query: "广州天气 + 温度"))
        let googleComponents = try XCTUnwrap(URLComponents(url: google, resolvingAgainstBaseURL: false))
        XCTAssertEqual(google.host, "www.google.com")
        XCTAssertEqual(googleComponents.queryItems?.first(where: { $0.name == "q" })?.value, "广州天气 + 温度")

        let duckDuckGo = try XCTUnwrap(PhoneSearchEngine.duckDuckGo.searchURL(query: "旅行计划"))
        XCTAssertEqual(duckDuckGo.host, "html.duckduckgo.com")
    }

    func testBrowserActionParserAcceptsPersistentTabActionsAndBoundsInputs() throws {
        let search = try PhoneBrowserActionRequest(
            argumentsJSON: #"{"tool_title":"Search Guangzhou weather","action":"search","query":"广州天气","tab_id":2}"#
        )
        XCTAssertEqual(search.action, .search)
        XCTAssertEqual(search.query, "广州天气")
        XCTAssertEqual(search.tabID, 2)

        let click = try PhoneBrowserActionRequest(
            argumentsJSON: #"{"tool_title":"Open result","action":"click","selector":"a.result","tab_id":2}"#
        )
        XCTAssertEqual(click.action, .click)
        XCTAssertEqual(click.selector, "a.result")

        let backbone = try PhoneBrowserActionRequest(
            argumentsJSON: #"{"action":"get_backbone","max_depth":5,"tab_id":2}"#
        )
        XCTAssertEqual(backbone.action, .getBackbone)
        XCTAssertEqual(backbone.maxDepth, 5)

        let collect = try PhoneBrowserActionRequest(
            argumentsJSON: #"{"action":"scroll_and_collect","selector":"main","item_selector":"article","direction":"up","amount":650,"scroll_count":7,"timeout":10,"tab_id":2}"#
        )
        XCTAssertEqual(collect.action, .scrollAndCollect)
        XCTAssertEqual(collect.selector, "main")
        XCTAssertEqual(collect.itemSelector, "article")
        XCTAssertEqual(collect.direction, .up)
        XCTAssertEqual(collect.amount, 650)
        XCTAssertEqual(collect.scrollCount, 7)
        XCTAssertEqual(collect.timeout, 10)

        let hover = try PhoneBrowserActionRequest(
            argumentsJSON: #"{"action":"hover","selector":"button.menu"}"#
        )
        XCTAssertEqual(hover.action, .hover)

        XCTAssertThrowsError(try PhoneBrowserActionRequest(
            argumentsJSON: #"{"action":"search","query":"   "}"#
        ))
        XCTAssertThrowsError(try PhoneBrowserActionRequest(
            argumentsJSON: #"{"action":"click","coordinate_x":20}"#
        ))
        XCTAssertThrowsError(try PhoneBrowserActionRequest(
            argumentsJSON: #"{"action":"navigate","url":"file:///etc/passwd"}"#
        ))
        XCTAssertThrowsError(try PhoneBrowserActionRequest(
            argumentsJSON: #"{"action":"scroll_and_collect","scroll_count":21}"#
        ))
    }

    func testCommandPolicyTrimsAndAcceptsBoundedCommand() throws {
        XCTAssertEqual(try PhoneSandboxCommandPolicy.validate("  printf 'hello'  "), "printf 'hello'")
    }

    func testCommandPolicyRejectsEmptyCommand() {
        XCTAssertThrowsError(try PhoneSandboxCommandPolicy.validate(" \n ")) { error in
            XCTAssertEqual(error as? PhoneSandboxCommandError, .emptyCommand)
        }
    }

    func testCommandPolicyRejectsCommandAboveByteLimit() {
        let oversized = String(repeating: "界", count: PhoneSandboxCommandPolicy.maximumCommandBytes / 3 + 1)
        XCTAssertThrowsError(try PhoneSandboxCommandPolicy.validate(oversized)) { error in
            XCTAssertEqual(error as? PhoneSandboxCommandError, .commandTooLarge)
        }
    }

    func testCommandPolicyRejectsNullByte() {
        XCTAssertThrowsError(try PhoneSandboxCommandPolicy.validate("echo\0unsafe")) { error in
            XCTAssertEqual(error as? PhoneSandboxCommandError, .containsNullByte)
        }
    }

}
