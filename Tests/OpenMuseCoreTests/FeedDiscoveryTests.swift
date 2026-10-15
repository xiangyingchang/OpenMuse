import Foundation
import XCTest
@testable import OpenMuseCore

@MainActor
final class FeedDiscoveryTests: XCTestCase {
    func testSearchQueryUsesOnlyBoundedNonSensitiveTopicTermsAndTargetPlatforms() throws {
        let query = try XCTUnwrap(FeedDiscovery.searchQuery(topics: [
            "根据我最近在准备的旅行，分享我可能感兴趣的路线灵感和地方故事。",
            "我喜欢自然摄影和轻松旅行",
            "我对青霉素过敏"
        ]))

        XCTAssertLessThanOrEqual(query.count, 160)
        XCTAssertTrue(query.contains("site:x.com"))
        XCTAssertTrue(query.contains("site:reddit.com"))
        XCTAssertTrue(query.contains("site:xiaohongshu.com"))
        XCTAssertTrue(query.contains("site:mp.weixin.qq.com"))
        XCTAssertTrue(query.contains("旅行"))
        XCTAssertFalse(query.contains("青霉素"))
        XCTAssertFalse(query.contains("过敏"))
    }

    func testGoogleSearchResultsBecomeDeduplicatedPublicContentCards() {
        let links = [
            PhoneBrowserLink(title: "X 旅行灵感", url: "https://x.com/user/status/123?utm_source=google", summary: "公开帖子摘要"),
            PhoneBrowserLink(title: "同一条帖子", url: "https://x.com/user/status/123?utm_medium=search", summary: "重复结果"),
            PhoneBrowserLink(title: "Reddit 讨论", url: "https://www.reddit.com/r/travel/comments/abc/example/", summary: "社区讨论摘要"),
            PhoneBrowserLink(title: "小红书笔记", url: "https://www.xiaohongshu.com/explore/xyz", summary: "公开笔记摘要"),
            PhoneBrowserLink(title: "微信公众号文章", url: "https://mp.weixin.qq.com/s/example", summary: "公开文章摘要"),
            PhoneBrowserLink(title: "搜索页，不是内容", url: "https://www.google.com/search?q=travel", summary: "")
        ]

        let items = FeedDiscovery.items(from: links, fetchedAt: Date(timeIntervalSince1970: 1_800_000_000))

        XCTAssertEqual(items.count, 4)
        XCTAssertEqual(Set(items.map(\.sourceTitle)), ["X", "Reddit", "小红书", "微信公众号"])
        XCTAssertEqual(items.first(where: { $0.sourceTitle == "X" })?.url, "https://x.com/user/status/123")
        XCTAssertEqual(items.first(where: { $0.sourceTitle == "X" })?.summary, "公开帖子摘要")
        XCTAssertTrue(items.allSatisfy { $0.sourceID == FeedDiscovery.sourceID })
    }

    func testRefreshSearchesAndPersistsRealResultCards() async throws {
        let container = FileManager.default.temporaryDirectory.appendingPathComponent("OpenMuseFeedDiscovery-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: container) }
        let browser = FixtureFeedDiscoveryBrowser()
        let store = try SQLiteStore(path: container.appendingPathComponent("OpenMuse.sqlite"))
        let interest = MemoryClaimRecord(
            id: "feed-interest-photography", value: "喜欢自然摄影", category: "interest",
            confidence: 0.9, sourceID: "feed-interest-source", sourceText: "我喜欢自然摄影。"
        )
        try store.save(interest, kind: RecordKind.memoryClaim, id: interest.id, revision: 1, appendRevision: true)
        let goal = GoalRecord(id: "feed-trip-goal", conversationID: "primary", title: "恩施七日旅行", summary: "旅行计划", steps: [])
        try store.save(goal, kind: RecordKind.goal, id: goal.id, revision: 1, appendRevision: true)
        let model = OpenMuseAppModel(
            runtimeOverride: nil,
            workspaceRootOverride: container.appendingPathComponent("workspace", isDirectory: true),
            configurationOverride: nil,
            startMacBridge: false,
            phoneBrowserRuntime: browser
        )

        await model.refreshFeeds()

        XCTAssertEqual(model.feedItems.count, 1)
        XCTAssertEqual(model.feedItems.first?.title, "一段公开的旅行灵感")
        XCTAssertEqual(model.feedItems.first?.sourceTitle, "Reddit")
        XCTAssertTrue(model.feedDiscoveryStatus?.contains("Google") == true)
        XCTAssertNotNil(model.lastFeedDiscoveryAt)
        let request = try XCTUnwrap(browser.lastRequest)
        XCTAssertEqual(request.action, .search)
        XCTAssertEqual(request.conversationID, FeedDiscovery.browserConversationID)
        XCTAssertTrue(request.query?.contains("site:reddit.com") == true)
        XCTAssertTrue(request.query?.contains("自然摄影") == true)
        XCTAssertTrue(request.query?.contains("恩施七日旅行") == true)
        XCTAssertLessThanOrEqual(request.query?.count ?? 0, 160)

        let reopened = OpenMuseAppModel(
            runtimeOverride: nil,
            workspaceRootOverride: container.appendingPathComponent("workspace", isDirectory: true),
            configurationOverride: nil,
            startMacBridge: false,
            phoneBrowserRuntime: FixtureFeedDiscoveryBrowser()
        )
        XCTAssertEqual(reopened.feedItems.map(\.id), model.feedItems.map(\.id))
    }
}

@MainActor
private final class FixtureFeedDiscoveryBrowser: PhoneBrowserRuntime {
    struct Request {
        let action: PhoneBrowserAction
        let query: String?
        let conversationID: String
    }

    private(set) var lastRequest: Request?

    func search(query: String) async throws -> PhoneBrowserPage {
        PhoneBrowserPage(title: "Google", url: "https://www.google.com/search?q=travel", text: "")
    }

    func open(url: String) async throws -> PhoneBrowserPage {
        PhoneBrowserPage(title: "Source", url: url, text: "")
    }

    func perform(_ request: PhoneBrowserActionRequest, conversationID: String) async throws -> PhoneBrowserActionResult {
        lastRequest = Request(action: request.action, query: request.query, conversationID: conversationID)
        return PhoneBrowserActionResult(
            action: .search,
            text: "Google public results",
            title: "Google",
            url: "https://www.google.com/search?q=travel",
            searchEngine: "Google",
            isSearchResult: true,
            links: [PhoneBrowserLink(
                title: "一段公开的旅行灵感",
                url: "https://www.reddit.com/r/travel/comments/example/story/",
                summary: "这是一条搜索结果提供的摘要。"
            )]
        )
    }
}
