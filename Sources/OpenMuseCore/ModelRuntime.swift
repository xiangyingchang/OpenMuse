import Foundation

public enum ModelRuntimeError: Error, LocalizedError {
    case invalidEndpoint
    case missingKey
    case server(String)
    case emptyResponse
    case piUnavailable
    case piFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidEndpoint: "模型地址无效。请检查设置中的 API 地址。"
        case .missingKey: "还没有保存模型密钥。请先在设置中配置。"
        case .server(let message): message
        case .emptyResponse: "模型返回了空内容，请重试或更换模型。"
        case .piUnavailable: "Mac 没有找到 Pi。请先安装 Pi 并确认它可从终端启动。"
        case .piFailed(let detail): detail
        }
    }
}

public protocol ModelRuntime {
    func reply(systemPrompt: String, messages: [TranscriptMessage], configuration: ModelConfiguration, apiKey: String) async throws -> String
}

public struct OpenAICompatibleRuntime: ModelRuntime {
    private let session: URLSession

    public init(session: URLSession = .shared) { self.session = session }

    public func reply(systemPrompt: String, messages: [TranscriptMessage], configuration: ModelConfiguration, apiKey: String) async throws -> String {
        guard configuration.isReady, let url = chatCompletionsURL(configuration.endpoint) else { throw ModelRuntimeError.invalidEndpoint }
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ModelRuntimeError.missingKey }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        var transcript = [["role": "system", "content": systemPrompt]]
        transcript += messages.suffix(24).map { ["role": $0.role, "content": $0.content] }
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": configuration.model,
            "messages": transcript,
            "stream": false
        ])

        let (data, response): (Data, URLResponse)
        do { (data, response) = try await session.data(for: request) }
        catch { throw ModelRuntimeError.server("连接模型失败：\(error.localizedDescription)") }
        guard let http = response as? HTTPURLResponse else { throw ModelRuntimeError.server("模型服务没有返回有效的 HTTP 响应。") }
        guard (200..<300).contains(http.statusCode) else {
            let serverMessage = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                .flatMap { ($0["error"] as? [String: Any])?["message"] as? String }
            throw ModelRuntimeError.server(serverMessage ?? "模型服务返回 HTTP \(http.statusCode)。请检查地址、密钥和模型名称。")
        }
        guard let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = body["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String,
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ModelRuntimeError.emptyResponse }
        return content
    }

    private func chatCompletionsURL(_ base: String) -> URL? {
        let cleaned = base.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !cleaned.isEmpty else { return nil }
        let path = cleaned.hasSuffix("/chat/completions") ? "" : "/chat/completions"
        return URL(string: cleaned + path)
    }
}

#if os(macOS)
/// Runs Pi in a one-request, no-tools RPC session. The model credential is passed only
/// through the child process environment; the prompt travels over stdin, never argv.
public struct PiRuntime: ModelRuntime {
    private let executableOverride: URL?
    private let supportDirectoryOverride: URL?

    public init(executableURL: URL? = nil, supportDirectoryURL: URL? = nil) {
        executableOverride = executableURL
        supportDirectoryOverride = supportDirectoryURL
    }

