import Foundation
import XCTest
@testable import OpenMuseCore

final class PhoneAgentRuntimeTests: XCTestCase {
    func testLiveWeatherRequestForcesLocalBrowserSearchAndReturnsItsSourceToModel() async throws {
        PhoneAgentStubURLProtocol.reset([
            #"{"choices":[{"message":{"role":"assistant","content":null,"tool_calls":[{"id":"call-weather","type":"function","function":{"name":"openmuse_phone_browser_use","arguments":"{\"tool_title\":\"搜索广州天气\",\"action\":\"search\",\"query\":\"广州天气\"}"}}]}}]}"#,
            #"{"choices":[{"message":{"role":"assistant","content":"广州天气以网页搜索结果为准。来源：Google。"}}]}"#
        ])
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        let runtime = OpenAICompatibleRuntime(session: session)
        let configuration = ModelConfiguration(provider: .deepSeek, endpoint: "https://example.com/v1", model: "fixture", supportsToolCalling: true)
        let browserTool = ModelToolDefinition(
            name: PhoneBrowserToolRequestPolicy.toolName,
            description: "Control the persistent phone browser.",
            parameters: [
                "tool_title": ModelToolParameter(type: "string", description: "Action summary"),
                "action": ModelToolParameter(type: "string", description: "Browser action", enumValues: PhoneBrowserAction.allCases.map(\.rawValue)),
                "query": ModelToolParameter(type: "string", description: "Public search terms"),
                "url": ModelToolParameter(type: "string", description: "HTTPS URL")
            ],
            required: ["tool_title", "action"]
        )
        let executor = PhoneToolInvocationRecorder()
        let eventRecorder = PhoneToolEventRecorder()
        let result = try await runtime.replyWithTools(
            systemPrompt: "Use the phone browser for current facts.",
            messages: [TranscriptMessage(role: "user", content: "帮我查广州的天气")],
            configuration: configuration,
            apiKey: "test-key",
            tools: [browserTool],
            execute: { invocation in
                await executor.append(invocation)
                return #"{"action":"search","isSearchResult":true,"title":"广州天气","url":"https://www.google.com/search?q=广州天气","text":"广州天气，晴，25℃"}"#
            },
            onDelta: { _ in },
            onToolEvent: { await eventRecorder.append($0) }
        )

        XCTAssertEqual(result.text, "广州天气以网页搜索结果为准。来源：Google。")
        let calls = await executor.snapshot()
        XCTAssertEqual(calls.map(\.name), [PhoneBrowserToolRequestPolicy.searchToolName])
        let request = try XCTUnwrap(JSONSerialization.jsonObject(with: PhoneAgentStubURLProtocol.capturedBodies[0]) as? [String: Any])
        let definitions = try XCTUnwrap(request["tools"] as? [[String: Any]])
        XCTAssertEqual(definitions.count, 1)
        let firstFunction = try XCTUnwrap(definitions.first?["function"] as? [String: Any])
        let firstSchema = try XCTUnwrap(firstFunction["parameters"] as? [String: Any])
        let firstProperties = try XCTUnwrap(firstSchema["properties"] as? [String: Any])
        let actionSchema = try XCTUnwrap(firstProperties["action"] as? [String: Any])
        XCTAssertEqual(actionSchema["enum"] as? [String], [PhoneBrowserAction.search.rawValue])
        let forcedChoice = try XCTUnwrap(request["tool_choice"] as? [String: Any])
        XCTAssertEqual((forcedChoice["function"] as? [String: Any])?["name"] as? String, PhoneBrowserToolRequestPolicy.searchToolName)
        let followUp = try XCTUnwrap(JSONSerialization.jsonObject(with: PhoneAgentStubURLProtocol.capturedBodies[1]) as? [String: Any])
        XCTAssertEqual(followUp["tool_choice"] as? String, "auto")
        let transcript = try XCTUnwrap(followUp["messages"] as? [[String: Any]])
        XCTAssertTrue(transcript.last?["content"] as? String == #"{"action":"search","isSearchResult":true,"title":"广州天气","url":"https://www.google.com/search?q=广州天气","text":"广州天气，晴，25℃"}"#)
        let events = await eventRecorder.snapshot()
        XCTAssertEqual(events.last?.safeSummary, "搜索来源：www.google.com")
        XCTAssertEqual(events.first?.inputJSON, #"{"tool_title":"搜索广州天气","action":"search","query":"广州天气"}"#)
        XCTAssertTrue(try XCTUnwrap(events.last?.outputText).contains("广州天气，晴，25℃"))
    }

    func testBrowserIntentPolicyHonorsExplicitOfflineRequest() {
        XCTAssertTrue(PhoneBrowserToolRequestPolicy.requiresSearchTool(
            for: [TranscriptMessage(role: "user", content: "帮我查广州的天气")]
        ))
        XCTAssertTrue(PhoneBrowserToolRequestPolicy.shouldExposeTools(
            for: [TranscriptMessage(role: "user", content: "帮我查广州的天气")]
        ))
        XCTAssertTrue(PhoneBrowserToolRequestPolicy.requiresSearchTool(
            for: [TranscriptMessage(role: "user", content: "查一下今天广州的空气质量")]
        ))
        XCTAssertFalse(PhoneBrowserToolRequestPolicy.requiresSearchTool(
            for: [TranscriptMessage(role: "user", content: "不用联网，凭你知道的说说广州天气通常怎样")]
        ))
        XCTAssertFalse(PhoneBrowserToolRequestPolicy.shouldExposeTools(
            for: [TranscriptMessage(role: "user", content: "不用联网，凭你知道的说说广州天气通常怎样")]
        ))
        XCTAssertFalse(PhoneBrowserToolRequestPolicy.requiresSearchTool(
            for: [TranscriptMessage(role: "user", content: "帮我计划一趟轻松的旅行")]
        ))
        XCTAssertTrue(PhoneBrowserToolRequestPolicy.shouldExposeTools(
            for: [TranscriptMessage(role: "user", content: "帮我计划一趟轻松的旅行")]
        ))
        XCTAssertFalse(PhoneBrowserToolRequestPolicy.shouldExposeTools(
            for: [TranscriptMessage(role: "user", content: "帮我计划一趟轻松的旅行，不要用浏览器联网")]
        ))
        XCTAssertFalse(PhoneBrowserToolRequestPolicy.requiresSearchTool(
            for: [TranscriptMessage(role: "user", content: "请调用 browser_use 的 list_tabs，再读取当前页面")]
        ))
        XCTAssertNil(PhoneBrowserToolRequestPolicy.requiredAction(for: [
            TranscriptMessage(role: "user", content: "请调用 browser_use 的 list_tabs，再读取当前页面")
        ]))
        XCTAssertTrue(PhoneBrowserToolRequestPolicy.shouldExposeTools(
            for: [TranscriptMessage(role: "user", content: "帮我看看这个页面 https://example.com/guide")]
        ))
    }

    func testBrowserRequestThatExplicitlyDeclinesISHExposesBrowserWithoutShell() async throws {
        PhoneAgentStubURLProtocol.reset([
            #"{"choices":[{"message":{"role":"assistant","content":null,"tool_calls":[{"id":"call-browser-only","type":"function","function":{"name":"openmuse_phone_browser_use","arguments":"{\"tool_title\":\"打开 example.com\",\"action\":\"navigate\",\"url\":\"https://example.com/\"}"}}]}}]}"#,
            #"{"choices":[{"message":{"role":"assistant","content":null,"tool_calls":[{"id":"call-browser-read","type":"function","function":{"name":"openmuse_phone_browser_use","arguments":"{\"tool_title\":\"读取 example.com\",\"action\":\"get_readable\",\"tab_id\":3}"}}]}}]}"#,
            #"{"choices":[{"message":{"role":"assistant","content":"已打开并读取 example.com。"}}]}"#
        ])
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        let runtime = OpenAICompatibleRuntime(session: session)
        let browserTool = ModelToolDefinition(
            name: PhoneBrowserToolRequestPolicy.toolName,
            description: "Control the persistent phone browser.",
            parameters: [
                "tool_title": ModelToolParameter(type: "string", description: "Action title"),
                "action": ModelToolParameter(type: "string", description: "Browser action", enumValues: PhoneBrowserAction.allCases.map(\.rawValue)),
                "url": ModelToolParameter(type: "string", description: "Public HTTPS URL")
            ],
            required: ["tool_title", "action"]
        )
        let shellTool = ModelToolDefinition(
            name: PhoneShellToolRequestPolicy.toolName,
            description: "Execute a local iSH command.",
            parameters: ["command": ModelToolParameter(type: "string", description: "Command")],
            required: ["command"]
        )
        let executor = PhoneToolInvocationRecorder()
        let messages = [TranscriptMessage(
            role: "user",
            content: "请使用本机 browser_use 的 navigate 打开 https://example.com/，再读取同一个标签；不要调用 iSH。"
        )]
        XCTAssertFalse(PhoneShellToolRequestPolicy.requiresShellTool(for: messages))
        XCTAssertTrue(PhoneBrowserToolRequestPolicy.shouldExposeTools(for: messages))
        XCTAssertEqual(PhoneBrowserToolRequestPolicy.requiredAction(for: messages), .navigate)

        let reply = try await runtime.replyWithTools(
            systemPrompt: "Use local tools according to the current request.",
            messages: messages,
            configuration: ModelConfiguration(provider: .deepSeek, endpoint: "https://example.com/v1", model: "fixture", supportsToolCalling: true),
            apiKey: "test-key",
            tools: [shellTool, browserTool],
            execute: { invocation in
                await executor.append(invocation)
                if invocation.argumentsJSON.contains("get_readable") {
                    return #"{"action":"get_readable","tab_id":3,"title":"Example Domain","url":"https://example.com/","text":"Example Domain"}"#
                }
                return #"{"action":"navigate","tab_id":3,"title":"Example Domain","url":"https://example.com/","text":"Example Domain"}"#
            },
            onDelta: { _ in },
            onToolEvent: { _ in }
        )

        XCTAssertEqual(reply.text, "已打开并读取 example.com。")
        let calls = await executor.snapshot()
        XCTAssertEqual(calls.map(\.name), [PhoneBrowserToolRequestPolicy.toolName, PhoneBrowserToolRequestPolicy.toolName])
        XCTAssertTrue(calls[0].argumentsJSON.contains("\"action\":\"navigate\""))
        XCTAssertTrue(calls[1].argumentsJSON.contains("\"action\":\"get_readable\""))
        XCTAssertTrue(calls[1].argumentsJSON.contains("\"tab_id\":3"))
        let request = try XCTUnwrap(JSONSerialization.jsonObject(with: PhoneAgentStubURLProtocol.capturedBodies[0]) as? [String: Any])
        let definitions = try XCTUnwrap(request["tools"] as? [[String: Any]])
        let names = definitions.compactMap { ($0["function"] as? [String: Any])?["name"] as? String }
        XCTAssertEqual(names, [PhoneBrowserToolRequestPolicy.toolName])
        let firstAction = try XCTUnwrap(((definitions.first?["function"] as? [String: Any])?["parameters"] as? [String: Any])?["properties"] as? [String: Any])
        XCTAssertEqual((firstAction["action"] as? [String: Any])?["enum"] as? [String], [PhoneBrowserAction.navigate.rawValue])
        let followUp = try XCTUnwrap(JSONSerialization.jsonObject(with: PhoneAgentStubURLProtocol.capturedBodies[1]) as? [String: Any])
        XCTAssertEqual(followUp["tool_choice"] as? String, "auto")
    }

    func testRequiredBrowserNavigationFailureDoesNotReturnModelSuccess() async throws {
        PhoneAgentStubURLProtocol.reset([
            #"{"choices":[{"message":{"role":"assistant","content":null,"tool_calls":[{"id":"call-navigate","type":"function","function":{"name":"openmuse_phone_browser_use","arguments":"{\"tool_title\":\"打开页面\",\"action\":\"navigate\",\"url\":\"https://example.com/\"}"}}]}}]}"#
        ])
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        let runtime = OpenAICompatibleRuntime(session: session)
        let browserTool = ModelToolDefinition(
            name: PhoneBrowserToolRequestPolicy.toolName,
            description: "Control the persistent phone browser.",
            parameters: [
                "tool_title": ModelToolParameter(type: "string", description: "Action title"),
                "action": ModelToolParameter(type: "string", description: "Browser action", enumValues: PhoneBrowserAction.allCases.map(\.rawValue)),
                "url": ModelToolParameter(type: "string", description: "Public HTTPS URL")
            ],
            required: ["tool_title", "action"]
        )
        let events = PhoneToolEventRecorder()

        do {
            _ = try await runtime.replyWithTools(
                systemPrompt: "Use the phone browser.",
                messages: [TranscriptMessage(role: "user", content: "打开 https://example.com/")],
                configuration: ModelConfiguration(provider: .deepSeek, endpoint: "https://example.com/v1", model: "fixture", supportsToolCalling: true),
                apiKey: "test-key",
                tools: [browserTool],
                execute: { _ in throw PhoneBrowserError.pageUnavailable },
                onDelta: { _ in },
                onToolEvent: { await events.append($0) }
            )
            XCTFail("A failed required navigation must not produce a normal assistant answer.")
        } catch let error as ModelRuntimeError {
            guard case .server(let message) = error else { return XCTFail("Unexpected error: \(error)") }
            XCTAssertTrue(message.contains("navigate"))
            XCTAssertTrue(message.contains("失败"))
        }

        XCTAssertEqual(PhoneAgentStubURLProtocol.capturedBodies.count, 1)
        let recordedEvents = await events.snapshot()
        XCTAssertEqual(recordedEvents.map(\.status), ["started", "failed"])
    }

    func testOrdinaryTaskCanSelectISHShellWithoutMentioningItAndBrowserIsAvailableByDefault() async throws {
        PhoneAgentStubURLProtocol.reset([
            #"{"choices":[{"message":{"role":"assistant","content":null,"tool_calls":[{"id":"call-shell-general","type":"function","function":{"name":"openmuse_phone_run_ish_command","arguments":"{\"command\":\"printf ready\"}"}}]}}]}"#,
            #"{"choices":[{"message":{"role":"assistant","content":"我已在本机整理好材料。"}}]}"#
        ])
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        let runtime = OpenAICompatibleRuntime(session: session)
        let executor = PhoneToolInvocationRecorder()
        let eventRecorder = PhoneToolEventRecorder()
        let tools = [
            ModelToolDefinition(
                name: PhoneShellToolRequestPolicy.toolName,
                description: "Execute a sandboxed iSH command.",
                parameters: ["command": ModelToolParameter(type: "string", description: "Shell command")],
                required: ["command"]
            ),
            ModelToolDefinition(
                name: PhoneBrowserToolRequestPolicy.toolName,
                description: "Control the persistent phone browser.",
                parameters: [
                    "tool_title": ModelToolParameter(type: "string", description: "Action title"),
                    "action": ModelToolParameter(type: "string", description: "Browser action", enumValues: PhoneBrowserAction.allCases.map(\.rawValue)),
                    "query": ModelToolParameter(type: "string", description: "Public search terms"),
                    "url": ModelToolParameter(type: "string", description: "Public HTTPS page URL"),
                    "tab_id": ModelToolParameter(type: "integer", description: "Existing tab ID")
                ],
                required: ["tool_title", "action"]
            ),
            ModelToolDefinition(
                name: "openmuse_phone_search_history",
                description: "Search local conversation history.",
                parameters: ["query": ModelToolParameter(type: "string", description: "Local query")],
                required: ["query"]
            )
        ]

        _ = try await runtime.replyWithTools(
            systemPrompt: "Only use tools that match the user's request.",
            messages: [TranscriptMessage(role: "user", content: "帮我整理当前对话里的旅行材料")],
            configuration: ModelConfiguration(provider: .deepSeek, endpoint: "https://example.com/v1", model: "fixture", supportsToolCalling: true),
            apiKey: "test-key",
            tools: tools,
            execute: { invocation in
                await executor.append(invocation)
                return #"{"exitCode":124,"output":"stopped","timedOut":true}"#
            },
            onDelta: { _ in },
            onToolEvent: { await eventRecorder.append($0) }
        )

        let calls = await executor.snapshot()
        let events = await eventRecorder.snapshot()
        XCTAssertEqual(calls.map(\.name), [PhoneShellToolRequestPolicy.toolName])
        XCTAssertEqual(events.map(\.status), ["started", "timed-out"])
        XCTAssertTrue(try XCTUnwrap(events.last?.outputText).contains("stopped"))
        let request = try XCTUnwrap(JSONSerialization.jsonObject(with: PhoneAgentStubURLProtocol.capturedBodies[0]) as? [String: Any])
        let definitions = try XCTUnwrap(request["tools"] as? [[String: Any]])
        let functionDefinitions = try XCTUnwrap(definitions.map { try XCTUnwrap($0["function"] as? [String: Any]) })
        let names = functionDefinitions.compactMap { $0["name"] as? String }
        XCTAssertEqual(names, [PhoneShellToolRequestPolicy.toolName, PhoneBrowserToolRequestPolicy.toolName, "openmuse_phone_search_history"])
        XCTAssertEqual(request["tool_choice"] as? String, "auto")
        XCTAssertEqual(PhoneAgentStubURLProtocol.capturedBodies.count, 2)
    }

    func testRequiredBrowserSearchFailsClosedWhenTheDeviceHasNoBrowserTool() async throws {
        PhoneAgentStubURLProtocol.reset([])
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        let runtime = OpenAICompatibleRuntime(session: session)
        do {
            _ = try await runtime.replyWithTools(
                systemPrompt: "No browser available.",
                messages: [TranscriptMessage(role: "user", content: "帮我查广州天气")],
                configuration: ModelConfiguration(provider: .deepSeek, endpoint: "https://example.com/v1", model: "fixture", supportsToolCalling: true),
                apiKey: "test-key",
                tools: [],
                execute: { _ in "unexpected" },
                onDelta: { _ in },
                onToolEvent: { _ in }
            )
            XCTFail("A live weather request must not fall back to an unsupported model-only answer.")
        } catch let error as ModelRuntimeError {
            guard case .server(let message) = error else { return XCTFail("Unexpected error: \(error)") }
            XCTAssertTrue(message.contains("没有提供网页查询工具"))
            XCTAssertTrue(message.contains("没有执行"))
        }
        XCTAssertTrue(PhoneAgentStubURLProtocol.capturedBodies.isEmpty)
    }

    func testFailedBrowserSearchStopsBeforeModelCanInventAnotherAttempt() async throws {
        PhoneAgentStubURLProtocol.reset([
            #"{"choices":[{"message":{"role":"assistant","content":null,"tool_calls":[{"id":"call-weather-fail","type":"function","function":{"name":"openmuse_phone_browser_use","arguments":"{\"tool_title\":\"搜索广州天气\",\"action\":\"search\",\"query\":\"广州天气\"}"}}]}}]}"#
        ])
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        let runtime = OpenAICompatibleRuntime(session: session)
        let tool = ModelToolDefinition(
            name: PhoneBrowserToolRequestPolicy.toolName,
            description: "Control the persistent phone browser.",
            parameters: [
                "tool_title": ModelToolParameter(type: "string", description: "Action summary"),
                "action": ModelToolParameter(type: "string", description: "Browser action", enumValues: PhoneBrowserAction.allCases.map(\.rawValue)),
                "query": ModelToolParameter(type: "string", description: "Public search terms")
            ],
            required: ["tool_title", "action"]
        )
        let events = PhoneToolEventRecorder()
        let deltas = PhoneTextDeltaRecorder()

        do {
            _ = try await runtime.replyWithTools(
                systemPrompt: "Use the browser; report only recorded results.",
                messages: [TranscriptMessage(role: "user", content: "帮我查广州天气")],
                configuration: ModelConfiguration(provider: .deepSeek, endpoint: "https://example.com/v1", model: "fixture", supportsToolCalling: true),
                apiKey: "test-key",
                tools: [tool],
                execute: { _ in
                    throw PhoneBrowserError.searchUnavailable(attemptedEngines: [.google, .bing], lastFailure: "网页加载超时。")
                },
                onDelta: { await deltas.append($0) },
                onToolEvent: { await events.append($0) }
            )
            XCTFail("A failed real search must not be followed by model-authored search claims.")
        } catch let error as ModelRuntimeError {
            guard case .server(let message) = error else { return XCTFail("Unexpected error: \(error)") }
            XCTAssertTrue(message.contains("Google、Bing"))
            XCTAssertTrue(message.contains("没有获得搜索结果"))
            XCTAssertTrue(message.contains("没有使用旧数据"))
        }

        XCTAssertEqual(PhoneAgentStubURLProtocol.capturedBodies.count, 1)
        let emittedDeltas = await deltas.snapshot()
        let eventStatuses = await events.snapshot().map(\.status)
        XCTAssertTrue(emittedDeltas.isEmpty)
        XCTAssertEqual(eventStatuses, ["started", "failed"])
    }

    func testToolLoopRunsApprovedPhoneToolAndReturnsItsResultToModel() async throws {
        PhoneAgentStubURLProtocol.reset([
            #"{"choices":[{"message":{"role":"assistant","content":null,"tool_calls":[{"id":"call-1","type":"function","function":{"name":"openmuse_phone_search_history","arguments":"{\"query\":\"旅行\"}"}}]}}],"usage":{"prompt_tokens":10,"completion_tokens":3,"total_tokens":13}}"#,
            #"{"choices":[{"message":{"role":"assistant","content":"记得你之前在聊恩施旅行，我们可以接着整理。"}}],"usage":{"prompt_tokens":20,"completion_tokens":8,"total_tokens":28}}"#
        ])
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        let runtime = OpenAICompatibleRuntime(session: session)
        let configuration = ModelConfiguration(provider: .custom, endpoint: "https://example.com/v1", model: "fixture", supportsToolCalling: true)
        let executor = PhoneToolInvocationRecorder()
        let events = PhoneToolEventRecorder()
        let deltas = PhoneTextDeltaRecorder()
        let result = try await runtime.replyWithTools(
            systemPrompt: "Use local tools only when needed.",
            messages: [TranscriptMessage(role: "user", content: "接着聊旅行")],
            configuration: configuration,
            apiKey: "test-key",
            tools: [ModelToolDefinition(
                name: "openmuse_phone_search_history",
                description: "Search user-authored history.",
                parameters: ["query": ModelToolParameter(type: "string", description: "Search terms")],
                required: ["query"]
            )],
            execute: { invocation in
                await executor.append(invocation)
                return #"{"source":"local","userQuote":"用户原话"}"#
            },
            onDelta: { await deltas.append($0) },
            onToolEvent: { await events.append($0) }
        )

        XCTAssertEqual(result.text, "记得你之前在聊恩施旅行，我们可以接着整理。")
        XCTAssertEqual(result.usage, ModelUsage(inputTokens: 30, outputTokens: 11, totalTokens: 41))
        let calls = await executor.snapshot()
        let recordedEvents = await events.snapshot()
        let recordedDeltas = await deltas.snapshot()
        XCTAssertEqual(calls.map(\.name), ["openmuse_phone_search_history"])
        XCTAssertEqual(calls.first?.argumentsJSON, #"{"query":"旅行"}"#)
        XCTAssertEqual(recordedEvents.map(\.status), ["started", "completed"])
        XCTAssertEqual(recordedDeltas, ["记得你之前在聊恩施旅行，我们可以接着整理。"])

        let bodies = PhoneAgentStubURLProtocol.capturedBodies
        XCTAssertEqual(bodies.count, 2)
        let first = try XCTUnwrap(JSONSerialization.jsonObject(with: bodies[0]) as? [String: Any])
        let definitions = try XCTUnwrap(first["tools"] as? [[String: Any]])
        XCTAssertEqual(((definitions.first?["function"] as? [String: Any])?["name"] as? String), "openmuse_phone_search_history")
        let second = try XCTUnwrap(JSONSerialization.jsonObject(with: bodies[1]) as? [String: Any])
        let transcript = try XCTUnwrap(second["messages"] as? [[String: Any]])
        XCTAssertEqual(transcript.suffix(2).first?["role"] as? String, "assistant")
        XCTAssertEqual(transcript.last?["role"] as? String, "tool")
        XCTAssertEqual(transcript.last?["tool_call_id"] as? String, "call-1")
        XCTAssertEqual(transcript.last?["content"] as? String, #"{"source":"local","userQuote":"用户原话"}"#)
    }

    func testExplicitISHRequestForcesTheShellToolAndDoesNotOfferOtherTools() async throws {
        PhoneAgentStubURLProtocol.reset([
            #"{"choices":[{"message":{"role":"assistant","content":null,"tool_calls":[{"id":"call-shell","type":"function","function":{"name":"openmuse_phone_run_ish_command","arguments":"{\"command\":\"uname -a && cat /etc/alpine-release\"}"}}]}}]}"#,
            #"{"choices":[{"message":{"role":"assistant","content":"已收到真实 iSH 工具结果。"}}]}"#
        ])
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        let runtime = OpenAICompatibleRuntime(session: session)
        let configuration = ModelConfiguration(provider: .deepSeek, endpoint: "https://example.com/v1", model: "fixture", supportsToolCalling: true)
        let shellTool = ModelToolDefinition(
            name: PhoneShellToolRequestPolicy.toolName,
            description: "Run one approved command in iSH.",
            parameters: ["command": ModelToolParameter(type: "string", description: "Full shell command")],
            required: ["command"]
        )
        let historyTool = ModelToolDefinition(name: "openmuse_phone_search_history", description: "Search history", parameters: [:], required: [])
        let executor = PhoneToolInvocationRecorder()
        let request = "请现在通过 OpenMuse 的 iSH 工具调用，只执行这一条命令：uname -a && cat /etc/alpine-release。不要追加命令，并用实际输出回复。"

        let result = try await runtime.replyWithTools(
            systemPrompt: "用户明确要求 iSH 命令时必须调用工具，不得编造结果；普通命令不需要逐次审批。",
            messages: [TranscriptMessage(role: "user", content: request)],
            configuration: configuration,
            apiKey: "test-key",
            tools: [historyTool, shellTool],
            execute: { invocation in
                await executor.append(invocation)
                return #"{"exitCode":0,"output":"Linux localhost\\n3.24.2","timedOut":false}"#
            },
            onDelta: { _ in },
            onToolEvent: { _ in }
        )

        XCTAssertEqual(result.text, "已收到真实 iSH 工具结果。")
        let calls = await executor.snapshot()
        XCTAssertEqual(calls.map(\.name), [PhoneShellToolRequestPolicy.toolName])
        let bodies = PhoneAgentStubURLProtocol.capturedBodies
        XCTAssertEqual(bodies.count, 2)
        let first = try XCTUnwrap(JSONSerialization.jsonObject(with: bodies[0]) as? [String: Any])
        let tools = try XCTUnwrap(first["tools"] as? [[String: Any]])
        XCTAssertEqual(tools.count, 1)
        XCTAssertEqual(((tools[0]["function"] as? [String: Any])?["name"] as? String), PhoneShellToolRequestPolicy.toolName)
        let choice = try XCTUnwrap(first["tool_choice"] as? [String: Any])
        XCTAssertEqual(choice["type"] as? String, "function")
        XCTAssertEqual((choice["function"] as? [String: Any])?["name"] as? String, PhoneShellToolRequestPolicy.toolName)
        let second = try XCTUnwrap(JSONSerialization.jsonObject(with: bodies[1]) as? [String: Any])
        XCTAssertEqual(second["tool_choice"] as? String, "auto")
    }

    func testExplicitISHRequestFailsClosedWhenModelReturnsTextWithoutCallingTool() async throws {
        PhoneAgentStubURLProtocol.reset([
            #"{"choices":[{"message":{"role":"assistant","content":"第一条命令已执行完成，内核为 Linux；Alpine 3.24.2。"}}]}"#
        ])
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        let runtime = OpenAICompatibleRuntime(session: session)
        let configuration = ModelConfiguration(provider: .deepSeek, endpoint: "https://example.com/v1", model: "fixture", supportsToolCalling: true)
        let shellTool = ModelToolDefinition(
            name: PhoneShellToolRequestPolicy.toolName,
            description: "Run one approved command in iSH.",
            parameters: ["command": ModelToolParameter(type: "string", description: "Full shell command")],
            required: ["command"]
        )
        let executor = PhoneToolInvocationRecorder()
        let deltas = PhoneTextDeltaRecorder()
        do {
            _ = try await runtime.replyWithTools(
                systemPrompt: "不得编造工具执行结果。",
                messages: [TranscriptMessage(role: "user", content: "请通过 iSH 工具执行 uname -a。")],
                configuration: configuration,
                apiKey: "test-key",
                tools: [shellTool],
                execute: { invocation in await executor.append(invocation); return "unexpected" },
                onDelta: { await deltas.append($0) },
                onToolEvent: { _ in }
            )
            XCTFail("A text-only response cannot stand in for an explicitly requested shell call.")
        } catch let error as ModelRuntimeError {
            guard case .server(let message) = error else { return XCTFail("Unexpected error: \(error)") }
            XCTAssertTrue(message.contains("没有返回 iSH 工具调用"))
            XCTAssertTrue(message.contains("命令没有执行"))
        }
        let calls = await executor.snapshot()
        let streamed = await deltas.snapshot()
        XCTAssertTrue(calls.isEmpty)
        XCTAssertTrue(streamed.isEmpty)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: PhoneAgentStubURLProtocol.capturedBodies[0]) as? [String: Any])
        XCTAssertNotNil(body["tool_choice"] as? [String: Any])
    }

    func testExplicitISHRequestFailsClosedWhenToolCallingIsDisabled() async throws {
        PhoneAgentStubURLProtocol.reset(["should not be requested"])
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        let runtime = OpenAICompatibleRuntime(session: session)
        let configuration = ModelConfiguration(
            provider: .deepSeek,
            endpoint: "https://example.com/v1",
            model: "fixture",
            supportsToolCalling: false,
            supportsStreamingResponses: true
        )
        let executor = PhoneToolInvocationRecorder()
        do {
            _ = try await runtime.replyWithTools(
                systemPrompt: "No tools.",
                messages: [TranscriptMessage(role: "user", content: "请在 iSH 里运行 uname -a")],
                configuration: configuration,
                apiKey: "test-key",
                tools: [ModelToolDefinition(name: PhoneShellToolRequestPolicy.toolName, description: "Run", parameters: [:], required: [])],
                execute: { invocation in await executor.append(invocation); return "unexpected" },
                onDelta: { _ in },
                onToolEvent: { _ in }
            )
            XCTFail("Disabled tool calling must not fall back to text when shell execution was requested.")
        } catch let error as ModelRuntimeError {
            guard case .server(let message) = error else { return XCTFail("Unexpected error: \(error)") }
            XCTAssertTrue(message.contains("iSH 命令没有执行"))
        }
        let calls = await executor.snapshot()
        XCTAssertTrue(calls.isEmpty)
        XCTAssertTrue(PhoneAgentStubURLProtocol.capturedBodies.isEmpty)
    }

    func testExplicitISHNonExecutionRequestDoesNotForceOrExposeShellTool() async throws {
        PhoneAgentStubURLProtocol.reset([
            #"{"choices":[{"message":{"role":"assistant","content":"我不会运行命令。"}}]}"#
        ])
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        let runtime = OpenAICompatibleRuntime(session: session)
        let configuration = ModelConfiguration(provider: .custom, endpoint: "https://example.com/v1", model: "fixture", supportsToolCalling: true)
        let shellTool = ModelToolDefinition(name: PhoneShellToolRequestPolicy.toolName, description: "Run", parameters: [:], required: [])
        let executor = PhoneToolInvocationRecorder()
        let result = try await runtime.replyWithTools(
            systemPrompt: "No execution.",
            messages: [
                TranscriptMessage(role: "user", content: "请通过 iSH 工具运行 uname -a"),
                TranscriptMessage(role: "assistant", content: "我不会运行命令。"),
                TranscriptMessage(role: "user", content: "解释一下，先不要再运行 iSH 命令。")
            ],
            configuration: configuration,
            apiKey: "test-key",
            tools: [shellTool],
            execute: { invocation in await executor.append(invocation); return "unexpected" },
            onDelta: { _ in },
            onToolEvent: { _ in }
        )
        XCTAssertEqual(result.text, "我不会运行命令。")
        let calls = await executor.snapshot()
        XCTAssertTrue(calls.isEmpty)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: PhoneAgentStubURLProtocol.capturedBodies[0]) as? [String: Any])
        XCTAssertNil(body["tools"])
        XCTAssertNil(body["tool_choice"])
    }

