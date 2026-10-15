import Foundation

public struct PhoneBrowserLink: Codable, Equatable, Sendable {
    public let title: String
    public let url: String
    public let summary: String?

    public init(title: String, url: String, summary: String? = nil) {
        self.title = title
        self.url = url
        self.summary = summary
    }
}

public struct PhoneBrowserPage: Codable, Equatable, Sendable {
    public let title: String
    public let url: String
    public let text: String
    public let links: [PhoneBrowserLink]
    public let searchEngine: String?
    public let attemptedSearchEngines: [String]?

    public init(
        title: String,
        url: String,
        text: String,
        links: [PhoneBrowserLink] = [],
        searchEngine: String? = nil,
        attemptedSearchEngines: [String]? = nil
    ) {
        self.title = title
        self.url = url
        self.text = text
        self.links = links
        self.searchEngine = searchEngine
        self.attemptedSearchEngines = attemptedSearchEngines
    }
}

public enum PhoneBrowserAction: String, CaseIterable, Codable, Sendable {
    case navigate
    case getReadable = "get_readable"
    case getText = "get_text"
    case getPageInfo = "get_page_info"
    case findElements = "find_elements"
    case click
    case type
    case hover
    case scroll
    case scrollAndCollect = "scroll_and_collect"
    case getBackbone = "get_backbone"
    case waitForDOMStable = "wait_for_dom_stable"
    case newTab = "new_tab"
    case closeTab = "close_tab"
    case listTabs = "list_tabs"
    case search
}

public enum PhoneBrowserScrollDirection: String, Codable, Sendable {
    case up
    case down
}

public struct PhoneBrowserActionRequest: Equatable, Sendable {
    public let action: PhoneBrowserAction
    public let query: String?
    public let url: String?
    public let selector: String?
    public let text: String?
    public let direction: PhoneBrowserScrollDirection?
    public let amount: Int?
    public let tabID: Int?
    public let coordinateX: Int?
    public let coordinateY: Int?
    public let maxDepth: Int?
    public let scrollCount: Int?
    public let itemSelector: String?
    public let timeout: Int?

    public init(
        action: PhoneBrowserAction,
        query: String? = nil,
        url: String? = nil,
        selector: String? = nil,
        text: String? = nil,
        direction: PhoneBrowserScrollDirection? = nil,
        amount: Int? = nil,
        tabID: Int? = nil,
        coordinateX: Int? = nil,
        coordinateY: Int? = nil,
        maxDepth: Int? = nil,
        scrollCount: Int? = nil,
        itemSelector: String? = nil,
        timeout: Int? = nil
    ) {
        self.action = action
        self.query = query
        self.url = url
        self.selector = selector
        self.text = text
        self.direction = direction
        self.amount = amount
        self.tabID = tabID
        self.coordinateX = coordinateX
        self.coordinateY = coordinateY
        self.maxDepth = maxDepth
        self.scrollCount = scrollCount
        self.itemSelector = itemSelector
        self.timeout = timeout
    }