    public func reply(systemPrompt: String, messages: [TranscriptMessage], configuration: ModelConfiguration, apiKey: String) async throws -> String {
        guard configuration.isReady else { throw ModelRuntimeError.invalidEndpoint }
        guard !apiKey.isEmpty else { throw ModelRuntimeError.missingKey }
        let executableOverride = self.executableOverride
        let supportDirectoryOverride = self.supportDirectoryOverride
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let result = try Self.run(systemPrompt: systemPrompt, messages: messages, configuration: configuration, apiKey: apiKey, executableOverride: executableOverride, supportDirectoryOverride: supportDirectoryOverride)
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func run(systemPrompt: String, messages: [TranscriptMessage], configuration: ModelConfiguration, apiKey: String, executableOverride: URL?, supportDirectoryOverride: URL?) throws -> String {
        guard let executable = executableOverride ?? piExecutable() else { throw ModelRuntimeError.piUnavailable }
        let applicationSupport: URL
        if let supportDirectoryOverride {
            applicationSupport = supportDirectoryOverride
        } else {
            applicationSupport = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        }
        let piHome = applicationSupport.appendingPathComponent("OpenMuse/pi", isDirectory: true)
        try FileManager.default.createDirectory(at: piHome, withIntermediateDirectories: true)

        let provider: [String: Any] = [
            "name": "OpenMuse",
            "baseUrl": configuration.endpoint.trimmingCharacters(in: CharacterSet(charactersIn: "/")),
            "api": "openai-completions",
            "apiKey": "$OPENMUSE_API_KEY",
            "models": [[
                "id": configuration.model,
                "name": configuration.model,
                "api": "openai-completions",
                "contextWindow": max(8_192, configuration.contextWindow),
                "maxTokens": 4_096,
                "input": ["text"],
                "cost": ["input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0]
            ]]
        ]
        let modelConfig = try JSONSerialization.data(withJSONObject: ["providers": ["openmuse": provider]], options: [.prettyPrinted, .sortedKeys])
        try modelConfig.write(to: piHome.appendingPathComponent("models.json"), options: .atomic)

        let transcript = messages.suffix(24).map { item in
            "\(item.role == "assistant" ? "OpenMuse" : "User"): \(item.content)"
        }.joined(separator: "\n\n")
        let prompt = "\(systemPrompt)\n\n以下是最近的对话。请自然地接着回应用户。\n\n\(transcript)\n\nOpenMuse:"
        var input = try JSONSerialization.data(withJSONObject: ["id": "openmuse-turn", "type": "prompt", "message": prompt])
        input.append(10)

        let process = Process()
        process.executableURL = executable
        process.arguments = [
            "--mode", "rpc", "--no-session", "--no-tools", "--no-extensions", "--no-mcp", "--no-skills", "--no-context-files",
            "--provider", "openmuse", "--model", configuration.model, "--thinking", "off",
            "--system-prompt", "You are OpenMuse, a helpful personal assistant. Follow the user's request and do not claim tools or actions you did not perform."
        ]
        var environment = ProcessInfo.processInfo.environment
        environment["PI_CODING_AGENT_DIR"] = piHome.path
        environment["OPENMUSE_API_KEY"] = apiKey
        process.environment = environment
        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
        do { try process.run() }
        catch { throw ModelRuntimeError.piFailed("无法启动 Pi：\(error.localizedDescription)") }

        let outputLock = NSLock()
        var pending = Data()
        var finalText: String?
        var rpcError: String?
        var settled = false
        var stderrData = Data()
        let completion = DispatchSemaphore(value: 0)
        let stderrReadComplete = DispatchSemaphore(value: 0)
        let stdoutHandle = stdout.fileHandleForReading
        stdoutHandle.readabilityHandler = { handle in
            let chunk = handle.availableData
            outputLock.lock()
            defer { outputLock.unlock() }
            if chunk.isEmpty {
                if !settled { settled = true; completion.signal() }
                return
            }
            pending.append(chunk)
            while let newline = pending.firstIndex(of: 10) {
                let line = Data(pending[..<newline])
                pending.removeSubrange(...newline)
                guard let record = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
                if record["type"] as? String == "response",
                   record["command"] as? String == "prompt",
                   record["success"] as? Bool == false {
                    rpcError = record["error"] as? String ?? "Pi 没有接受这条消息。"
                }
                if record["type"] as? String == "message_end",
                   let message = record["message"] as? [String: Any],
                   message["role"] as? String == "assistant" {
                    if message["stopReason"] as? String == "error" {
                        rpcError = message["errorMessage"] as? String ?? "Pi 返回模型错误。"
                        finalText = nil
                    } else if let content = message["content"] as? String {
                        finalText = content
                    } else if let blocks = message["content"] as? [[String: Any]] {
                        let combined = blocks.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }.joined()
                        if !combined.isEmpty { finalText = combined; rpcError = nil }
                    }
                }
                if record["type"] as? String == "agent_settled", !settled {
                    settled = true
                    completion.signal()
                }
            }
        }
        DispatchQueue.global(qos: .utility).async {
            let data = stderr.fileHandleForReading.readDataToEndOfFile()
            outputLock.lock(); stderrData = data; outputLock.unlock()
            stderrReadComplete.signal()
        }
        do { try stdin.fileHandleForWriting.write(contentsOf: input) }
        catch {
            process.terminate()
            try? stdin.fileHandleForWriting.close()
            process.waitUntilExit()
            stdoutHandle.readabilityHandler = nil
            _ = stderrReadComplete.wait(timeout: .now() + 2)
            throw ModelRuntimeError.piFailed("无法向 Pi 发送请求。")
        }

        let waitResult = completion.wait(timeout: .now() + 125)
        if waitResult == .timedOut { process.terminate() }
        try? stdin.fileHandleForWriting.close()
        process.waitUntilExit()
        _ = stderrReadComplete.wait(timeout: .now() + 2)
        stdoutHandle.readabilityHandler = nil
        outputLock.lock()
        let answer = finalText
        let failure = rpcError
        let diagnostics = stderrData
        outputLock.unlock()

        if waitResult == .timedOut { throw ModelRuntimeError.piFailed("等待模型回复超时；任务状态已保留，可重试。") }
        if let answer, !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return answer }
        if let failure, !failure.isEmpty {
            let safeDetail = failure.replacingOccurrences(of: apiKey, with: "[已隐藏]")
            throw ModelRuntimeError.piFailed("Pi 调用失败：\(safeDetail.prefix(600))")
        }
        if process.terminationStatus != 0 {
            let detail = String(data: diagnostics, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let safeDetail = detail.replacingOccurrences(of: apiKey, with: "[已隐藏]")
            throw ModelRuntimeError.piFailed(safeDetail.isEmpty ? "Pi 调用失败（退出码 \(process.terminationStatus)）。请检查模型设置。" : "Pi 调用失败：\(safeDetail.prefix(600))")
        }
        throw ModelRuntimeError.emptyResponse
    }

    private static func piExecutable() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            URL(fileURLWithPath: "/opt/homebrew/bin/pi"),
            URL(fileURLWithPath: "/usr/local/bin/pi"),
            home.appendingPathComponent(".npm-global/bin/pi"),
            URL(fileURLWithPath: "/usr/bin/pi")
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
}
#endif