    func testDisabledToolCapabilityFallsBackToStreamingWithoutSendingTools() async throws {
        PhoneAgentStubURLProtocol.reset([
            "data: {\"choices\":[{\"delta\":{\"content\":\"可以继续聊。\"}}]}\n\ndata: [DONE]\n\n"
        ])
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        let runtime = OpenAICompatibleRuntime(session: session)
        let executor = PhoneToolInvocationRecorder()
        let deltas = PhoneTextDeltaRecorder()
        let result = try await runtime.replyWithTools(
            systemPrompt: "No tools this turn.",
            messages: [TranscriptMessage(role: "user", content: "帮我计划旅行")],
            configuration: ModelConfiguration(
                provider: .custom,
                endpoint: "https://example.com/v1",
                model: "plain-chat",
                supportsToolCalling: false,
                supportsStreamingResponses: true
            ),
            apiKey: "test-key",
            tools: [ModelToolDefinition(name: "read_local", description: "Read", parameters: [:], required: [])],
            execute: { invocation in await executor.append(invocation); return "must not run" },
            onDelta: { await deltas.append($0) },
            onToolEvent: { _ in }
        )

        XCTAssertEqual(result.text, "可以继续聊。")
        let invocations = await executor.snapshot()
        let streamedDeltas = await deltas.snapshot()
        XCTAssertTrue(invocations.isEmpty)
        XCTAssertEqual(streamedDeltas, ["可以继续聊。"])
        let request = try XCTUnwrap(JSONSerialization.jsonObject(with: PhoneAgentStubURLProtocol.capturedBodies[0]) as? [String: Any])
        XCTAssertNil(request["tools"])
        XCTAssertEqual(request["stream"] as? Bool, true)
    }

