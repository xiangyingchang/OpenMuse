import Foundation

public struct BridgePairRequest: Codable, Sendable {
    public var code: String
    public var deviceName: String

    public init(code: String, deviceName: String) {
        self.code = code
        self.deviceName = deviceName
    }
}

public struct BridgePairResponse: Codable, Sendable {
    public var deviceID: String
    public var token: String
}

public struct BridgeChatRequest: Codable, Sendable {
    public var requestID: String
    public var systemPrompt: String
    public var messages: [TranscriptMessage]

    public init(requestID: String = UUID().uuidString, systemPrompt: String, messages: [TranscriptMessage]) {
        self.requestID = requestID
        self.systemPrompt = systemPrompt
        self.messages = messages
    }

    public var isWithinLimits: Bool {
        requestID.count <= 100 && systemPrompt.utf8.count <= 32_000 && messages.count <= 40 &&
        messages.allSatisfy { ["user", "assistant"].contains($0.role) && $0.content.utf8.count <= 32_000 } &&
        messages.reduce(systemPrompt.utf8.count) { $0 + $1.content.utf8.count } <= 256_000
    }
}

public struct BridgeChatResponse: Codable, Sendable {
    public var requestID: String
    public var answer: String

    public init(requestID: String, answer: String) {
        self.requestID = requestID
        self.answer = answer
    }
}

public enum MacBridgeError: Error, LocalizedError {
    case invalidAddress
    case invalidResponse
    case rejected(String)
    case unavailable

    public var errorDescription: String? {
        switch self {
        case .invalidAddress: "Mac 地址无效。请填写 Tailscale HTTPS 地址。"
        case .invalidResponse: "Mac 返回了无法读取的结果。"
        case .rejected(let message): message
        case .unavailable: "家里的 Mac 暂时没有响应。确认 Mac 已开机、OpenMuse 正在运行，并且两台设备都已连接 Tailscale。"
        }
    }
}

public enum MacBridgeClient {
    private static let directSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.connectionProxyDictionary = [:]
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }()

    public static func pair(address: String, code: String, session: URLSession? = nil) async throws -> (endpoint: String, token: String) {
        guard let base = baseURL(address) else { throw MacBridgeError.invalidAddress }
        let requestBody = BridgePairRequest(code: code.trimmingCharacters(in: .whitespacesAndNewlines), deviceName: deviceName)
        let data = try JSONEncoder().encode(requestBody)
        let responseData = try await send(path: "v1/pair", base: base, body: data, token: nil, session: session ?? directSession)
        let response = try JSONDecoder().decode(BridgePairResponse.self, from: responseData)
        return (base.absoluteString, response.token)
    }

    public static func reply(address: String, token: String, request: BridgeChatRequest, session: URLSession? = nil) async throws -> String {
        guard request.isWithinLimits, let base = baseURL(address) else { throw MacBridgeError.invalidAddress }
        let data = try await send(path: "v1/chat", base: base, body: try JSONEncoder().encode(request), token: token, session: session ?? directSession)
        let response = try JSONDecoder().decode(BridgeChatResponse.self, from: data)
        guard response.requestID == request.requestID, !response.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MacBridgeError.invalidResponse
        }
        return response.answer
    }

    public static func check(address: String, session: URLSession? = nil) async throws -> String {
        guard let base = baseURL(address) else { throw MacBridgeError.invalidAddress }
        let url = base.appendingPathComponent("health")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 8
        let (data, response) = try await (session ?? directSession).data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw MacBridgeError.unavailable }
        guard let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let deviceName = value["device"] as? String, !deviceName.isEmpty else { throw MacBridgeError.invalidResponse }
        return deviceName
    }

    private static func send(path: String, base: URL, body: Data, token: String?, session: URLSession) async throws -> Data {
        var request = URLRequest(url: base.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        request.httpBody = body
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw MacBridgeError.invalidResponse }
            guard (200..<300).contains(http.statusCode) else {
                let error = (try? JSONDecoder().decode(BridgeErrorResponse.self, from: data))?.message
                if http.statusCode == 401 { throw MacBridgeError.rejected("设备未配对或授权已撤销。请重新配对。") }
                throw MacBridgeError.rejected(error ?? "Mac 请求失败（HTTP \(http.statusCode)）。")
            }
            return data
        } catch let error as MacBridgeError {
            throw error
        } catch {
            throw MacBridgeError.unavailable
        }
    }

    static func baseURL(_ address: String) -> URL? {
        var raw = address.trimmingCharacters(in: .whitespacesAndNewlines)
        while raw.hasSuffix("/") { raw.removeLast() }
        guard var components = URLComponents(string: raw),
              let scheme = components.scheme?.lowercased(),
              let host = components.host?.lowercased(),
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil,
              (scheme == "https" && host.hasSuffix(".ts.net")) ||
                (scheme == "http" && ["localhost", "127.0.0.1", "::1"].contains(host)) else { return nil }
        let path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = path.isEmpty ? "" : "/\(path)"
        return components.url
    }

    private static var deviceName: String {
        #if os(iOS)
        return "iPhone"
        #else
        return Host.current().localizedName ?? "Mac"
        #endif
    }
}

private struct BridgeErrorResponse: Decodable {
    var message: String
}
