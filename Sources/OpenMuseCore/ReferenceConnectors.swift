import Foundation

public struct ReferenceDocumentDraft: Equatable, Sendable {
    public var provider: String
    public var externalID: String
    public var title: String
    public var locator: String?
    public var content: String
    public var sourceUpdatedAt: Date?

    public init(provider: String, externalID: String, title: String, locator: String?, content: String, sourceUpdatedAt: Date? = nil) {
        self.provider = provider
        self.externalID = externalID
        self.title = title
        self.locator = locator
        self.content = content
        self.sourceUpdatedAt = sourceUpdatedAt
    }
}

public struct NotionPageSummary: Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var url: String
    public var lastEditedAt: Date?

    public init(id: String, title: String, url: String, lastEditedAt: Date? = nil) {
        self.id = id
        self.title = title
        self.url = url
        self.lastEditedAt = lastEditedAt
    }
}

public enum ReferenceConnectorError: Error, LocalizedError, Equatable {
    case invalidCredential
    case invalidResponse
    case accessDenied
    case rateLimited
    case unsupportedFile
    case fileTooLarge
    case pageTooLarge
    case provider(String)

    public var errorDescription: String? {
        switch self {
        case .invalidCredential: "Notion 授权无效；请检查只读连接凭证。"
        case .invalidResponse: "资料服务返回了无法识别的结果。"
        case .accessDenied: "连接没有读取该页面的权限；请在 Notion 中把目标页面分享给只读连接。"
        case .rateLimited: "资料服务暂时限制了请求；稍后可以重试。"
        case .unsupportedFile: "请选择 Markdown 文件（.md 或 .markdown）。"
        case .fileTooLarge: "Markdown 文件超过单份资料的大小限制。"
        case .pageTooLarge: "Notion 页面超过本地导入上限；页面没有被截断或保存。"
        case .provider(let message): message
        }
    }
}

