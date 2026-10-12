import Foundation
import OpenMuseCore
import WebKit

@MainActor
final class IOSPhoneBrowserRuntime: NSObject, PhoneBrowserRuntime, WKNavigationDelegate, WKUIDelegate {
    private static let maximumTabsPerConversation = 3
    private static let maximumLiveTabs = 8
    private static let idleTabLifetime: TimeInterval = 15 * 60
    private static let navigationTimeout: TimeInterval = 30
    private static let persistenceKeyPrefix = "openmuse.phoneBrowser.tabs."
    // Match OpenMinis' headless mobile-browser viewport. A zero-sized WKWebView
    // can navigate but does not reliably lay out pages for DOM extraction.
    private static let mobileViewport = CGSize(width: 390, height: 844)

    private let userDefaults: UserDefaults
    private let processPool = WKProcessPool()
    private var tabsByConversation: [String: [Int: BrowserTab]] = [:]
    private var selectedTabIDs: [String: Int] = [:]
    private var nextTabID = 1

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        super.init()
    }

    func search(query: String) async throws -> PhoneBrowserPage {
        let result = try await perform(
            PhoneBrowserActionRequest(action: .search, query: query),
            conversationID: "legacy"
        )
        return PhoneBrowserPage(
            title: result.title ?? "",
            url: result.url ?? "",
            text: result.text,
            searchEngine: result.searchEngine,
            attemptedSearchEngines: result.attemptedSearchEngines
        )
    }

    func open(url: String) async throws -> PhoneBrowserPage {
        let result = try await perform(
            PhoneBrowserActionRequest(action: .navigate, url: url),
            conversationID: "legacy"
        )
        return PhoneBrowserPage(title: result.title ?? "", url: result.url ?? "", text: result.text)
    }

    func perform(_ request: PhoneBrowserActionRequest, conversationID: String) async throws -> PhoneBrowserActionResult {
        guard !conversationID.isEmpty, conversationID.utf8.count <= 200 else {
            throw PhoneBrowserError.invalidAction
        }
        pruneExpiredTabs()

        switch request.action {
        case .listTabs:
            return listTabs(conversationID: conversationID)
        case .newTab:
            let tab = try createTab(conversationID: conversationID)
            selectedTabIDs[conversationID] = tab.id
            if let rawURL = request.url {
                let page = try await withTabLock(tab) {
                    try await self.load(self.validPublicURL(rawURL), in: tab)
                }
                return actionResult(.newTab, page: page, tab: tab)
            }
            persistTabs(for: conversationID)
            return PhoneBrowserActionResult(
                action: .newTab,
                text: "已创建空白浏览器标签。",
                title: "新标签",
                tabID: tab.id,
                tabs: tabSummaries(conversationID: conversationID)
            )
        case .closeTab:
            guard let tab = try tabForAction(request, conversationID: conversationID, createIfMissing: false) else {
                throw PhoneBrowserError.pageUnavailable
            }
            guard !tab.isBusy else { throw PhoneBrowserError.tabBusy(tab.id) }
            tab.webView.stopLoading()
            tab.webView.navigationDelegate = nil
            tab.webView.uiDelegate = nil
            tabsByConversation[conversationID]?.removeValue(forKey: tab.id)
            if tabsByConversation[conversationID]?.isEmpty == true {
                tabsByConversation.removeValue(forKey: conversationID)
            }
            if selectedTabIDs[conversationID] == tab.id {
                selectedTabIDs[conversationID] = tabsByConversation[conversationID]?.keys.max()
            }
            persistTabs(for: conversationID, excluding: [tab.id])
            return PhoneBrowserActionResult(
                action: .closeTab,
                text: "已关闭浏览器标签 \(tab.id)。",
                tabID: tab.id,
                tabs: tabSummaries(conversationID: conversationID)
            )
        case .search:
            return try await withSelectedTab(request, conversationID: conversationID) { tab in
                try await self.search(request.query ?? "", in: tab)
            }
        case .navigate:
            guard let rawURL = request.url else { throw PhoneBrowserError.invalidURL }
            return try await withSelectedTab(request, conversationID: conversationID) { tab in
                let page = try await self.load(self.validPublicURL(rawURL), in: tab)
                tab.searchEngine = nil
                tab.attemptedSearchEngines = nil
                return self.actionResult(.navigate, page: page, tab: tab)
            }
        case .getReadable, .getText, .getPageInfo, .getBackbone, .findElements, .click, .type, .hover, .scroll, .scrollAndCollect, .waitForDOMStable:
            return try await withSelectedTab(request, conversationID: conversationID) { tab in
                try await self.performPageAction(request, in: tab)
            }
        }
    }

    private func search(_ rawQuery: String, in tab: BrowserTab) async throws -> PhoneBrowserActionResult {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, query.count <= 160 else { throw PhoneBrowserError.invalidQuery }
        let engines = PhoneSearchEnginePreferences(userDefaults: userDefaults).enginesToTry
        var attempted: [PhoneSearchEngine] = []
        var lastFailure: Error = PhoneBrowserError.pageUnavailable

        for engine in engines {
            guard let url = engine.searchURL(query: query) else { continue }
            attempted.append(engine)
            do {
                let page = try await load(url, in: tab)
                guard Self.isUsableSearchPage(page) else {
                    lastFailure = PhoneBrowserError.pageUnavailable
                    continue
                }
                tab.searchEngine = engine.rawValue
                tab.attemptedSearchEngines = attempted.map(\.rawValue)
                return actionResult(.search, page: page, tab: tab, isSearchResult: true)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastFailure = error
            }
        }

        tab.searchEngine = nil
        tab.attemptedSearchEngines = attempted.map(\.rawValue)
        throw PhoneBrowserError.searchUnavailable(
            attemptedEngines: attempted,
            lastFailure: lastFailure.localizedDescription
        )
    }

    private func performPageAction(
        _ request: PhoneBrowserActionRequest,
        in tab: BrowserTab
    ) async throws -> PhoneBrowserActionResult {
        let page = try await restorePageIfNeeded(in: tab)
        switch request.action {
        case .getReadable:
            let refreshed = try await readPage(in: tab, waitForStableDOM: true)
            return actionResult(.getReadable, page: refreshed, tab: tab)
        case .getText:
            let refreshed = try await readPage(in: tab, waitForStableDOM: true)
            if let selector = request.selector {
                let script = """
                (() => {
                  const el = document.querySelector(\(try jsString(selector)));
                  return el ? (el.innerText || el.textContent || '').replace(/\\s+/g, ' ').trim().slice(0, 18000) : null;
                })()
                """
                guard let selected = try await tab.webView.evaluateJavaScript(script) as? String else {
                    throw PhoneBrowserError.pageUnavailable
                }
                return actionResult(.getText, page: refreshed, tab: tab, text: String(selected.prefix(18_000)))
            }
            return actionResult(.getText, page: refreshed, tab: tab)
        case .getPageInfo:
            let info = try await readPage(in: tab, waitForStableDOM: false)
            return PhoneBrowserActionResult(
                action: .getPageInfo,
                text: "title: \(info.title)\nurl: \(info.url)",
                title: info.title,
                url: info.url,
                tabID: tab.id,
                searchEngine: tab.searchEngine,
                attemptedSearchEngines: tab.attemptedSearchEngines
            )
        case .getBackbone:
            let depth = min(max(request.maxDepth ?? 4, 1), 8)
            let rootSelector = try jsString(request.selector ?? "body")
            let script = """
            (() => {
              const root = document.querySelector(\(rootSelector));
              if (!root) return {error:'找不到页面结构起点'};
              let visited = 0;
              const ignored = new Set(['SCRIPT','STYLE','NOSCRIPT','SVG','PATH']);
              function node(el, depth) {
                if (!el || ignored.has(el.tagName) || visited >= 120) return null;
                visited += 1;
                const result = {tag: el.tagName.toLowerCase()};
                if (el.id) result.id = el.id.slice(0,80);
                if (typeof el.className === 'string' && el.className.trim()) result.class = el.className.trim().split(/\\s+/).slice(0,4).join('.').slice(0,100);
                const role = el.getAttribute('role'); if (role) result.role = role.slice(0,60);
                const label = el.getAttribute('aria-label') || el.getAttribute('title'); if (label) result.label = label.trim().slice(0,120);
                const text = (el.children.length ? '' : (el.innerText || el.textContent || '')).replace(/\\s+/g,' ').trim();
                if (text) result.text = text.slice(0,100);
                if (el instanceof HTMLAnchorElement && el.href) result.href = el.href.slice(0,300);
                if (depth < \(depth) && el.children.length) {
                  const children = [];
                  for (const child of el.children) {
                    if (visited >= 120) break;
                    const item = node(child, depth + 1); if (item) children.push(item);
                  }
                  if (children.length) result.children = children;
                }
                return result;
              }
              return {title:document.title, url:location.href, tree:node(root,0), truncated:visited >= 120};
            })()
            """
            let value = try await tab.webView.evaluateJavaScript(script) ?? [:]
            let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .fragmentsAllowed])
            let structure = String(decoding: data, as: UTF8.self)
            return actionResult(.getBackbone, page: page, tab: tab, text: String(structure.prefix(8_000)))
        case .findElements:
            guard let selector = request.selector else { throw PhoneBrowserError.invalidAction }
            let script = """
            (() => {
              const selector = \(try jsString(selector));
              try {
                return Array.from(document.querySelectorAll(selector)).slice(0, 50).map((el, index) => ({
                  index, tag: el.tagName.toLowerCase(), text: (el.innerText || el.textContent || '').replace(/\\s+/g, ' ').trim().slice(0, 240),
                  href: el.href || null, role: el.getAttribute('role'), type: el.getAttribute('type'),
                  ariaLabel: el.getAttribute('aria-label'), disabled: Boolean(el.disabled)
                }));
              } catch (error) { return {error: String(error)}; }
            })()
            """
            let matches = try await tab.webView.evaluateJavaScript(script)
            let data = try JSONSerialization.data(withJSONObject: matches ?? [], options: [.sortedKeys, .fragmentsAllowed])
            let resultText = String(decoding: data, as: UTF8.self)
            return actionResult(.findElements, page: page, tab: tab, text: String(resultText.prefix(8_000)))
        case .click:
            let target: String
            if let selector = request.selector {
                target = "document.querySelector(\(try jsString(selector)))"
            } else if let x = request.coordinateX, let y = request.coordinateY {
                target = "document.elementFromPoint(\(x), \(y))"
            } else {
                throw PhoneBrowserError.invalidAction
            }
            let script = """
            (() => {
              const el = \(target);
              if (!el) return {ok:false, error:'目标元素不存在'};
              el.scrollIntoView({block:'center', inline:'center'});
              const summary = (el.innerText || el.getAttribute('aria-label') || el.title || '').replace(/\\s+/g, ' ').trim().slice(0, 160);
              const actionLabel = (summary + ' ' + (el.getAttribute('type') || '') + ' ' + (el.getAttribute('aria-label') || '')).toLowerCase();
              if (el.closest('form') && (el.matches('button, input[type=submit], input[type=image]') || el.getAttribute('role') === 'button'))
                return {ok:false, error:'这个动作会提交网页表单；手机浏览器不会代替你提交。'};
              if (/(buy|purchase|pay|send|submit|book|reserve|delete|remove|cancel|checkout|order|购买|付款|支付|发送|提交|预订|删除|取消|下单)/i.test(actionLabel))
                return {ok:false, error:'这个动作可能产生外部副作用；请由你本人确认后操作。'};
              el.click();
              return {ok:true, tag:el.tagName.toLowerCase(), text:summary};
            })()
            """
            let outcome = try await tab.webView.evaluateJavaScript(script) as? [String: Any]
            guard outcome?["ok"] as? Bool == true else {
                throw PhoneBrowserError.actionFailed(outcome?["error"] as? String ?? "点击目标不可用。")
            }
            try await waitForNavigationToSettle(in: tab)
            let refreshed = try await readPage(in: tab, waitForStableDOM: true)
            return actionResult(.click, page: refreshed, tab: tab, text: "点击完成：\(outcome?["text"] as? String ?? "页面元素")")
        case .hover:
            guard let selector = request.selector else { throw PhoneBrowserError.invalidAction }
            let script = """
            (() => {
              const el = document.querySelector(\(try jsString(selector)));
              if (!el) return {ok:false,error:'目标元素不存在'};
              el.scrollIntoView({block:'center',inline:'center'});
              const common = {bubbles:true,cancelable:true,view:window};
              el.dispatchEvent(new PointerEvent('pointerover',{...common,pointerType:'mouse'}));
              el.dispatchEvent(new MouseEvent('mouseover',common));
              el.dispatchEvent(new MouseEvent('mouseenter',{...common,bubbles:false}));
              return {ok:true,tag:el.tagName.toLowerCase(),text:(el.innerText||el.getAttribute('aria-label')||'').replace(/\\s+/g,' ').trim().slice(0,160)};
            })()
            """
            let outcome = try await tab.webView.evaluateJavaScript(script) as? [String: Any]
            guard outcome?["ok"] as? Bool == true else {
                throw PhoneBrowserError.actionFailed(outcome?["error"] as? String ?? "悬停目标不可用。")
            }
            try await waitForDOMStability(in: tab.webView, timeout: 3)
            let refreshed = try await readPage(in: tab, waitForStableDOM: false)
            let label = outcome?["text"] as? String ?? outcome?["tag"] as? String ?? "页面元素"
            return actionResult(.hover, page: refreshed, tab: tab, text: "已在 \(label) 上触发悬停交互。")
        case .type:
            guard let selector = request.selector, let text = request.text else { throw PhoneBrowserError.invalidAction }
            let script = """
            (() => {
              const el = document.querySelector(\(try jsString(selector)));
              if (!el) return {ok:false, error:'目标输入框不存在'};
              if (!(el instanceof HTMLInputElement || el instanceof HTMLTextAreaElement || el.isContentEditable))
                return {ok:false, error:'目标元素不是可输入控件'};
              if (el instanceof HTMLInputElement && (el.type === 'password' || /password|one-time-code/i.test(el.autocomplete)))
                return {ok:false, error:'本机浏览器不向密码或一次性验证码字段输入内容。'};
              el.focus();
              if (el.isContentEditable) el.textContent = \(try jsString(text));
              else {
                const descriptor = Object.getOwnPropertyDescriptor(Object.getPrototypeOf(el), 'value');
                if (descriptor && descriptor.set) descriptor.set.call(el, \(try jsString(text)));
                else el.value = \(try jsString(text));
              }
              el.dispatchEvent(new InputEvent('input', {bubbles:true, inputType:'insertText', data:\(try jsString(text))}));
              el.dispatchEvent(new Event('change', {bubbles:true}));
              return {ok:true, length:\(text.count)};
            })()
            """
            let outcome = try await tab.webView.evaluateJavaScript(script) as? [String: Any]
            guard outcome?["ok"] as? Bool == true else {
                throw PhoneBrowserError.actionFailed(outcome?["error"] as? String ?? "输入目标不可用。")
            }
            try await waitForNavigationToSettle(in: tab)
            try await waitForDOMStability(in: tab.webView, timeout: 5)
            let refreshed = try await readPage(in: tab, waitForStableDOM: false)
            return actionResult(.type, page: refreshed, tab: tab, text: "已在页面输入 \(outcome?["length"] as? Int ?? 0) 个字符；未主动提交表单。")
        case .scroll:
            guard let direction = request.direction else { throw PhoneBrowserError.invalidAction }
            let amount = min(max(request.amount ?? 500, 50), 3_000)
            let delta = direction == .down ? amount : -amount
            let script: String
            if let selector = request.selector {
                script = """
                (() => { const el=document.querySelector(\(try jsString(selector))); if(!el) return false; el.scrollBy({top:\(delta),behavior:'instant'}); return true; })()
                """
            } else {
                script = "window.scrollBy({top:\(delta),behavior:'instant'}); true"
            }
            guard try await tab.webView.evaluateJavaScript(script) as? Bool == true else {
                throw PhoneBrowserError.actionFailed("找不到可滚动的页面区域。")
            }
            try await waitForNavigationToSettle(in: tab)
            try await waitForDOMStability(in: tab.webView, timeout: 5)
            let refreshed = try await readPage(in: tab, waitForStableDOM: false)
            return actionResult(.scroll, page: refreshed, tab: tab, text: "页面已向\(direction == .down ? "下" : "上")滚动 \(amount) 像素。")
        case .scrollAndCollect:
            let scrollCount = min(max(request.scrollCount ?? 10, 1), 20)
            let amount = min(max(request.amount ?? 500, 50), 3_000)
            let direction = request.direction ?? .down
            let pixels = direction == .down ? amount : -amount
            let itemSelector = try jsString(request.itemSelector ?? "")
            let containerSelector = try jsString(request.selector ?? "")
            let timeoutMilliseconds = min(max(request.timeout ?? 8, 1), 15) * 1_000
            let script = """
            return await (async () => {
              const containerSelector = \(containerSelector);
              let scrollTarget = null;
              let scroll;
              if (containerSelector) {
                scrollTarget = document.querySelector(containerSelector);
                if (!scrollTarget) return {error:'找不到可滚动的页面区域'};
                scroll = () => scrollTarget.scrollBy({top:\(pixels),behavior:'instant'});
              } else {
                const beforeY = window.scrollY;
                window.scrollBy({top:\(pixels),behavior:'instant'});
                if (window.scrollY !== beforeY) {
                  window.scrollBy({top:-\(pixels),behavior:'instant'});
                  scrollTarget = document.body;
                  scroll = () => window.scrollBy({top:\(pixels),behavior:'instant'});
                } else {
                  let best = null, bestArea = 0, visited = 0;
                  const walk = (el, depth) => {
                    if (depth > 10 || visited > 500) return;
                    for (const child of el.children) {
                      visited++;
                      const style = getComputedStyle(child);
                      if ((style.overflowY === 'auto' || style.overflowY === 'scroll') && child.scrollHeight > child.clientHeight + 5) {
                        const area = child.clientWidth * child.clientHeight;
                        if (area > bestArea) { best = child; bestArea = area; }
                      }
                      walk(child, depth + 1);
                    }
                  };
                  walk(document.body,0);
                  scrollTarget = best || document.documentElement;
                  scroll = best
                    ? () => best.scrollBy({top:\(pixels),behavior:'instant'})
                    : () => { document.documentElement.scrollTop += \(pixels); };
                }
              }
              let effectiveSelector = \(itemSelector) || null;
              if (!effectiveSelector) {
                for (const candidate of ['article','[role="article"]','[data-testid]','li']) {
                  if (scrollTarget.querySelectorAll(candidate).length >= 3) { effectiveSelector = candidate; break; }
                }
                if (!effectiveSelector) {
                  const counts = {};
                  for (const child of scrollTarget.children) counts[child.tagName] = (counts[child.tagName] || 0) + 1;
                  const bestTag = Object.keys(counts).sort((a,b) => counts[b] - counts[a])[0];
                  effectiveSelector = bestTag && counts[bestTag] >= 3 ? ':scope > ' + bestTag.toLowerCase() : ':scope > *';
                }
              }
              const seen = new Set();
              const items = [];
              let totalSeen = 0, totalCharacters = 0;
              const collect = () => {
                let nodes;
                try { nodes = scrollTarget.querySelectorAll(effectiveSelector); }
                catch (error) { return {error:String(error)}; }
                let added = 0;
                for (const el of Array.from(nodes).slice(0,500)) {
                  const text = (el.innerText || '').replace(/\\s+/g,' ').trim();
                  if (!text) continue;
                  totalSeen++;
                  const key = text.slice(0,80);
                  if (seen.has(key)) continue;
                  seen.add(key);
                  const remaining = 7_000 - totalCharacters;
                  if (remaining <= 0 || items.length >= 40) break;
                  const item = text.slice(0,Math.min(400,remaining));
                  items.push(item); totalCharacters += item.length; added++;
                  if (totalCharacters >= 7_000 || items.length >= 40) break;
                }
                return {added};
              };
              const startedAt = Date.now();
              let steps = 0;
              let initial = collect();
              if (initial.error) return initial;
              for (let i=0;i<\(scrollCount) && items.length<40 && totalCharacters<7_000;i++) {
                if (Date.now() - startedAt >= \(timeoutMilliseconds)) break;
                let mutated = false, resolveMutation;
                const mutation = new Promise(resolve => { resolveMutation = resolve; });
                const observer = new MutationObserver(() => { mutated = true; resolveMutation(); });
                observer.observe(scrollTarget,{childList:true,subtree:true});
                scroll(); steps++;
                const remaining = Math.max(1,\(timeoutMilliseconds) - (Date.now() - startedAt));
                await Promise.race([mutation,new Promise(resolve=>setTimeout(resolve,Math.min(1_500,remaining)))]);
                if (mutated) {
                  const settleUntil = Math.min(Date.now() + 700, startedAt + \(timeoutMilliseconds));
                  while (Date.now() < settleUntil) {
                    mutated = false;
                    await new Promise(resolve=>setTimeout(resolve,200));
                    if (!mutated) break;
                  }
                }
                observer.disconnect();
                await new Promise(resolve=>setTimeout(resolve,100));
                const result = collect();
                if (result.error) return result;
                if (result.added === 0) break;
              }
              const scrollPosition = scrollTarget === document.body || scrollTarget === document.documentElement
                ? window.scrollY : scrollTarget.scrollTop;
              return {itemsCollected:items.length,totalItemsSeen:totalSeen,scrollSteps:steps,scrollPosition,itemSelector:effectiveSelector,items};
            })();
            """
            let rawValue = try await tab.webView.callAsyncJavaScript(
                script,
                arguments: [:],
                in: nil,
                contentWorld: .page
            )
            guard let value = rawValue as? [String: Any] else {
                throw PhoneBrowserError.actionFailed("页面采集没有返回结构化结果。")
            }
            if let error = (value as? [String: Any])?["error"] as? String {
                throw PhoneBrowserError.actionFailed(error)
            }
            let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .fragmentsAllowed])
            let collected = String(decoding: data, as: UTF8.self)
            let refreshed = try await readPage(in: tab, waitForStableDOM: false)
            return actionResult(.scrollAndCollect, page: refreshed, tab: tab, text: String(collected.prefix(8_000)))
        case .waitForDOMStable:
            try await waitForNavigationToSettle(in: tab)
            let stable = try await waitForDOMStability(in: tab.webView, timeout: 10)
            let refreshed = try await readPage(in: tab, waitForStableDOM: false)
            return actionResult(.waitForDOMStable, page: refreshed, tab: tab, text: stable ? "页面 DOM 已稳定。" : "等待达到 10 秒上限，页面仍有变化。")
        case .search, .navigate, .newTab, .closeTab, .listTabs:
            break
        }
        throw PhoneBrowserError.unsupportedAction(request.action)
    }

    private func withSelectedTab(
        _ request: PhoneBrowserActionRequest,
        conversationID: String,
        action: (BrowserTab) async throws -> PhoneBrowserActionResult
    ) async throws -> PhoneBrowserActionResult {
        guard let tab = try tabForAction(request, conversationID: conversationID, createIfMissing: request.action == .search || request.action == .navigate) else {
            throw PhoneBrowserError.pageUnavailable
        }
        return try await withTabLock(tab) { try await action(tab) }
    }

    private func withTabLock<T>(_ tab: BrowserTab, operation: () async throws -> T) async throws -> T {
        guard !tab.isBusy else { throw PhoneBrowserError.tabBusy(tab.id) }
        tab.isBusy = true
        defer {
            tab.isBusy = false
            tab.lastUsedAt = .now
            persistTabs(for: tab.conversationID)
        }
        try Task.checkCancellation()
        return try await operation()
    }

    private func tabForAction(
        _ request: PhoneBrowserActionRequest,
        conversationID: String,
        createIfMissing: Bool
    ) throws -> BrowserTab? {
        if let requestedID = request.tabID {
            if let live = tabsByConversation[conversationID]?[requestedID] { return live }
            if let saved = savedTabs(for: conversationID).first(where: { $0.id == requestedID }) {
                nextTabID = max(nextTabID, requestedID + 1)
                let restored = makeTab(id: saved.id, conversationID: conversationID, restoredURL: saved.url, title: saved.title)
                tabsByConversation[conversationID, default: [:]][restored.id] = restored
                selectedTabIDs[conversationID] = restored.id
                return restored
            }
            throw PhoneBrowserError.tabNotFound(requestedID)
        }
        if let selected = selectedTabIDs[conversationID],
           let tab = tabsByConversation[conversationID]?[selected] {
            return tab
        }
        if let savedSelection = savedSelectionID(for: conversationID),
           let saved = savedTabs(for: conversationID).first(where: { $0.id == savedSelection }) {
            nextTabID = max(nextTabID, saved.id + 1)
            let restored = makeTab(id: saved.id, conversationID: conversationID, restoredURL: saved.url, title: saved.title)
            tabsByConversation[conversationID, default: [:]][restored.id] = restored
            selectedTabIDs[conversationID] = restored.id
            return restored
        }
        if let existing = tabsByConversation[conversationID]?.values.max(by: { $0.lastUsedAt < $1.lastUsedAt }) {
            selectedTabIDs[conversationID] = existing.id
            return existing
        }
        guard createIfMissing else { return nil }
        let tab = try createTab(conversationID: conversationID)
        selectedTabIDs[conversationID] = tab.id
        return tab
    }

    private func createTab(conversationID: String) throws -> BrowserTab {
        nextTabID = max(nextTabID, (savedTabs(for: conversationID).map(\.id).max() ?? 0) + 1)
        let live = tabsByConversation[conversationID, default: [:]]
        guard live.count + savedTabs(for: conversationID).filter({ live[$0.id] == nil }).count < Self.maximumTabsPerConversation else {
            throw PhoneBrowserError.tabLimitReached
        }
        try makeRoomForLiveTabIfNeeded()
        let tab = makeTab(id: nextTabID, conversationID: conversationID, restoredURL: nil, title: "新标签")
        nextTabID += 1
        tabsByConversation[conversationID, default: [:]][tab.id] = tab
        selectedTabIDs[conversationID] = tab.id
        persistTabs(for: conversationID)
        return tab
    }

    private func makeRoomForLiveTabIfNeeded() throws {
        let allTabs = tabsByConversation.values.flatMap(\.values)
        guard allTabs.count >= Self.maximumLiveTabs else {
            return
        }
        guard let victim = allTabs.filter({ !$0.isBusy }).min(by: { $0.lastUsedAt < $1.lastUsedAt }) else {
            throw PhoneBrowserError.tabLimitReached
        }
        victim.webView.stopLoading()
        victim.webView.navigationDelegate = nil
        victim.webView.uiDelegate = nil
        tabsByConversation[victim.conversationID]?.removeValue(forKey: victim.id)
        persistTabs(for: victim.conversationID)
    }

    private func makeTab(id: Int, conversationID: String, restoredURL: String?, title: String) -> BrowserTab {
        let configuration = WKWebViewConfiguration()
        // OpenMinis uses WKWebsiteDataStore.default() for its persistent tab pool.
        // Keep ordinary site session data across app launches; the model tool
        // still cannot read cookies or sign in on the user's behalf.
        configuration.websiteDataStore = .default()
        configuration.processPool = processPool
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.defaultWebpagePreferences.preferredContentMode = .mobile
        let webView = WKWebView(frame: CGRect(origin: .zero, size: Self.mobileViewport), configuration: configuration)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        return BrowserTab(
            id: id,
            conversationID: conversationID,
            webView: webView,
            restoredURL: restoredURL,
            title: title
        )
    }

    private func load(_ url: URL, in tab: BrowserTab) async throws -> PhoneBrowserPage {
        guard PhoneBrowserURLPolicy.isPublicHTTPSURL(url) else { throw PhoneBrowserError.invalidURL }
        tab.restoredURL = nil
        tab.lastNavigationError = nil
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<PhoneBrowserPage, Error>) in
                guard tab.navigationContinuation == nil else {
                    continuation.resume(throwing: PhoneBrowserError.tabBusy(tab.id))
                    return
                }
                tab.navigationContinuation = continuation
                tab.timeoutTask = Task { @MainActor [weak self, weak tab] in
                    try? await Task.sleep(nanoseconds: UInt64(Self.navigationTimeout * 1_000_000_000))
                    guard !Task.isCancelled, let self, let tab else { return }
                    self.finishNavigation(.failure(PhoneBrowserError.timedOut), for: tab)
                }
                let request = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: Self.navigationTimeout)
                tab.webView.load(request)
            }
        } onCancel: {
            Task { @MainActor [weak self, weak tab] in
                guard let self, let tab else { return }
                self.finishNavigation(.failure(CancellationError()), for: tab)
            }
        }
    }

    private func restorePageIfNeeded(in tab: BrowserTab) async throws -> PhoneBrowserPage {
        if let rawURL = tab.restoredURL {
            let url = try validPublicURL(rawURL)
            tab.restoredURL = nil
            return try await load(url, in: tab)
        }
        guard let url = tab.webView.url,
              PhoneBrowserURLPolicy.isPublicHTTPSURL(url) else { throw PhoneBrowserError.pageUnavailable }
        return try await readPage(in: tab, waitForStableDOM: false)
    }

    private func readPage(in tab: BrowserTab, waitForStableDOM: Bool) async throws -> PhoneBrowserPage {
        if tab.webView.isLoading { try await waitForNavigationToSettle(in: tab) }
        if waitForStableDOM { _ = try await waitForDOMStability(in: tab.webView, timeout: 5) }
        let script = """
        (() => {
          const clean = value => (value || '').replace(/\\s+/g, ' ').trim();
          const body = document.body;
          const candidates = ['article', '[role="main"]', 'main', '.post-content', '.article-body', '.entry-content', '#content', '.content'];
          let readableRoot = body;
          for (const selector of candidates) {
            const candidate = document.querySelector(selector);
            if (candidate && getComputedStyle(candidate).display !== 'none' && clean(candidate.innerText).length > 0) {
              readableRoot = candidate;
              break;
            }
          }
          const innerText = clean(readableRoot ? readableRoot.innerText : '');
          let text = innerText;
          if (!text && readableRoot) {
            const clone = readableRoot.cloneNode(true);
            clone.querySelectorAll('script,style,noscript,template').forEach(node => node.remove());
            text = clean(clone.textContent);
          }
          text = text.slice(0, 18000);
          const links = Array.from(document.querySelectorAll('a[href]'))
            .map(a => ({title: clean(a.innerText || a.getAttribute('aria-label') || a.title), url: a.href}))
            .filter(link => link.title && /^https:\\/\\//i.test(link.url))
            .slice(0, 30);
          return {
            title: clean(document.title), url: location.href, text, links,
            readyState: document.readyState,
            bodyTextLength: clean(body ? (body.innerText || body.textContent || '') : '').length
          };
        })()
        """
        guard let dictionary = try await tab.webView.evaluateJavaScript(script) as? [String: Any],
              let rawURL = dictionary["url"] as? String,
              let pageURL = URL(string: rawURL), PhoneBrowserURLPolicy.isPublicHTTPSURL(pageURL) else {
            throw PhoneBrowserError.pageUnavailable
        }
        guard let text = dictionary["text"] as? String, !text.isEmpty else {
            throw PhoneBrowserError.pageBodyUnavailable(
                host: pageURL.host ?? "网页",
                readyState: dictionary["readyState"] as? String ?? "unknown",
                bodyTextLength: dictionary["bodyTextLength"] as? Int ?? 0
            )
        }
        let links = (dictionary["links"] as? [[String: String]] ?? []).compactMap { link -> PhoneBrowserLink? in
            guard let title = link["title"], let rawURL = link["url"],
                  let url = URL(string: rawURL), PhoneBrowserURLPolicy.isPublicHTTPSURL(url) else { return nil }
            return PhoneBrowserLink(title: String(title.prefix(200)), url: rawURL)
        }
        let page = PhoneBrowserPage(
            title: String((dictionary["title"] as? String ?? "").prefix(300)),
            url: rawURL,
            text: String(text.prefix(18_000)),
            links: Array(links.prefix(20)),
            searchEngine: tab.searchEngine,
            attemptedSearchEngines: tab.attemptedSearchEngines
        )
        tab.title = page.title.isEmpty ? (pageURL.host ?? "网页") : page.title
        tab.currentURL = rawURL
        persistTabs(for: tab.conversationID)
        return page
    }

    @discardableResult
    private func waitForDOMStability(in webView: WKWebView, timeout: TimeInterval) async throws -> Bool {
        let installObserver = """
        if (window.__openMuseBrowserObserver) window.__openMuseBrowserObserver.disconnect();
        window.__openMuseBrowserMutationCount = 0;
        window.__openMuseBrowserObserver = new MutationObserver(() => { window.__openMuseBrowserMutationCount++; });
        if (document.documentElement) window.__openMuseBrowserObserver.observe(document.documentElement,
          {childList:true, subtree:true, attributes:true, characterData:true});
        return 0;
        """
        _ = try? await webView.evaluateJavaScript(installObserver)
        let deadline = Date.now.addingTimeInterval(timeout)
        var previousTotal = 0
        var previousDelta = Int.max
        var stableIntervals = 0
        while Date.now < deadline {
            try Task.checkCancellation()
            try await Task.sleep(nanoseconds: 500_000_000)
            let rawCount = try? await webView.evaluateJavaScript("window.__openMuseBrowserMutationCount || 0")
            let total: Int
            if let number = rawCount as? Int { total = number }
            else if let number = rawCount as? NSNumber { total = number.intValue }
            else { break }
            let delta = max(0, total - previousTotal)
            if delta <= previousDelta { stableIntervals += 1 } else { stableIntervals = 0 }
            previousTotal = total
            previousDelta = delta
            if stableIntervals >= 3 {
                _ = try? await webView.evaluateJavaScript("window.__openMuseBrowserObserver?.disconnect(); window.__openMuseBrowserObserver=null;")
                return true
            }
        }
        _ = try? await webView.evaluateJavaScript("window.__openMuseBrowserObserver?.disconnect(); window.__openMuseBrowserObserver=null;")
        return false
    }

    private func waitForNavigationToSettle(in tab: BrowserTab?) async throws {
        guard let tab else { return }
        let deadline = Date().addingTimeInterval(Self.navigationTimeout)
        while tab.webView.isLoading, Date() < deadline {
            try Task.checkCancellation()
            if let error = tab.lastNavigationError { throw error }
            try await Task.sleep(nanoseconds: 250_000_000)
        }
        guard !tab.webView.isLoading else { throw PhoneBrowserError.timedOut }
        if let error = tab.lastNavigationError {
            tab.lastNavigationError = nil
            throw error
        }
    }

    private func waitForNavigationToSettle(in tab: BrowserTab) async throws {
        try await waitForNavigationToSettle(in: Optional(tab))
    }

    private func listTabs(conversationID: String) -> PhoneBrowserActionResult {
        let summaries = tabSummaries(conversationID: conversationID)
        let text = summaries.isEmpty
            ? "当前对话还没有浏览器标签。使用 navigate、search 或 new_tab 创建一个。"
            : summaries.map { "tab_id \($0.id): \($0.title) | \($0.url ?? "about:blank")\($0.isLoading ? " | 正在加载" : "")" }.joined(separator: "\n")
        return PhoneBrowserActionResult(action: .listTabs, text: text, tabs: summaries)
    }

    private func tabSummaries(conversationID: String) -> [PhoneBrowserTabSummary] {
        var byID = Dictionary(uniqueKeysWithValues: savedTabs(for: conversationID).map { ($0.id, $0) })
        for tab in tabsByConversation[conversationID, default: [:]].values {
            byID[tab.id] = SavedBrowserTab(id: tab.id, title: tab.title, url: tab.currentURL ?? tab.restoredURL)
        }
        return byID.values.sorted { $0.id < $1.id }.map { saved in
            PhoneBrowserTabSummary(
                id: saved.id,
                title: saved.title,
                url: saved.url,
                isLoading: tabsByConversation[conversationID]?[saved.id]?.webView.isLoading ?? false
            )
        }
    }

    private func actionResult(
        _ action: PhoneBrowserAction,
        page: PhoneBrowserPage,
        tab: BrowserTab,
        text: String? = nil,
        isSearchResult: Bool = false
    ) -> PhoneBrowserActionResult {
        let body = text ?? page.text
        return PhoneBrowserActionResult(
            action: action,
            text: body,
            title: page.title,
            url: page.url,
            tabID: tab.id,
            searchEngine: tab.searchEngine,
            attemptedSearchEngines: tab.attemptedSearchEngines,
            isSearchResult: isSearchResult,
            links: page.links
        )
    }

    private func validPublicURL(_ rawURL: String) throws -> URL {
        guard let url = URL(string: rawURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              PhoneBrowserURLPolicy.isPublicHTTPSURL(url) else { throw PhoneBrowserError.invalidURL }
        return url
    }

    private func findTab(for webView: WKWebView) -> BrowserTab? {
        tabsByConversation.values.lazy.flatMap(\.values).first { $0.webView === webView }
    }

    private func finishNavigation(_ result: Result<PhoneBrowserPage, Error>, for tab: BrowserTab) {
        guard let continuation = tab.navigationContinuation else { return }
        tab.navigationContinuation = nil
        tab.timeoutTask?.cancel()
        tab.timeoutTask = nil
        if case .failure(let error) = result, !(error is CancellationError) {
            tab.lastNavigationError = error
        }
        continuation.resume(with: result)
    }

    private func savedTabs(for conversationID: String) -> [SavedBrowserTab] {
        guard let data = userDefaults.data(forKey: Self.persistenceKey(for: conversationID)),
              let state = try? JSONDecoder().decode(PersistedBrowserTabs.self, from: data) else { return [] }
        return state.tabs
    }

    private func savedSelectionID(for conversationID: String) -> Int? {
        guard let data = userDefaults.data(forKey: Self.persistenceKey(for: conversationID)),
              let state = try? JSONDecoder().decode(PersistedBrowserTabs.self, from: data) else { return nil }
        return state.selectedTabID
    }

    private func persistTabs(for conversationID: String, excluding excluded: Set<Int> = []) {
        let summaries = tabSummariesWithoutPersistence(conversationID: conversationID).filter { !excluded.contains($0.id) }
        let state = PersistedBrowserTabs(
            selectedTabID: selectedTabIDs[conversationID],
            tabs: Array(summaries.prefix(Self.maximumTabsPerConversation))
        )
        guard let data = try? JSONEncoder().encode(state) else { return }
        userDefaults.set(data, forKey: Self.persistenceKey(for: conversationID))
    }

    private func tabSummariesWithoutPersistence(conversationID: String) -> [SavedBrowserTab] {
        var byID = Dictionary(uniqueKeysWithValues: savedTabs(for: conversationID).map { ($0.id, $0) })
        for tab in tabsByConversation[conversationID, default: [:]].values {
            byID[tab.id] = SavedBrowserTab(id: tab.id, title: tab.title, url: tab.currentURL ?? tab.restoredURL)
        }
        return byID.values.sorted { $0.id < $1.id }
    }

    private func pruneExpiredTabs() {
        let cutoff = Date().addingTimeInterval(-Self.idleTabLifetime)
        for (conversationID, tabs) in tabsByConversation {
            for tab in tabs.values where tab.lastUsedAt < cutoff && !tab.isBusy {
                tab.webView.stopLoading()
                tab.webView.navigationDelegate = nil
                tab.webView.uiDelegate = nil
                tabsByConversation[conversationID]?.removeValue(forKey: tab.id)
            }
            if tabsByConversation[conversationID]?.isEmpty == true { tabsByConversation.removeValue(forKey: conversationID) }
            persistTabs(for: conversationID)
        }
    }

    private static func persistenceKey(for conversationID: String) -> String {
        persistenceKeyPrefix + conversationID
    }

    private func jsString(_ value: String) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: [value], options: [.fragmentsAllowed])
        guard let arrayText = String(data: data, encoding: .utf8), arrayText.count >= 2 else {
            throw PhoneBrowserError.invalidAction
        }
        return String(arrayText.dropFirst().dropLast())
    }

    private static func isUsableSearchPage(_ page: PhoneBrowserPage) -> Bool {
        guard page.text.count > 80 else { return false }
        let content = "\(page.title) \(page.text)".lowercased()
        let blockedPageMarkers = [
            "captcha", "verify you are human", "unusual traffic", "automated queries",
            "our systems have detected", "before you continue to google",
            "请输入验证码", "人机验证", "安全验证", "访问异常", "异常流量"
        ]
        return !blockedPageMarkers.contains(where: content.contains)
    }

    // MARK: - WKNavigationDelegate

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        let frame = navigationAction.targetFrame
        let disposition = PhoneBrowserURLPolicy.navigationDisposition(
            url: navigationAction.request.url,
            hasTargetFrame: frame != nil,
            isMainFrame: frame?.isMainFrame == true
        )
        switch disposition {
        case .allow:
            decisionHandler(.allow)
        case .cancel:
            decisionHandler(.cancel)
        case .reject:
            decisionHandler(.cancel)
            if let tab = findTab(for: webView) {
                let error = PhoneBrowserError.invalidURL
                if tab.navigationContinuation != nil { finishNavigation(.failure(error), for: tab) }
                else { tab.lastNavigationError = error }
            }
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let tab = findTab(for: webView), tab.navigationContinuation != nil else { return }
        Task { @MainActor [weak self, weak tab] in
            guard let self, let tab else { return }
            do {
                let page = try await self.readPage(in: tab, waitForStableDOM: true)
                self.finishNavigation(.success(page), for: tab)
            } catch {
                self.finishNavigation(.failure(error), for: tab)
            }
        }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        handleNavigationError(error, webView: webView)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handleNavigationError(error, webView: webView)
    }

    private func handleNavigationError(_ error: Error, webView: WKWebView) {
        guard !Self.isCancelledNavigation(error), let tab = findTab(for: webView) else { return }
        if tab.navigationContinuation != nil { finishNavigation(.failure(error), for: tab) }
        else { tab.lastNavigationError = error }
    }

    // MARK: - WKUIDelegate

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        // Match OpenMinis' same-session tab model without allowing websites to
        // create uncontrolled pop-up views. The model must request new_tab.
        nil
    }

    private static func isCancelledNavigation(_ error: Error) -> Bool {
        let error = error as NSError
        return error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled
    }
}

@MainActor
private final class BrowserTab {
    let id: Int
    let conversationID: String
    let webView: WKWebView
    var restoredURL: String?
    var currentURL: String?
    var title: String
    var searchEngine: String?
    var attemptedSearchEngines: [String]?
    var isBusy = false
    var lastUsedAt = Date()
    var lastNavigationError: Error?
    var navigationContinuation: CheckedContinuation<PhoneBrowserPage, Error>?
    var timeoutTask: Task<Void, Never>?

    init(id: Int, conversationID: String, webView: WKWebView, restoredURL: String?, title: String) {
        self.id = id
        self.conversationID = conversationID
        self.webView = webView
        self.restoredURL = restoredURL
        self.currentURL = restoredURL
        self.title = title
    }
}

private struct PersistedBrowserTabs: Codable {
    let selectedTabID: Int?
    let tabs: [SavedBrowserTab]
}

private struct SavedBrowserTab: Codable {
    let id: Int
    let title: String
    let url: String?
}
