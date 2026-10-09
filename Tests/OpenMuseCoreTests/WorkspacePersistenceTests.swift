import Foundation
import XCTest
import CSQLite
@testable import OpenMuseCore

final class WorkspacePersistenceTests: XCTestCase {
    func testRecordsAndDocumentRevisionsSurviveReopen() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("OpenMuseTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let databaseURL = directory.appendingPathComponent("state.sqlite")
        let workspaceURL = directory.appendingPathComponent("workspace", isDirectory: true)

        var store: SQLiteStore? = try SQLiteStore(path: databaseURL)
        var files: WorkspaceFiles? = try WorkspaceFiles(store: store!, rootURL: workspaceURL)
        let original = try XCTUnwrap(files?.document(path: "SOUL.md"))
        let revised = try XCTUnwrap(files?.save(path: "SOUL.md", content: original.content + "\n用户确认的修订。"))
        XCTAssertEqual(revised.revision, original.revision + 1)
        XCTAssertEqual(try store?.pendingOutboxCount(), 8)

        files = nil
        store = nil

        let reopened = try SQLiteStore(path: databaseURL)
        let reopenedFiles = try WorkspaceFiles(store: reopened, rootURL: workspaceURL)
        let current = try XCTUnwrap(reopenedFiles.document(path: "SOUL.md"))
        let history = try reopened.revisions(WorkspaceDocument.self, kind: RecordKind.document, objectID: "SOUL.md")
        XCTAssertEqual(current.revision, revised.revision)
        XCTAssertTrue(current.content.contains("用户确认的修订"))
        XCTAssertGreaterThanOrEqual(history.count, 2)
        XCTAssertTrue((try reopened.pendingOutboxCount()) >= 8)
    }

    func testGoalAndArtifactUseStructuredRecords() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("OpenMuseTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try SQLiteStore(path: directory.appendingPathComponent("state.sqlite"))
        let conversation = ConversationRecord(title: "恩施旅行")
        let goal = GoalRecord(conversationID: conversation.id, title: "恩施 7 天旅行", summary: "测试资料", steps: [GoalStep(title: "整理路线")])
        let artifact = ArtifactRecord(title: "旅行计划草稿", conversationID: conversation.id, goalID: goal.id, content: "第一版路线")
        try store.save(conversation, kind: RecordKind.conversation, id: conversation.id)
        try store.save(goal, kind: RecordKind.goal, id: goal.id)
        try store.save(artifact, kind: RecordKind.artifact, id: artifact.id, appendRevision: true)

        let loaded = try XCTUnwrap(store.load(GoalRecord.self, kind: RecordKind.goal).first)
        XCTAssertEqual(loaded, goal)
        XCTAssertEqual(loaded.steps.first?.title, "整理路线")

        var revisedArtifact = artifact
        revisedArtifact.currentRevision = 2
        revisedArtifact.content = "第一天：抵达恩施"
        try store.save(revisedArtifact, kind: RecordKind.artifact, id: artifact.id, revision: revisedArtifact.currentRevision, appendRevision: true)
        let artifactVersions = try store.revisions(ArtifactRecord.self, kind: RecordKind.artifact, objectID: artifact.id)
        XCTAssertEqual(artifactVersions.map(\.currentRevision), [1, 2])
        XCTAssertEqual(artifactVersions.last?.content, "第一天：抵达恩施")
    }

    func testDatabaseRejectsNewerSchemaWithoutDowngradingIt() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("OpenMuseTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = directory.appendingPathComponent("state.sqlite")
        var handle: OpaquePointer?
        XCTAssertEqual(sqlite3_open(path.path, &handle), SQLITE_OK)
        defer { if let handle { sqlite3_close(handle) } }
        XCTAssertEqual(sqlite3_exec(handle, "PRAGMA user_version=2", nil, nil, nil), SQLITE_OK)

        XCTAssertThrowsError(try SQLiteStore(path: path))
        var statement: OpaquePointer?
        XCTAssertEqual(sqlite3_prepare_v2(handle, "PRAGMA user_version", -1, &statement, nil), SQLITE_OK)
        defer { if let statement { sqlite3_finalize(statement) } }
        XCTAssertEqual(sqlite3_step(statement), SQLITE_ROW)
        XCTAssertEqual(sqlite3_column_int(statement, 0), 2)
    }