    func testDisabledToolAndStreamingCapabilitiesUsePlainNonStreamingChat() async throws {
        PhoneAgentStubURLProtocol.reset([
            #"{"choices":[{"message":{"content":"可以先从日期开始。"}}],"usage":{"prompt_tokens":7,"completion_tokens":5,"total_tokens":12}}"#
        ])
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        let runtime = OpenAICompatibleRuntime(session: session)
        let executor = PhoneToolInvocationRecorder()
        let result = try await runtime.replyWithTools(
            systemPrompt: "No tools or streaming.",
            messages: [TranscriptMessage(role: "user", content: "规划出行")],
            configuration: ModelConfiguration(
                provider: .custom,
                endpoint: "https://example.com/v1",
                model: "plain-chat",
                supportsToolCalling: false,
                supportsStreamingResponses: false
            ),
            apiKey: "test-key",
            tools: [ModelToolDefinition(name: "read_local", description: "Read", parameters: [:], required: [])],
            execute: { invocation in await executor.append(invocation); return "must not run" },
            onDelta: { _ in },
            onToolEvent: { _ in }
        )

        XCTAssertEqual(result.text, "可以先从日期开始。")
        XCTAssertEqual(result.usage, ModelUsage(inputTokens: 7, outputTokens: 5, totalTokens: 12))
        let invocations = await executor.snapshot()
        XCTAssertTrue(invocations.isEmpty)
        let request = try XCTUnwrap(JSONSerialization.jsonObject(with: PhoneAgentStubURLProtocol.capturedBodies[0]) as? [String: Any])
        XCTAssertNil(request["tools"])
        XCTAssertEqual(request["stream"] as? Bool, false)
    }