public enum ObsidianMarkdownImporter {
    public static func read(url: URL) throws -> ReferenceDocumentDraft {
        let ext = url.pathExtension.lowercased()
        guard ext == "md" || ext == "markdown" else { throw ReferenceConnectorError.unsupportedFile }
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true else { throw ReferenceConnectorError.unsupportedFile }
        guard let size = values.fileSize, size <= ReferenceDocumentRecord.maximumContentBytes else {
            throw ReferenceConnectorError.fileTooLarge
        }
        let content = try String(contentsOf: url, encoding: .utf8)
        guard content.utf8.count <= ReferenceDocumentRecord.maximumContentBytes else { throw ReferenceConnectorError.fileTooLarge }
        let filename = url.deletingPathExtension().lastPathComponent
        let title = content.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first(where: { $0.hasPrefix("# ") })
            .map { String($0.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap { $0.isEmpty ? nil : $0 } ?? filename
        return ReferenceDocumentDraft(
            provider: "obsidian",
            externalID: "file:\(SourceRecord.digest(url.standardizedFileURL.path))",
            title: String(title.prefix(300)),
            locator: url.lastPathComponent,
            content: content
        )
    }
}

public enum ReferenceImportOutcome: Equatable, Sendable {
    case imported
    case updated
    case unchanged
}

public struct ReferenceDocumentStore {
    private let database: SQLiteStore

    public init(database: SQLiteStore) { self.database = database }

    public func all() throws -> [ReferenceDocumentRecord] {
        try database.load(ReferenceDocumentRecord.self, kind: RecordKind.referenceDocument)
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    @discardableResult
    public func importDocument(_ draft: ReferenceDocumentDraft) throws -> (ReferenceDocumentRecord, ReferenceImportOutcome) {
        guard ["notion", "obsidian", "qq-mail"].contains(draft.provider),
              !draft.externalID.isEmpty, draft.externalID.count <= 500,
              !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              draft.content.utf8.count <= ReferenceDocumentRecord.maximumContentBytes else {
            throw ReferenceConnectorError.pageTooLarge
        }
        let id = ReferenceDocumentRecord.stableID(provider: draft.provider, externalID: draft.externalID)
        let sourceID = SourceRecord.stableID(type: "reference-document-\(draft.provider)", externalID: draft.externalID)
        let importID = SourceRecord.stableID(type: "reference-import-\(draft.provider)", externalID: draft.externalID)
        let existing = try database.load(ReferenceDocumentRecord.self, kind: RecordKind.referenceDocument).first(where: { $0.id == id })
        let digest = SourceRecord.digest(draft.content)
        if let existing, existing.contentDigest == digest, existing.title == draft.title, existing.locator == draft.locator {
            return (existing, .unchanged)
        }
        let now = Date.now
        let document = ReferenceDocumentRecord(
            id: id,
            provider: draft.provider,
            externalID: draft.externalID,
            sourceRecordID: sourceID,
            importRecordID: importID,
            title: String(draft.title.prefix(300)),
            locator: draft.locator.map { String($0.prefix(2_000)) },
            content: draft.content,
            contentDigest: digest,
            sourceUpdatedAt: draft.sourceUpdatedAt,
            importedAt: existing?.importedAt ?? now,
            updatedAt: now
        )
        guard document.isValid else { throw ReferenceConnectorError.invalidResponse }
        let source = SourceRecord(
            id: sourceID,
            sourceType: "reference-document",
            provider: draft.provider,
            displayName: String(document.title.prefix(200)),
            externalID: draft.externalID,
            locator: document.locator,
            contentDigest: digest,
            trust: "untrusted-import",
            createdAt: existing?.importedAt ?? now,
            updatedAt: now
        )
        let importRecord = ImportRecord(
            id: importID,
            sourceRecordID: sourceID,
            importType: "reference-document",
            externalItemID: draft.externalID,
            targetKind: RecordKind.referenceDocument,
            targetRecordID: id,
            contentDigest: digest,
            itemCount: 1,
            status: "imported",
            createdAt: existing?.importedAt ?? now,
            updatedAt: now
        )
        let nextDocumentRevision = try database.revisions(ReferenceDocumentRecord.self, kind: RecordKind.referenceDocument, objectID: id).count + 1
        let nextSourceRevision = try database.revisions(SourceRecord.self, kind: RecordKind.source, objectID: sourceID).count + 1
        let nextImportRevision = try database.revisions(ImportRecord.self, kind: RecordKind.importRecord, objectID: importID).count + 1
        let writes = [
            try database.prepareWrite(source, kind: RecordKind.source, id: sourceID, revision: nextSourceRevision, appendRevision: true),
            try database.prepareWrite(importRecord, kind: RecordKind.importRecord, id: importID, revision: nextImportRevision, appendRevision: true),
            try database.prepareWrite(document, kind: RecordKind.referenceDocument, id: id, revision: nextDocumentRevision, appendRevision: true)
        ]
        try database.saveAtomically(writes)
        return (document, existing == nil ? .imported : .updated)
    }

    public func forget(id: String) throws {
        guard let document = try all().first(where: { $0.id == id }) else { return }
        try database.forgetRecords([
            (RecordKind.referenceDocument, document.id),
            (RecordKind.source, document.sourceRecordID),
            (RecordKind.importRecord, document.importRecordID)
        ])
    }
}

/// Read-only Notion API client. The integration token must have read-content capability and page access.
public struct NotionConnector: Sendable {
    public static let apiVersion = "2026-03-11"
    private static let apiRoot = URL(string: "https://api.notion.com/v1")!
    private let token: String
    private let session: URLSession

    public init(token: String, session: URLSession = .shared) {
        self.token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        self.session = session
    }

    public func searchPages(query: String, limit: Int = 40) async throws -> [NotionPageSummary] {
        guard !token.isEmpty, query.utf8.count <= 500 else { throw ReferenceConnectorError.invalidCredential }
        let maximum = min(max(limit, 1), 100)
        var cursor: String?
        var results: [NotionPageSummary] = []
        for _ in 0..<5 where results.count < maximum {
            var payload: [String: Any] = [
                "query": query,
                "page_size": min(100, maximum - results.count),
                "filter": ["property": "object", "value": "page"],
                "sort": ["direction": "descending", "timestamp": "last_edited_time"]
            ]
            if let cursor { payload["start_cursor"] = cursor }
            let data = try await send(path: "search", method: "POST", body: try JSONSerialization.data(withJSONObject: payload))
            guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let items = root["results"] as? [[String: Any]] else { throw ReferenceConnectorError.invalidResponse }
            for item in items where item["object"] as? String == "page" && item["in_trash"] as? Bool != true {
                guard let id = item["id"] as? String, Self.isSafeNotionID(id),
                      let url = item["url"] as? String, Self.isSafePageURL(url) else { continue }
                let title = Self.pageTitle(item)
                guard !title.isEmpty else { continue }
                results.append(NotionPageSummary(
                    id: id,
                    title: String(title.prefix(300)),
                    url: url,
                    lastEditedAt: Self.parseDate(item["last_edited_time"] as? String)
                ))
                if results.count >= maximum { break }
            }
            guard root["has_more"] as? Bool == true, let next = root["next_cursor"] as? String, !next.isEmpty else { break }
            cursor = next
        }
        return results
    }

    public func readPage(_ page: NotionPageSummary) async throws -> ReferenceDocumentDraft {
        guard !token.isEmpty, Self.isSafeNotionID(page.id), Self.isSafePageURL(page.url) else { throw ReferenceConnectorError.invalidCredential }
        let budget = ContentBudget()
        let content = try await readChildren(blockID: page.id, depth: 0, budget: budget)
        return ReferenceDocumentDraft(
            provider: "notion",
            externalID: page.id,
            title: page.title,
            locator: page.url,
            content: content,
            sourceUpdatedAt: page.lastEditedAt
        )
    }

    private func readChildren(blockID: String, depth: Int, budget: ContentBudget) async throws -> String {
        guard depth <= 4, budget.blockCount < 500, Self.isSafeNotionID(blockID) else { throw ReferenceConnectorError.pageTooLarge }
        var cursor: String?
        var output: [String] = []
        for pageIndex in 0..<10 {
            var components = URLComponents(url: Self.apiRoot.appendingPathComponent("blocks/\(blockID)/children"), resolvingAgainstBaseURL: false)
            components?.queryItems = [URLQueryItem(name: "page_size", value: "100")]
            if let cursor { components?.queryItems?.append(URLQueryItem(name: "start_cursor", value: cursor)) }
            guard let url = components?.url else { throw ReferenceConnectorError.invalidResponse }
            let data = try await send(url: url, method: "GET", body: nil)
            guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let blocks = root["results"] as? [[String: Any]] else { throw ReferenceConnectorError.invalidResponse }
            for block in blocks {
                budget.blockCount += 1
                guard budget.blockCount <= 500 else { throw ReferenceConnectorError.pageTooLarge }
                let type = block["type"] as? String ?? ""
                let value = block[type] as? [String: Any] ?? [:]
                var text = Self.blockText(type: type, value: value)
                if block["has_children"] as? Bool == true, let childID = block["id"] as? String {
                    let nested = try await readChildren(blockID: childID, depth: depth + 1, budget: budget)
                    if !nested.isEmpty { text = [text, nested].filter { !$0.isEmpty }.joined(separator: "\n") }
                }
                if !text.isEmpty {
                    budget.byteCount += text.utf8.count
                    guard budget.byteCount <= ReferenceDocumentRecord.maximumContentBytes else { throw ReferenceConnectorError.pageTooLarge }
                    output.append(text)
                }
            }
            guard root["has_more"] as? Bool == true, let next = root["next_cursor"] as? String, !next.isEmpty else { break }
            if pageIndex == 9 { throw ReferenceConnectorError.pageTooLarge }
            cursor = next
        }
        return output.joined(separator: "\n")
    }

    private func send(path: String, method: String, body: Data?) async throws -> Data {
        try await send(url: Self.apiRoot.appendingPathComponent(path), method: method, body: body)
    }

    private func send(url: URL, method: String, body: Data?) async throws -> Data {
        guard url.scheme == "https", url.host == "api.notion.com" else { throw ReferenceConnectorError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 30
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(Self.apiVersion, forHTTPHeaderField: "Notion-Version")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ReferenceConnectorError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            switch http.statusCode {
            case 401: throw ReferenceConnectorError.invalidCredential
            case 403, 404: throw ReferenceConnectorError.accessDenied
            case 429: throw ReferenceConnectorError.rateLimited
            default:
                let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["message"] as? String
                throw ReferenceConnectorError.provider(String((message ?? "Notion 请求失败（HTTP \(http.statusCode)）。").prefix(300)))
            }
        }
        return data
    }

    private static func pageTitle(_ page: [String: Any]) -> String {
        if let properties = page["properties"] as? [String: Any] {
            for raw in properties.values {
                guard let property = raw as? [String: Any] else { continue }
                if let title = property["title"] as? [[String: Any]] {
                    let text = richText(title)
                    if !text.isEmpty { return text }
                }
            }
        }
        if let title = page["title"] as? [[String: Any]] { return richText(title) }
        return ""
    }

    private static func blockText(type: String, value: [String: Any]) -> String {
        if type == "divider" { return "---" }
        if type == "table_row", let cells = value["cells"] as? [[[String: Any]]] {
            return "| " + cells.map(richText).joined(separator: " | ") + " |"
        }
        if ["child_page", "child_database"].contains(type), let title = value["title"] as? String {
            return "### \(title)"
        }
        let text = richText(value["rich_text"] as? [[String: Any]] ?? value["title"] as? [[String: Any]] ?? [])
        guard !text.isEmpty else { return "" }
        switch type {
        case "heading_1": return "# \(text)"
        case "heading_2": return "## \(text)"
        case "heading_3": return "### \(text)"
        case "bulleted_list_item": return "- \(text)"
        case "numbered_list_item": return "1. \(text)"
        case "to_do": return "- [\((value["checked"] as? Bool == true) ? "x" : " ")] \(text)"
        case "quote": return "> \(text)"
        case "callout": return "> \(text)"
        case "code": return "```\(value["language"] as? String ?? "")\n\(text)\n```"
        default: return text
        }
    }

    private static func richText(_ values: [[String: Any]]) -> String {
        values.compactMap { item -> String? in
            if let plain = item["plain_text"] as? String { return plain }
            if let text = item["text"] as? [String: Any], let content = text["content"] as? String { return content }
            if let equation = item["equation"] as? [String: Any], let expression = equation["expression"] as? String { return expression }
            return nil
        }.joined()
    }

    private static func parseDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let precise = ISO8601DateFormatter()
        precise.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return precise.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    private static func isSafeNotionID(_ value: String) -> Bool {
        !value.isEmpty && value.count <= 100 && value.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
    }

    private static func isSafePageURL(_ value: String) -> Bool {
        guard let url = URL(string: value), url.scheme == "https", url.user == nil, url.password == nil,
              let host = url.host?.lowercased() else { return false }
        return host == "notion.so" || host.hasSuffix(".notion.so") || host == "notion.site" || host.hasSuffix(".notion.site")
    }

    private final class ContentBudget {
        var blockCount = 0
        var byteCount = 0
    }
}