    func testModelEndpointRejectsInsecureRemoteURL() {
        XCTAssertFalse(ModelConfiguration(provider: .custom, endpoint: "http://example.com/v1", model: "model-1").isReady)
        XCTAssertTrue(ModelConfiguration(provider: .custom, endpoint: "https://example.com/v1", model: "model-1").isReady)
        XCTAssertTrue(ModelConfiguration(provider: .custom, endpoint: "http://localhost:11434/v1", model: "model-1").isReady)
        XCTAssertFalse(ModelConfiguration(provider: .custom, endpoint: "https://user:secret@example.com/v1", model: "model-1").isReady)
        XCTAssertFalse(ModelConfiguration(provider: .custom, endpoint: "https://example.com/v1?key=secret", model: "model-1").isReady)
        XCTAssertFalse(ModelConfiguration(provider: .custom, endpoint: "https://example.com/v1#fragment", model: "model-1").isReady)
        XCTAssertFalse(ModelConfiguration(provider: .custom, endpoint: "https://example.com/v1", model: "  ").isReady)
    }

    func testCredentialScopeSeparatesProvidersAndEndpoints() {
        let deepSeek = ModelConfiguration(provider: .deepSeek, endpoint: "https://api.deepseek.com/v1", model: "deepseek-chat")
        let openAI = ModelConfiguration(provider: .openAI, endpoint: "https://api.openai.com/v1", model: "gpt-4o-mini")
        let custom = ModelConfiguration(provider: .custom, endpoint: "https://proxy.example.com/v1", model: "model-1")
        XCTAssertNotEqual(deepSeek.credentialAccount, openAI.credentialAccount)
        XCTAssertNotEqual(openAI.credentialAccount, custom.credentialAccount)
    }

    func testOpenAICompatibleRuntimeSendsRequestAndReadsReply() async throws {
        ModelStubURLProtocol.responseData = Data(#"{"choices":[{"message":{"content":"可以慢慢计划这趟旅行。"}}]}"#.utf8)
        ModelStubURLProtocol.lastRequest = nil
        ModelStubURLProtocol.lastBody = nil
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [ModelStubURLProtocol.self]
        let session = URLSession(configuration: sessionConfiguration)
        defer { session.invalidateAndCancel() }

        let runtime = OpenAICompatibleRuntime(session: session)
        let configuration = ModelConfiguration(provider: .custom, endpoint: "https://example.com/v1", model: "demo-model")
        let reply = try await runtime.reply(
            systemPrompt: "Use Chinese.",
            messages: [TranscriptMessage(role: "user", content: "帮我计划旅行。")],
            configuration: configuration,
            apiKey: "unit-test-key"
        )

        XCTAssertEqual(reply, "可以慢慢计划这趟旅行。")
        let request = try XCTUnwrap(ModelStubURLProtocol.lastRequest)
        XCTAssertEqual(request.url?.absoluteString, "https://example.com/v1/chat/completions")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer unit-test-key")
        let body = try XCTUnwrap(ModelStubURLProtocol.lastBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["model"] as? String, "demo-model")
        XCTAssertEqual((json["messages"] as? [[String: String]])?.last?["content"], "帮我计划旅行。")
    }

    #if os(macOS)
    func testPiRPCRuntimeWaitsForSettledAssistantReply() async throws {
        guard let endpoint = ProcessInfo.processInfo.environment["OPENMUSE_PI_TEST_ENDPOINT"] else {
            throw XCTSkip("Set OPENMUSE_PI_TEST_ENDPOINT to run the local Pi RPC integration test.")
        }
        let candidates = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map { URL(fileURLWithPath: String($0)).appendingPathComponent("pi") }
        guard let executable = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) else {
            throw XCTSkip("Pi CLI is not available on PATH.")
        }
        let support = FileManager.default.temporaryDirectory.appendingPathComponent("OpenMusePiTest-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: support) }
        let runtime = PiRuntime(executableURL: executable, supportDirectoryURL: support)
        let configuration = ModelConfiguration(provider: .custom, endpoint: endpoint, model: "demo-model")
        let reply = try await runtime.reply(
            systemPrompt: "Reply with one short sentence.",
            messages: [TranscriptMessage(role: "user", content: "Say the local integration test passed.")],
            configuration: configuration,
            apiKey: "openmuse-test-token"
        )
        XCTAssertEqual(reply, "Pi RPC 本地模拟模型验证成功。")
    }
    #endif
}

private final class ModelStubURLProtocol: URLProtocol {
    static var responseData = Data()
    static var lastRequest: URLRequest?
    static var lastBody: Data?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastRequest = request
        if let body = request.httpBody {
            Self.lastBody = body
        } else if let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var data = Data()
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
            defer { buffer.deallocate() }
            while stream.hasBytesAvailable {
                let count = stream.read(buffer, maxLength: 4096)
                if count <= 0 { break }
                data.append(buffer, count: count)
            }
            Self.lastBody = data
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.responseData)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