    func testUnlistedToolIsNeverExecuted() async throws {
        PhoneAgentStubURLProtocol.reset([
            #"{"choices":[{"message":{"role":"assistant","content":null,"tool_calls":[{"id":"call-bad","type":"function","function":{"name":"openmuse_phone_delete_everything","arguments":"{}"}}]}}]}"#,
            #"{"choices":[{"message":{"role":"assistant","content":"我没有执行未开放的动作。"}}]}"#
        ])
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        let runtime = OpenAICompatibleRuntime(session: session)
        let executor = PhoneToolInvocationRecorder()
        let events = PhoneToolEventRecorder()
        _ = try await runtime.replyWithTools(
            systemPrompt: "Use tools safely.",
            messages: [TranscriptMessage(role: "user", content: "查资料")],
            configuration: ModelConfiguration(provider: .custom, endpoint: "https://example.com/v1", model: "fixture", supportsToolCalling: true),
            apiKey: "test-key",
            tools: [ModelToolDefinition(name: "openmuse_phone_search_history", description: "Search", parameters: [:], required: [])],
            execute: { invocation in await executor.append(invocation); return "should not run" },
            onDelta: { _ in },
            onToolEvent: { await events.append($0) }
        )
        let calls = await executor.snapshot()
        let recordedEvents = await events.snapshot()
        XCTAssertTrue(calls.isEmpty)
        XCTAssertEqual(recordedEvents.map(\.status), ["started", "failed"])
        let second = try XCTUnwrap(JSONSerialization.jsonObject(with: PhoneAgentStubURLProtocol.capturedBodies[1]) as? [String: Any])
        let transcript = try XCTUnwrap(second["messages"] as? [[String: Any]])
        XCTAssertTrue((transcript.last?["content"] as? String)?.contains("没有执行动作") == true)
    }