    public init(argumentsJSON: String) throws {
        guard argumentsJSON.utf8.count <= 8_192,
              let data = argumentsJSON.data(using: .utf8),
              let values = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawAction = values["action"] as? String,
              let action = PhoneBrowserAction(rawValue: rawAction) else {
            throw PhoneBrowserError.invalidAction
        }

        let query = values["query"] as? String
        let url = values["url"] as? String
        let selector = values["selector"] as? String
        let text = values["text"] as? String
        let direction = (values["direction"] as? String).flatMap(PhoneBrowserScrollDirection.init(rawValue:))
        let amount = values["amount"] as? Int
        let tabID = values["tab_id"] as? Int
        let coordinateX = values["coordinate_x"] as? Int
        let coordinateY = values["coordinate_y"] as? Int
        let maxDepth = values["max_depth"] as? Int
        let scrollCount = values["scroll_count"] as? Int
        let itemSelector = values["item_selector"] as? String
        let timeout = values["timeout"] as? Int

        guard (query?.utf8.count ?? 0) <= 480,
              (url?.utf8.count ?? 0) <= 2_048,
              (selector?.utf8.count ?? 0) <= 500,
              (text?.utf8.count ?? 0) <= 2_000,
              (itemSelector?.utf8.count ?? 0) <= 500,
              tabID.map({ (0...999).contains($0) }) ?? true,
              amount.map({ (50...3_000).contains($0) }) ?? true,
              coordinateX.map({ (0...10_000).contains($0) }) ?? true,
              coordinateY.map({ (0...10_000).contains($0) }) ?? true,
              maxDepth.map({ (1...8).contains($0) }) ?? true,
              scrollCount.map({ (1...20).contains($0) }) ?? true,
              timeout.map({ (1...15).contains($0) }) ?? true else {
            throw PhoneBrowserError.invalidAction
        }
        if action == .search {
            guard let query, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  query.count <= 160 else { throw PhoneBrowserError.invalidQuery }
        }
        if action == .navigate {
            guard let url, !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw PhoneBrowserError.invalidURL
            }
            guard let target = URL(string: url), PhoneBrowserURLPolicy.isPublicHTTPSURL(target) else {
                throw PhoneBrowserError.invalidURL
            }
        }
        if action == .newTab, let url,
           (URL(string: url).map(PhoneBrowserURLPolicy.isPublicHTTPSURL) != true) {
            throw PhoneBrowserError.invalidURL
        }
        if action == .scroll, direction == nil {
            throw PhoneBrowserError.invalidAction
        }
        if action == .click {
            let hasSelector = !(selector?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            let hasCoordinates = coordinateX != nil && coordinateY != nil
            guard hasSelector || hasCoordinates else { throw PhoneBrowserError.invalidAction }
            guard (coordinateX == nil) == (coordinateY == nil) else { throw PhoneBrowserError.invalidAction }
        }
        if action == .type, selector?.isEmpty ?? true {
            throw PhoneBrowserError.invalidAction
        }
        if action == .type, text == nil {
            throw PhoneBrowserError.invalidAction
        }
        if action == .findElements, selector?.isEmpty ?? true {
            throw PhoneBrowserError.invalidAction
        }
        if action == .hover, selector?.isEmpty ?? true {
            throw PhoneBrowserError.invalidAction
        }

        self.init(
            action: action,
            query: query,
            url: url,
            selector: selector,
            text: text,
            direction: direction,
            amount: amount,
            tabID: tabID,
            coordinateX: coordinateX,
            coordinateY: coordinateY,
            maxDepth: maxDepth,
            scrollCount: scrollCount,
            itemSelector: itemSelector,
            timeout: timeout
        )
    }
}

public struct PhoneBrowserActionResult: Equatable, Sendable {
    public let action: PhoneBrowserAction
    public let success: Bool
    public let text: String
    public let title: String?
    public let url: String?
    public let tabID: Int?
    public let searchEngine: String?
    public let attemptedSearchEngines: [String]?
    public let isSearchResult: Bool
    public let links: [PhoneBrowserLink]?
    public let tabs: [PhoneBrowserTabSummary]?

    public init(
        action: PhoneBrowserAction,
        success: Bool = true,
        text: String,
        title: String? = nil,
        url: String? = nil,
        tabID: Int? = nil,
        searchEngine: String? = nil,
        attemptedSearchEngines: [String]? = nil,
        isSearchResult: Bool = false,
        links: [PhoneBrowserLink]? = nil,
        tabs: [PhoneBrowserTabSummary]? = nil
    ) {
        self.action = action
        self.success = success
        self.text = text
        self.title = title
        self.url = url
        self.tabID = tabID
        self.searchEngine = searchEngine
        self.attemptedSearchEngines = attemptedSearchEngines
        self.isSearchResult = isSearchResult
        self.links = links
        self.tabs = tabs
    }
}

public struct PhoneBrowserTabSummary: Codable, Equatable, Sendable {
    public let id: Int
    public let title: String
    public let url: String?
    public let isLoading: Bool

    public init(id: Int, title: String, url: String?, isLoading: Bool) {
        self.id = id
        self.title = title
        self.url = url
        self.isLoading = isLoading
    }
}

@MainActor
public protocol PhoneBrowserRuntime: AnyObject {
    func search(query: String) async throws -> PhoneBrowserPage
    func open(url: String) async throws -> PhoneBrowserPage
    func perform(_ request: PhoneBrowserActionRequest, conversationID: String) async throws -> PhoneBrowserActionResult
}

public extension PhoneBrowserRuntime {
    func perform(_ request: PhoneBrowserActionRequest, conversationID: String) async throws -> PhoneBrowserActionResult {
        let page: PhoneBrowserPage
        switch request.action {
        case .search:
            guard let query = request.query else { throw PhoneBrowserError.invalidQuery }
            page = try await search(query: query)
        case .navigate:
            guard let url = request.url else { throw PhoneBrowserError.invalidURL }
            page = try await open(url: url)
        default:
            throw PhoneBrowserError.unsupportedAction(request.action)
        }
        return PhoneBrowserActionResult(
            action: request.action,
            text: page.text,
            title: page.title,
            url: page.url,
            searchEngine: page.searchEngine,
            attemptedSearchEngines: page.attemptedSearchEngines,
            isSearchResult: request.action == .search
        )
    }
}

