#if os(macOS)
import Combine
import Foundation
import Network
import Security

public struct BridgePairedDevice: Codable, Identifiable, Equatable {
    public var id: String
    public var name: String
    public var pairedAt: Date

    fileprivate init(id: String, name: String, pairedAt: Date) {
        self.id = id
        self.name = name
        self.pairedAt = pairedAt
    }
}

private struct BridgeHealth: Codable {
    var device: String
    var protocolVersion: Int
}

private struct BridgeErrorBody: Codable {
    var message: String
}

@MainActor
public final class MacBridgeServer: ObservableObject {
    @Published public private(set) var isRunning = false
    @Published public private(set) var pairingCode = ""
    @Published public private(set) var pairingCodeExpiresAt = Date.distantPast
    @Published public private(set) var status = "正在启动本机服务…"
    @Published public private(set) var deviceAddress: String?
    @Published public private(set) var pairedDevices: [BridgePairedDevice]
    @Published public private(set) var localPort: UInt16?
    @Published public private(set) var privateRouteEnabled: Bool
    @Published public private(set) var privateRouteStatus: String

    private let requestedPort: UInt16
    private let storageScope: String
    private let queue = DispatchQueue(label: "org.openmuse.bridge", qos: .userInitiated)
    private var listener: NWListener?
    private var handler: (@Sendable (BridgeChatRequest) async throws -> String)?
    private var pairingAttempts = 0
    private var isPairingCodeConsumed = false

    public init(port: UInt16 = 4388, storageScope: String = "default") {
        requestedPort = port
        self.storageScope = storageScope
        let route = port == 0 ? TailscaleBridgeAddress.State.empty : TailscaleBridgeAddress.inspect(localPort: port)
        deviceAddress = route.address
        privateRouteEnabled = route.enabled
        privateRouteStatus = route.status
        pairedDevices = Self.loadDevices(scope: storageScope)
        rotatePairingCode()
    }

    public func rotatePairingCode() {
        pairingCode = Self.randomCode()
        pairingCodeExpiresAt = .now.addingTimeInterval(5 * 60)
        pairingAttempts = 0
        isPairingCodeConsumed = false
    }