    func testUserDenialStopsThatToolAndReturnsTheDenialToTheModel() async throws {
        PhoneAgentStubURLProtocol.reset([
            #"{"choices":[{"message":{"role":"assistant","content":null,"tool_calls":[{"id":"call-write","type":"function","function":{"name":"write_draft","arguments":"{\"path\":\"travel.md\",\"content\":\"draft\"}"}}]}}]}"#,
            #"{"choices":[{"message":{"role":"assistant","content":"好的，我没有保存草稿。"}}]}"#
        ])
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        let runtime = OpenAICompatibleRuntime(session: session)
        let events = PhoneToolEventRecorder()
        let result = try await runtime.replyWithTools(
            systemPrompt: "Use the requested tools.",
            messages: [TranscriptMessage(role: "user", content: "先写草稿")],
            configuration: ModelConfiguration(provider: .custom, endpoint: "https://example.com/v1", model: "fixture", supportsToolCalling: true),
            apiKey: "test-key",
            tools: [ModelToolDefinition(name: "write_draft", description: "Write draft", parameters: [:], required: [])],
            execute: { _ in throw ModelToolExecutionError.userDenied },
            onDelta: { _ in },
            onToolEvent: { await events.append($0) }
        )

        XCTAssertEqual(result.text, "好的，我没有保存草稿。")
        let recordedEvents = await events.snapshot()
        XCTAssertEqual(recordedEvents.map(\.status), ["started", "denied"])
        let second = try XCTUnwrap(JSONSerialization.jsonObject(with: PhoneAgentStubURLProtocol.capturedBodies[1]) as? [String: Any])
        let transcript = try XCTUnwrap(second["messages"] as? [[String: Any]])
        XCTAssertEqual(transcript.last?["role"] as? String, "tool")
        XCTAssertTrue((transcript.last?["content"] as? String)?.contains("用户拒绝") == true)
        XCTAssertTrue((transcript.last?["content"] as? String)?.contains("没有执行") == true)
    }

