import Foundation
import XCTest
@testable import OpenMuseCore

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class ReferenceConnectorTests: XCTestCase {
    func testObsidianImporterKeepsFilenameNotFullPathAndUsesDistinctStableIDs() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("OpenMuseObsidian-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let firstFolder = directory.appendingPathComponent("first", isDirectory: true)
        let secondFolder = directory.appendingPathComponent("second", isDirectory: true)
        try FileManager.default.createDirectory(at: firstFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondFolder, withIntermediateDirectories: true)
        let firstURL = firstFolder.appendingPathComponent("旅行偏好.md")
        let secondURL = secondFolder.appendingPathComponent("旅行偏好.md")
        try "# 旅行偏好\n每天留一点自由时间。".write(to: firstURL, atomically: true, encoding: .utf8)
        try "# 另一份旅行偏好\n优先坐火车。".write(to: secondURL, atomically: true, encoding: .utf8)

        let first = try ObsidianMarkdownImporter.read(url: firstURL)
        let second = try ObsidianMarkdownImporter.read(url: secondURL)

        XCTAssertEqual(first.provider, "obsidian")
        XCTAssertEqual(first.title, "旅行偏好")
        XCTAssertEqual(first.locator, "旅行偏好.md")
        XCTAssertFalse(first.externalID.contains(directory.path))
        XCTAssertNotEqual(first.externalID, second.externalID)
        XCTAssertThrowsError(try ObsidianMarkdownImporter.read(url: directory.appendingPathComponent("notes.txt"))) {
            XCTAssertEqual($0 as? ReferenceConnectorError, .unsupportedFile)
        }
    }

    func testReferenceDocumentImportDeduplicatesUpdatesForgetsAndLeavesTombstones() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("OpenMuseReferenceStore-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = try SQLiteStore(path: directory.appendingPathComponent("store.sqlite"))
        let store = ReferenceDocumentStore(database: database)
        let draft = ReferenceDocumentDraft(provider: "obsidian", externalID: "file:abc", title: "旅行偏好", locator: "旅行偏好.md", content: "每天留一点自由时间。")

        let (first, firstOutcome) = try store.importDocument(draft)
        let (same, sameOutcome) = try store.importDocument(draft)
        let changedDraft = ReferenceDocumentDraft(provider: "obsidian", externalID: "file:abc", title: "旅行偏好", locator: "旅行偏好.md", content: "每天留一点自由时间，避免排满。")
        let (updated, updateOutcome) = try store.importDocument(changedDraft)

        XCTAssertEqual(firstOutcome, .imported)
        XCTAssertEqual(sameOutcome, .unchanged)
        XCTAssertEqual(same, first)
        XCTAssertEqual(updateOutcome, .updated)
        XCTAssertEqual(updated.id, first.id)
        XCTAssertNotEqual(updated.contentDigest, first.contentDigest)
        XCTAssertEqual(try database.load(SourceRecord.self, kind: RecordKind.source).count, 1)
        XCTAssertEqual(try database.load(ImportRecord.self, kind: RecordKind.importRecord).count, 1)

        try store.forget(id: updated.id)

        XCTAssertTrue(try store.all().isEmpty)
        XCTAssertTrue(try database.load(SourceRecord.self, kind: RecordKind.source).isEmpty)
        XCTAssertTrue(try database.load(ImportRecord.self, kind: RecordKind.importRecord).isEmpty)
        XCTAssertTrue(try database.load(DeletionTombstoneRecord.self, kind: RecordKind.deletionTombstone).contains(where: {
            $0.recordKind == RecordKind.referenceDocument && $0.recordID == updated.id
        }))
    }

    func testRelevantReferenceContextIsSourceLinkedAndNotIncludedForUnrelatedQuery() throws {
        let document = ReferenceDocumentRecord(
            id: ReferenceDocumentRecord.stableID(provider: "obsidian", externalID: "file:travel"),
            provider: "obsidian", externalID: "file:travel", sourceRecordID: "source-travel",
            importRecordID: "import-travel", title: "恩施旅行偏好", locator: "旅行偏好.md",
            content: "用户偏好每天安排一段自由时间。",
            contentDigest: SourceRecord.digest("用户偏好每天安排一段自由时间。")
        )
        let relevant = PromptContextBuilder.build(documents: [], contextWindow: 16_000, query: "帮我调整恩施旅行计划", referenceDocuments: [document])
        let unrelated = PromptContextBuilder.build(documents: [], contextWindow: 16_000, query: "如何修理咖啡机", referenceDocuments: [document])

        XCTAssertTrue(relevant.text.contains("外部资料"))
        XCTAssertTrue(relevant.text.contains("source-travel"))
        XCTAssertTrue(relevant.text.contains("不可信 JSON"))
        XCTAssertFalse(unrelated.text.contains("source-travel"))
    }

    func testNotionSearchUsesReadOnlyPageFilterAndSecureVersionedRequest() async throws {
        let protocolStub = ReferenceConnectorURLProtocol.self
        protocolStub.reset { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Notion-Version"), NotionConnector.apiVersion)
            let body = try Self.requestBody(request)
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual(json["query"] as? String, "旅行")
            XCTAssertEqual((json["filter"] as? [String: String])?["value"], "page")
            return (200, Data("""
            {"has_more":false,"results":[{"object":"page","id":"0123456789abcdef0123456789abcdef","url":"https://www.notion.so/trip-0123456789abcdef0123456789abcdef","last_edited_time":"2026-10-10T01:02:03.000Z","properties":{"Name":{"title":[{"plain_text":"旅行计划"}]}}}]}
            """.utf8))
        }
        let results = try await NotionConnector(token: "test-token", session: stubSession()).searchPages(query: "旅行")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.title, "旅行计划")
    }

    func testNotionReadsPaginatedNestedBlocksAndRejectsUnauthorizedAccess() async throws {
        ReferenceConnectorURLProtocol.reset { request in
            let path = request.url?.path ?? ""
            if path.hasSuffix("/blocks/0123456789abcdef0123456789abcdef/children") {
                return (200, Data("""
                {"has_more":false,"results":[{"id":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","type":"heading_1","has_children":false,"heading_1":{"rich_text":[{"plain_text":"计划"}]}},{"id":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","type":"paragraph","has_children":true,"paragraph":{"rich_text":[{"plain_text":"偏好"}]}}]}
                """.utf8))
            }
            if path.hasSuffix("/blocks/bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb/children") {
                return (200, Data("""
                {"has_more":false,"results":[{"id":"cccccccccccccccccccccccccccccccc","type":"bulleted_list_item","has_children":false,"bulleted_list_item":{"rich_text":[{"plain_text":"每天留出自由时间"}]}}]}
                """.utf8))
            }
            return (403, Data("{}".utf8))
        }
        let page = NotionPageSummary(id: "0123456789abcdef0123456789abcdef", title: "旅行", url: "https://www.notion.so/trip-0123456789abcdef0123456789abcdef")
        let draft = try await NotionConnector(token: "test-token", session: stubSession()).readPage(page)
        XCTAssertTrue(draft.content.contains("# 计划"))
        XCTAssertTrue(draft.content.contains("- 每天留出自由时间"))

        ReferenceConnectorURLProtocol.reset { _ in (403, Data("{}".utf8)) }
        do {
            _ = try await NotionConnector(token: "test-token", session: stubSession()).readPage(page)
            XCTFail("403 must be reported as missing page access")
        } catch {
            XCTAssertEqual(error as? ReferenceConnectorError, .accessDenied)
        }
    }

    private func stubSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ReferenceConnectorURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private static func requestBody(_ request: URLRequest) throws -> Data {
        if let body = request.httpBody { return body }
        let stream = try XCTUnwrap(request.httpBodyStream)
        stream.open()
        defer { stream.close() }
        var result = Data()
        var buffer = [UInt8](repeating: 0, count: 8_192)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count < 0 { throw stream.streamError ?? ReferenceConnectorError.invalidResponse }
            if count == 0 { break }
            result.append(contentsOf: buffer.prefix(count))
        }
        return result
    }
}

private final class ReferenceConnectorURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var currentHandler: ((URLRequest) throws -> (Int, Data))?

    static func reset(handler: @escaping (URLRequest) throws -> (Int, Data)) {
        lock.lock()
        currentHandler = handler
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        let handler = Self.currentHandler
        Self.lock.unlock()
        do {
            let requestHandler = try XCTUnwrap(handler)
            let (status, data) = try requestHandler(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