    public func start(handler: @escaping @Sendable (BridgeChatRequest) async throws -> String) {
        guard listener == nil else { return }
        self.handler = handler
        do {
            let port = requestedPort == 0 ? NWEndpoint.Port.any : NWEndpoint.Port(rawValue: requestedPort)!
            let parameters = NWParameters.tcp
            parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(IPv4Address("127.0.0.1")!), port: .any)
            let listener = try NWListener(using: parameters, on: port)
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    guard let self else { return }
                    switch state {
                    case .ready:
                        self.isRunning = true
                        self.localPort = listener.port?.rawValue
                        self.status = "本机服务已启动；只有配对设备可以提交任务。"
                    case .failed(let error):
                        self.isRunning = false
                        self.status = "本机服务启动失败：\(error.localizedDescription)"
                    case .cancelled:
                        self.isRunning = false
                        self.status = "本机服务已停止。"
                    default: break
                    }
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in
                    guard let self else { connection.cancel(); return }
                    self.receive(connection, buffer: Data())
                }
            }
            self.listener = listener
            listener.start(queue: queue)
        } catch {
            status = "本机服务启动失败：\(error.localizedDescription)"
        }
    }

    public func stop() {
        listener?.cancel()
        listener = nil
    }

    public func revokeDevice(id: String) {
        do { try SecureStore.deleteBridgeDeviceToken(id: id, scope: storageScope) }
        catch { status = "撤销设备失败：\(error.localizedDescription)"; return }
        pairedDevices.removeAll { $0.id == id }
        persistDevices()
    }

    public func enablePrivateLink() {
        do {
            let state = try TailscaleBridgeAddress.enablePrivateRoute(localPort: requestedPort)
            deviceAddress = state.address
            privateRouteEnabled = state.enabled
            privateRouteStatus = state.status
        } catch {
            privateRouteEnabled = false
            privateRouteStatus = error.localizedDescription
        }
    }

    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.start(queue: queue)
        readNext(connection, buffer: buffer)
    }

    private func readNext(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, complete, error in
            Task { @MainActor in
                guard let self else { connection.cancel(); return }
                if let error { self.respond(connection, status: 400, body: BridgeErrorBody(message: "Invalid request: \(error.localizedDescription)")); return }
                var received = buffer
                if let data { received.append(data) }
                guard received.count <= 300_000 else {
                    self.respond(connection, status: 413, body: BridgeErrorBody(message: "Request is too large."))
                    return
                }
                switch Self.parseRequest(received) {
                case .complete(let request): self.handle(request, connection: connection)
                case .invalid:
                    self.respond(connection, status: 400, body: BridgeErrorBody(message: "Malformed HTTP request."))
                case .incomplete:
                    if complete { self.respond(connection, status: 400, body: BridgeErrorBody(message: "Incomplete request.")) }
                    else { self.readNext(connection, buffer: received) }
                }
            }
        }
    }

    private func handle(_ request: ParsedHTTPRequest, connection: NWConnection) {
        if request.method == "GET", request.path.hasSuffix("/health") {
            respond(connection, status: 200, body: BridgeHealth(device: "OpenMuse Mac", protocolVersion: 1))
            return
        }
        guard request.method == "POST" else {
            respond(connection, status: 405, body: BridgeErrorBody(message: "Method not allowed.")); return
        }
        if request.path.hasSuffix("/v1/pair") {
            pair(request, connection: connection)
            return
        }
        guard request.path.hasSuffix("/v1/chat") else {
            respond(connection, status: 404, body: BridgeErrorBody(message: "Route not found.")); return
        }
        guard authenticated(request.headers["authorization"]) else {
            respond(connection, status: 401, body: BridgeErrorBody(message: "Pair this device before using the Mac.")); return
        }
        guard let payload = try? JSONDecoder().decode(BridgeChatRequest.self, from: request.body), payload.isWithinLimits else {
            respond(connection, status: 413, body: BridgeErrorBody(message: "Chat request is invalid or too large.")); return
        }
        guard let handler else {
            respond(connection, status: 503, body: BridgeErrorBody(message: "The OpenMuse model is not ready on this Mac.")); return
        }
        Task {
            do {
                let answer = try await handler(payload)
                self.respond(connection, status: 200, body: BridgeChatResponse(requestID: payload.requestID, answer: answer))
            } catch {
                self.respond(connection, status: 502, body: BridgeErrorBody(message: String(error.localizedDescription.prefix(500))))
            }
        }
    }

    private func pair(_ request: ParsedHTTPRequest, connection: NWConnection) {
        guard Date.now < pairingCodeExpiresAt, !isPairingCodeConsumed, pairingAttempts < 5 else {
            respond(connection, status: 429, body: BridgeErrorBody(message: "Pairing code expired. Generate a new code on the Mac.")); return
        }
        guard let payload = try? JSONDecoder().decode(BridgePairRequest.self, from: request.body) else {
            respond(connection, status: 400, body: BridgeErrorBody(message: "Pairing request is invalid.")); return
        }
        pairingAttempts += 1
        guard Self.constantTimeEqual(payload.code.uppercased(), pairingCode) else {
            respond(connection, status: 401, body: BridgeErrorBody(message: "Pairing code does not match.")); return
        }
        let id = UUID().uuidString
        let token = Self.randomToken()
        do {
            try SecureStore.saveBridgeDeviceToken(token, id: id, scope: storageScope)
            pairedDevices.append(BridgePairedDevice(id: id, name: String(payload.deviceName.prefix(80)), pairedAt: .now))
            persistDevices()
            isPairingCodeConsumed = true
            respond(connection, status: 200, body: BridgePairResponse(deviceID: id, token: token))
        } catch {
            respond(connection, status: 500, body: BridgeErrorBody(message: "The paired-device token could not be saved."))
        }
    }

    private func authenticated(_ authorization: String?) -> Bool {
        guard let authorization, authorization.hasPrefix("Bearer ") else { return false }
        let supplied = String(authorization.dropFirst(7))
        return pairedDevices.contains { device in
            guard let token = SecureStore.readBridgeDeviceToken(id: device.id, scope: storageScope) else { return false }
            return Self.constantTimeEqual(token, supplied)
        }
    }

    private func respond<T: Encodable>(_ connection: NWConnection, status: Int, body: T) {
        let data = (try? JSONEncoder().encode(body)) ?? Data("{}".utf8)
        let reason = Self.reasonPhrase(status)
        var response = Data("HTTP/1.1 \(status) \(reason)\r\nContent-Type: application/json; charset=utf-8\r\nContent-Length: \(data.count)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n".utf8)
        response.append(data)
        connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
    }

    private func persistDevices() {
        guard let data = try? JSONEncoder().encode(pairedDevices) else { return }
        UserDefaults.standard.set(data, forKey: "openmuse.bridge.devices.\(storageScope)")
    }

    private static func loadDevices(scope: String) -> [BridgePairedDevice] {
        guard let data = UserDefaults.standard.data(forKey: "openmuse.bridge.devices.\(scope)") else { return [] }
        return (try? JSONDecoder().decode([BridgePairedDevice].self, from: data)) ?? []
    }

    private static func randomCode() -> String {
        String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8))
    }

    private static func randomToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let result = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard result == errSecSuccess else { return UUID().uuidString + UUID().uuidString }
        return Data(bytes).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    private static func constantTimeEqual(_ lhs: String, _ rhs: String) -> Bool {
        let a = Array(lhs.utf8), b = Array(rhs.utf8)
        guard a.count == b.count else { return false }
        return zip(a, b).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }

    private static func reasonPhrase(_ status: Int) -> String {
        switch status {
        case 200: "OK"
        case 400: "Bad Request"
        case 401: "Unauthorized"
        case 404: "Not Found"
        case 405: "Method Not Allowed"
        case 413: "Payload Too Large"
        case 429: "Too Many Requests"
        case 500: "Internal Server Error"
        default: "Bad Gateway"
        }
    }

    private enum ParseResult {
        case incomplete
        case invalid
        case complete(ParsedHTTPRequest)
    }

    private static func parseRequest(_ data: Data) -> ParseResult {
        guard let boundary = data.range(of: Data("\r\n\r\n".utf8)) else { return .incomplete }
        guard let headerText = String(data: data[..<boundary.lowerBound], encoding: .utf8) else { return .invalid }
        let lines = headerText.components(separatedBy: "\r\n")
        guard let first = lines.first else { return .invalid }
        let parts = first.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count == 3, parts[2].hasPrefix("HTTP/1.") else { return .invalid }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { return .invalid }
            headers[String(line[..<colon]).lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        let length = Int(headers["content-length"] ?? "0") ?? -1
        guard length >= 0, length <= 256_000 else { return .invalid }
        let bodyStart = boundary.upperBound
        guard data.count >= bodyStart + length else { return .incomplete }
        let target = String(parts[1])
        let path = URLComponents(string: target)?.path ?? target
        let body = data[bodyStart..<(bodyStart + length)]
        return .complete(ParsedHTTPRequest(method: String(parts[0]), path: path, headers: headers, body: Data(body)))
    }
}