    func testToolLoopStopsAtSixRounds() async throws {
        let repeatedCall = #"{"choices":[{"message":{"role":"assistant","content":null,"tool_calls":[{"id":"call-next","type":"function","function":{"name":"read","arguments":"{}"}}]}}]}"#
        PhoneAgentStubURLProtocol.reset(Array(repeating: repeatedCall, count: 6))
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        let runtime = OpenAICompatibleRuntime(session: session)
        let executor = PhoneToolInvocationRecorder()
        do {
            _ = try await runtime.replyWithTools(
                systemPrompt: "Run tool loop.",
                messages: [TranscriptMessage(role: "user", content: "continue")],
                configuration: ModelConfiguration(provider: .custom, endpoint: "https://example.com/v1", model: "fixture", supportsToolCalling: true),
                apiKey: "test-key",
                tools: [ModelToolDefinition(name: "read", description: "Read", parameters: [:], required: [])],
                execute: { invocation in await executor.append(invocation); return "ok" },
                onDelta: { _ in },
                onToolEvent: { _ in }
            )
            XCTFail("A model must not keep the phone runtime in an unbounded tool loop.")
        } catch let error as ModelRuntimeError {
            guard case .server(let message) = error else { return XCTFail("Unexpected error: \(error)") }
            XCTAssertTrue(message.contains("6 轮上限"))
        }
        let calls = await executor.snapshot()
        XCTAssertEqual(calls.count, 6)
        XCTAssertEqual(PhoneAgentStubURLProtocol.capturedBodies.count, 6)
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PhoneAgentStubURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}

private actor PhoneToolInvocationRecorder {
    private(set) var values: [ModelToolInvocation] = []
    func append(_ value: ModelToolInvocation) { values.append(value) }
    func snapshot() -> [ModelToolInvocation] { values }
}

private actor PhoneToolEventRecorder {
    private(set) var values: [ModelToolExecutionEvent] = []
    func append(_ value: ModelToolExecutionEvent) { values.append(value) }
    func snapshot() -> [ModelToolExecutionEvent] { values }
}

private actor PhoneTextDeltaRecorder {
    private(set) var values: [String] = []
    func append(_ value: String) { values.append(value) }
    func snapshot() -> [String] { values }
}

private final class PhoneAgentStubURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var responses: [Data] = []
    private static var requestBodies: [Data] = []

    static var capturedBodies: [Data] {
        lock.lock(); defer { lock.unlock() }
        return requestBodies
    }

    static func reset(_ jsonResponses: [String]) {
        lock.lock(); defer { lock.unlock() }
        responses = jsonResponses.map { Data($0.utf8) }
        requestBodies = []
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let body: Data
        if let httpBody = request.httpBody {
            body = httpBody
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
            body = data
        } else {
            body = Data()
        }
        Self.lock.lock()
        Self.requestBodies.append(body)
        let responseBody = Self.responses.isEmpty ? Data(#"{"error":{"message":"No fixture response"}}"#.utf8) : Self.responses.removeFirst()
        Self.lock.unlock()
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: responseBody)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
