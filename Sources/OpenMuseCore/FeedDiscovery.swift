import Foundation

enum FeedDiscovery {
    static let sourceID = "google-public-discovery"
    static let browserConversationID = "openmuse-dynamic-discovery"
    static let supportedSites = "site:x.com OR site:reddit.com OR site:xiaohongshu.com OR site:mp.weixin.qq.com"

    static func searchQuery(topics: [String]) -> String? {
        let cleaned = topics.compactMap(cleanTopic)
        var unique: [String] = []
        var seen = Set<String>()
        for topic in cleaned where seen.insert(topic.lowercased()).inserted {
            unique.append(topic)
            if unique.count == 3 { break }
        }
        guard !unique.isEmpty else { return nil }
        let topicText = String(unique.joined(separator: " ").prefix(160 - supportedSites.count - 1))
        return "\(supportedSites) \(topicText)"
    }

    static func items(from links: [PhoneBrowserLink], fetchedAt: Date = .now) -> [FeedItemRecord] {
        var seen = Set<String>()
        return links.compactMap { link in
            guard let url = URL(string: link.url),
                  url.scheme?.lowercased() == "https",
                  let host = url.host?.lowercased(), !host.isEmpty,
                  !isSearchEngineHost(host),
                  !link.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            let canonicalURL = canonicalPublicURL(url)
            let id = FeedReader.itemID(sourceID: sourceID, url: canonicalURL)
            guard seen.insert(id).inserted else { return nil }
            return FeedItemRecord(
                id: id,
                sourceID: sourceID,
                sourceTitle: displaySource(host),
                title: String(link.title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(300)),
                summary: String((link.summary ?? "").trimmingCharacters(in: .whitespacesAndNewlines).prefix(1_000)),
                url: canonicalURL,
                fetchedAt: fetchedAt
            )
        }
    }

    static func cleanTopic(_ raw: String) -> String? {
        guard !raw.contains("@"),
              raw.range(of: "\\d{7,}", options: .regularExpression) == nil,
              !MemoryPrivacyPolicy.isSensitive(raw) else { return nil }
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let genericPhrases = [
            "根据我最近在准备的", "最近在准备的", "根据最近的对话", "根据聊天内容",
            "分享我可能感兴趣的", "我可能感兴趣的", "我最近在关注的", "推荐一些",
            "推荐", "分享", "我喜欢", "我对", "兴趣说明", "兴趣", "内容", "看看"
        ]
        for phrase in genericPhrases { value = value.replacingOccurrences(of: phrase, with: "") }
        value = value.map { character in
            character.isLetter || character.isNumber || character.isWhitespace ? character : " "
        }.reduce(into: "") { $0.append($1) }
        value = value.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard value.count >= 2 else { return nil }
        return String(value.prefix(36))
    }

    private static func isSearchEngineHost(_ host: String) -> Bool {
        ["google.", "bing.com", "baidu.com", "duckduckgo.com", "search.yahoo.com"].contains(where: host.contains)
    }

    private static func canonicalPublicURL(_ url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url.absoluteString }
        components.fragment = nil
        if let queryItems = components.queryItems {
            let retainedItems = queryItems.filter { item in
                let key = item.name.lowercased()
                return !key.hasPrefix("utm_") && !["gclid", "fbclid", "ref", "source"].contains(key)
            }
            components.queryItems = retainedItems.isEmpty ? nil : retainedItems
        }
        return components.url?.absoluteString ?? url.absoluteString
    }

    private static func displaySource(_ host: String) -> String {
        if host == "x.com" || host.hasSuffix(".x.com") || host == "twitter.com" || host.hasSuffix(".twitter.com") { return "X" }
        if host == "reddit.com" || host.hasSuffix(".reddit.com") { return "Reddit" }
        if host == "xiaohongshu.com" || host.hasSuffix(".xiaohongshu.com") { return "小红书" }
        if host == "mp.weixin.qq.com" || host.hasSuffix(".weixin.qq.com") { return "微信公众号" }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}