private struct ParsedHTTPRequest {
    var method: String
    var path: String
    var headers: [String: String]
    var body: Data
}

private enum TailscaleBridgeAddress {
    struct State {
        var address: String?
        var enabled: Bool
        var status: String

        static let empty = State(address: nil, enabled: false, status: "尚未设置 Tailscale 私有通道。")
    }

    private static let servicePort: UInt16 = 8443
    private static let servicePath = "/openmuse"

    static func inspect(localPort: UInt16) -> State {
        guard let executable = tailscaleExecutable(), let statusData = run(executable, ["status", "--json"]),
              let root = try? JSONSerialization.jsonObject(with: statusData) as? [String: Any],
              let selfRecord = root["Self"] as? [String: Any],
              let dns = selfRecord["DNSName"] as? String, !dns.isEmpty else {
            return State(address: nil, enabled: false, status: "没有找到已连接的 Tailscale。")
        }
        let host = dns.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        let address = "https://\(host):\(servicePort)\(servicePath)"
        guard let serveData = run(executable, ["serve", "status", "--json"]),
              let configuration = try? JSONSerialization.jsonObject(with: serveData) as? [String: Any] else {
            return State(address: address, enabled: false, status: "Tailscale 已连接；私有通道尚未启用。")
        }
        if matches(configuration, host: host, localPort: localPort) {
            return State(address: address, enabled: true, status: "Tailscale 私有通道已启用，仅在 tailnet 内可访问。")
        }
        let tcp = configuration["TCP"] as? [String: Any] ?? [:]
        if tcp[String(servicePort)] != nil {
            return State(address: address, enabled: false, status: "8443 端口已有其他服务配置；OpenMuse 没有覆盖它。")
        }
        return State(address: address, enabled: false, status: "Tailscale 已连接；点击启用独立私有通道。")
    }