public enum PhoneBrowserError: LocalizedError, Equatable {
    case invalidAction
    case invalidQuery
    case invalidURL
    case pageUnavailable
    case pageBodyUnavailable(host: String, readyState: String, bodyTextLength: Int)
    case timedOut
    case tabNotFound(Int)
    case tabLimitReached
    case tabBusy(Int)
    case actionFailed(String)
    case unsupportedAction(PhoneBrowserAction)
    case searchUnavailable(attemptedEngines: [PhoneSearchEngine], lastFailure: String)

    public var errorDescription: String? {
        switch self {
        case .invalidAction: return "浏览器动作参数无效。"
        case .invalidQuery: return "搜索词无效。"
        case .invalidURL: return "只允许打开安全的公开 HTTPS 网页。"
        case .pageUnavailable: return "网页没有返回可读取的正文。"
        case let .pageBodyUnavailable(host, readyState, bodyTextLength):
            return "网页已打开，但正文不可读取（\(host)，页面状态 \(readyState)，正文字符数 \(bodyTextLength)）。"
        case .timedOut: return "网页加载超时。"
        case .tabNotFound(let tabID): return "没有找到浏览器标签 \(tabID)。请先查看当前标签列表。"
        case .tabLimitReached: return "当前对话的浏览器标签已达上限；请关闭不用的标签后再试。"
        case .tabBusy(let tabID): return "浏览器标签 \(tabID) 正在执行上一项操作，请稍后重试。"
        case .actionFailed(let message): return message
        case .unsupportedAction(let action): return "当前手机浏览器尚未实现 \(action.rawValue) 动作。"
        case let .searchUnavailable(attemptedEngines, lastFailure):
            let names = attemptedEngines.map(\.displayName).joined(separator: "、")
            return "搜索没有获得可读取的结果。已尝试：\(names.isEmpty ? "无" : names)。最后失败原因：\(lastFailure)"
        }
    }
}

public enum PhoneBrowserNavigationDisposition: Equatable {
    case allow
    case cancel
    case reject
}

public enum PhoneBrowserURLPolicy {
    public static func navigationDisposition(
        url: URL?,
        hasTargetFrame: Bool,
        isMainFrame: Bool
    ) -> PhoneBrowserNavigationDisposition {
        // OpenMinis keeps WKWebView's safe page-local frames working (including
        // about:blank and blob-backed content), while blocking app-link schemes.
        // OpenMuse applies a stricter public-HTTPS rule to top-level pages and
        // cancels unsafe child frames without failing the containing result page.
        guard hasTargetFrame else { return .cancel }
        guard let url else { return isMainFrame ? .reject : .cancel }

        if isPublicHTTPSURL(url) { return .allow }
        guard !isMainFrame else { return .reject }

        switch url.scheme?.lowercased() {
        case "about":
            let localPage = url.absoluteString.lowercased()
            return ["about:blank", "about:srcdoc"].contains(localPage) ? .allow : .cancel
        case "blob":
            let nestedURL = String(url.absoluteString.dropFirst("blob:".count))
            guard let creator = URL(string: nestedURL), isPublicHTTPSURL(creator) else { return .cancel }
            return .allow
        default:
            return .cancel
        }
    }

    public static func isPublicHTTPSURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              url.user == nil, url.password == nil,
              let host = url.host?.lowercased(), host.contains("."),
              host != "localhost", !host.hasSuffix(".localhost"), !host.hasSuffix(".local"),
              !host.contains(":"), !host.hasSuffix(".internal") else {
            return false
        }
        let octets = host.split(separator: ".").compactMap { UInt8($0) }
        if octets.count == 4 {
            let a = Int(octets[0]), b = Int(octets[1])
            if a == 0 || a == 10 || a == 127 || a >= 224 ||
                (a == 169 && b == 254) ||
                (a == 172 && (16...31).contains(b)) ||
                (a == 192 && b == 168) ||
                (a == 100 && (64...127).contains(b)) ||
                (a == 198 && (18...19).contains(b)) {
                return false
            }
        }
        return true
    }
}
