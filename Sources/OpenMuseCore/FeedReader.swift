import CryptoKit
import Foundation

struct ParsedFeed: Sendable {
    let title: String
    let items: [FeedItemRecord]
}

enum FeedReaderError: Error, LocalizedError {
    case invalidAddress
    case unavailable(String)
    case invalidDocument

    var errorDescription: String? {
        switch self {
        case .invalidAddress: "订阅地址必须是有效的 HTTPS 网页地址。"
        case .unavailable(let message): message
        case .invalidDocument: "来源没有返回可读取的 RSS 或 Atom 内容。"
        }
    }
}

enum FeedReader {
    static let maximumDocumentBytes = 1_000_000
    static let maximumItems = 100

    static func validatedURL(_ rawValue: String) throws -> URL {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.count <= 2_048,
              let components = URLComponents(string: value),
              components.scheme?.lowercased() == "https",
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              host != "localhost", !host.hasSuffix(".local"), let url = components.url else { throw FeedReaderError.invalidAddress }
        return url
    }

    static func fetch(source: FeedSourceRecord, session: URLSession = .shared, now: Date = .now) async throws -> ParsedFeed {
        let url = try validatedURL(source.url)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 25
        request.setValue("application/atom+xml, application/rss+xml, application/xml, text/xml;q=0.9, */*;q=0.5", forHTTPHeaderField: "Accept")
        let (data, response): (Data, URLResponse)
        do { (data, response) = try await session.data(for: request) }
        catch { throw FeedReaderError.unavailable("读取来源失败：\(error.localizedDescription)") }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode
            throw FeedReaderError.unavailable(status.map { "来源返回 HTTP \($0)。" } ?? "来源没有返回有效的网页响应。")
        }
        guard data.count <= maximumDocumentBytes else { throw FeedReaderError.unavailable("来源超过 1 MB 限制，没有导入。") }
        return try parse(data: data, sourceURL: url, sourceID: source.id, fallbackTitle: source.title, fetchedAt: now)
    }

    static func parse(data: Data, sourceURL: URL, sourceID: String, fallbackTitle: String, fetchedAt: Date = .now) throws -> ParsedFeed {
        guard !data.isEmpty, data.count <= maximumDocumentBytes else { throw FeedReaderError.invalidDocument }
        let delegate = RSSAtomParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldResolveExternalEntities = false
        guard parser.parse(), delegate.sawFeedRoot, !delegate.items.isEmpty else { throw FeedReaderError.invalidDocument }
        let feedTitle = clean(delegate.feedTitle).isEmpty ? fallbackTitle : clean(delegate.feedTitle)
        let items = delegate.items.prefix(maximumItems).compactMap { item -> FeedItemRecord? in
            let title = String(clean(item.title).prefix(300))
            guard !title.isEmpty,
                  let itemURL = URL(string: item.link.trimmingCharacters(in: .whitespacesAndNewlines), relativeTo: sourceURL)?.absoluteURL,
                  ["https", "http"].contains(itemURL.scheme?.lowercased() ?? ""),
                  itemURL.host != nil else { return nil }
            let summary = String(clean(item.summary).prefix(2_000))
            return FeedItemRecord(
                id: itemID(sourceID: sourceID, url: itemURL.absoluteString),
                sourceID: sourceID,
                sourceTitle: feedTitle,
                title: title,
                summary: summary,
                url: itemURL.absoluteString,
                imageURL: safeImageURL(item.image, relativeTo: sourceURL)?.absoluteString,
                publishedAt: parseDate(item.date),
                fetchedAt: fetchedAt
            )
        }
        guard !items.isEmpty else { throw FeedReaderError.invalidDocument }
        var seen = Set<String>()
        return ParsedFeed(title: feedTitle, items: items.filter { seen.insert($0.id).inserted })
    }

    static func itemID(sourceID: String, url: String) -> String {
        let digest = SHA256.hash(data: Data("\(sourceID)|\(url)".utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func safeImageURL(_ rawValue: String, relativeTo baseURL: URL) -> URL? {
        guard let candidate = URL(string: rawValue.trimmingCharacters(in: .whitespacesAndNewlines), relativeTo: baseURL)?.absoluteURL,
              let validated = try? validatedURL(candidate.absoluteString) else { return nil }
        return validated
    }

    private static func parseDate(_ value: String) -> Date? {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        if let date = iso.date(from: value) { return date }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        for format in ["EEE, dd MMM yyyy HH:mm:ss zzz", "EEE, dd MMM yyyy HH:mm zzz", "EEE, dd MMM yyyy HH:mm:ss Z"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: value) { return date }
        }
        return nil
    }

    private static func clean(_ value: String) -> String {
        let stripped = value.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        return stripped
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}

private final class RSSAtomParser: NSObject, XMLParserDelegate {
    struct Item {
        var title = ""
        var link = ""
        var summary = ""
        var date = ""
        var image = ""
    }

    private(set) var sawFeedRoot = false
    private(set) var feedTitle = ""
    private(set) var items: [Item] = []
    private var current: Item?
    private var captureKey: String?
    private var text = ""

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        let name = (qName ?? elementName).lowercased()
        if ["rss", "feed", "rdf:rdf"].contains(name) { sawFeedRoot = true }
        if name == "item" || name == "entry" {
            current = Item()
            return
        }
        if name == "link", current != nil {
            let relation = attributeDict["rel"]?.lowercased()
            if let href = attributeDict["href"] {
                if relation == "enclosure" || attributeDict["type"]?.lowercased().hasPrefix("image/") == true {
                    current?.image = href
                } else if relation == nil || relation == "alternate" {
                    current?.link = href
                }
            }
        }
        let isImageElement = name == "media:thumbnail" || name == "media:content"
        let isImageEnclosure = name == "enclosure" && attributeDict["type"]?.lowercased().hasPrefix("image/") == true
        if (isImageElement || isImageEnclosure), let image = attributeDict["url"] {
            current?.image = image
        }
        if let key = normalizedKey(name) {
            captureKey = key
            text = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }
    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if let value = String(data: CDATABlock, encoding: .utf8) { text += value }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let name = (qName ?? elementName).lowercased()
        if let captureKey, let key = normalizedKey(name), captureKey == key {
            if current != nil {
                switch key {
                case "title": current?.title += text
                case "link": if current?.link.isEmpty == true { current?.link = text }
                case "summary": current?.summary += text
                case "date": current?.date = text
                default: break
                }
            } else if key == "title", feedTitle.isEmpty {
                feedTitle = text
            }
            self.captureKey = nil
            text = ""
        }
        if name == "item" || name == "entry", let current {
            items.append(current)
            self.current = nil
        }
    }

    private func normalizedKey(_ name: String) -> String? {
        switch name {
        case "title": "title"
        case "link": "link"
        case "description", "summary", "content", "content:encoded": "summary"
        case "pubdate", "published", "updated", "dc:date": "date"
        default: nil
        }
    }
}