    static func enablePrivateRoute(localPort: UInt16) throws -> State {
        guard let executable = tailscaleExecutable(), let statusData = run(executable, ["status", "--json"]),
              let status = try? JSONSerialization.jsonObject(with: statusData) as? [String: Any],
              let selfRecord = status["Self"] as? [String: Any],
              selfRecord["BackendState"] as? String == "Running",
              let dns = selfRecord["DNSName"] as? String, !dns.isEmpty else {
            throw MacBridgeError.rejected("先在这台 Mac 上登录并连接 Tailscale，再启用私有通道。")
        }
        let host = dns.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard let beforeData = run(executable, ["serve", "status", "--json"]),
              let before = try? JSONSerialization.jsonObject(with: beforeData) as? [String: Any] else {
            throw MacBridgeError.rejected("无法读取现有 Tailscale Serve 设置；为避免覆盖其他路由，OpenMuse 没有修改配置。")
        }
        if matches(before, host: host, localPort: localPort) {
            return State(address: "https://\(host):\(servicePort)\(servicePath)", enabled: true, status: "Tailscale 私有通道已启用，仅在 tailnet 内可访问。")
        }
        let tcp = before["TCP"] as? [String: Any] ?? [:]
        let web = before["Web"] as? [String: Any] ?? [:]
        let usesWebPort = web.keys.contains { $0.hasSuffix(":\(servicePort)") }
        let funnel = before["AllowFunnel"] as? [String: Any] ?? [:]
        guard tcp[String(servicePort)] == nil, !usesWebPort, funnel["\(host):\(servicePort)"] == nil else {
            throw MacBridgeError.rejected("8443 端口已有其他服务配置；OpenMuse 保留了现有设置。")
        }
        guard run(executable, ["serve", "--bg", "--https=\(servicePort)", "--set-path=\(servicePath)", "http://127.0.0.1:\(localPort)"]) != nil else {
            throw MacBridgeError.rejected("Tailscale 没有启用私有通道。请检查 HTTPS 证书是否已在 tailnet 中开启。")
        }
        guard let afterData = run(executable, ["serve", "status", "--json"]),
              let after = try? JSONSerialization.jsonObject(with: afterData) as? [String: Any],
              matches(after, host: host, localPort: localPort),
              preservesOtherPorts(before: before, after: after) else {
            throw MacBridgeError.rejected("无法确认 OpenMuse 私有通道已启用，或检测到其他 Serve 路由发生变化；请检查 Tailscale 设置。")
        }
        return State(address: "https://\(host):\(servicePort)\(servicePath)", enabled: true, status: "Tailscale 私有通道已启用，仅在 tailnet 内可访问。")
    }

    private static func matches(_ configuration: [String: Any], host: String, localPort: UInt16) -> Bool {
        let key = "\(host):\(servicePort)"
        let web = configuration["Web"] as? [String: Any] ?? [:]
        let hostConfiguration = web[key] as? [String: Any] ?? [:]
        let handlers = hostConfiguration["Handlers"] as? [String: Any] ?? [:]
        let route = handlers[servicePath] as? [String: Any]
        let proxy = route?["Proxy"] as? String
        let funnel = configuration["AllowFunnel"] as? [String: Any] ?? [:]
        return proxy == "http://127.0.0.1:\(localPort)" && funnel[key] as? Bool != true
    }

    private static func preservesOtherPorts(before: [String: Any], after: [String: Any]) -> Bool {
        func filtered(_ value: [String: Any]) -> [String: Any] {
            var result = value
            if var tcp = result["TCP"] as? [String: Any] {
                tcp.removeValue(forKey: String(servicePort))
                if tcp.isEmpty { result.removeValue(forKey: "TCP") } else { result["TCP"] = tcp }
            }
            if var web = result["Web"] as? [String: Any] {
                web = web.filter { !$0.key.hasSuffix(":\(servicePort)") }
                if web.isEmpty { result.removeValue(forKey: "Web") } else { result["Web"] = web }
            }
            if var funnel = result["AllowFunnel"] as? [String: Any] {
                funnel = funnel.filter { !$0.key.hasSuffix(":\(servicePort)") }
                if funnel.isEmpty { result.removeValue(forKey: "AllowFunnel") } else { result["AllowFunnel"] = funnel }
            }
            return result
        }
        guard let old = try? JSONSerialization.data(withJSONObject: filtered(before), options: [.sortedKeys]),
              let new = try? JSONSerialization.data(withJSONObject: filtered(after), options: [.sortedKeys]) else { return false }
        return old == new
    }

    private static func tailscaleExecutable() -> String? {
        ["/usr/local/bin/tailscale", "/opt/homebrew/bin/tailscale"].first(where: FileManager.default.isExecutableFile(atPath:))
    }

    @discardableResult
    private static func run(_ executable: String, _ arguments: [String]) -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        let errors = Pipe()
        process.standardError = errors
        do { try process.run() } catch { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        _ = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return process.terminationStatus == 0 ? data : nil
    }
}
#endif
