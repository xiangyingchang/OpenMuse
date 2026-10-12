#if os(macOS)
import Combine
import Foundation
import Network
import Security

public struct BridgePairedDevice: Codable, Identifiable, Equatable {
    public var id: String
    public var name: String
    public var syncDeviceID: String?
    public var pairedAt: Date

    fileprivate init(id: String, name: String, syncDeviceID: String?, pairedAt: Date) {
        self.id = id
        self.name = name
        self.syncDeviceID = syncDeviceID
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
    private var handler: (@Sendable (BridgeChatRequest) async throws -> BridgeChatResult)?
    private var syncHandler: ((DeviceSyncRequest, String) throws -> DeviceSyncResponse)?
    private var attachmentHandler: ((String, String, Data) throws -> BridgeAttachmentPayload)?
    private struct ActiveChatRequest {
        var pairedDeviceID: String
        var task: Task<Void, Never>
        var heartbeatTask: Task<Void, Never>?
        var events: [BridgeSequencedToolEvent] = []
        var nextSequence = 1
        var heartbeatAt = Date()
        var responseText = ""
    }
    private struct PendingChatCancellation {
        var pairedDeviceID: String
        var expiresAt: Date
    }
    private var activeChatRequests: [String: ActiveChatRequest] = [:]
    private var pendingChatCancellations: [String: PendingChatCancellation] = [:]
    private var workspaceID: String?
    private var ownerDeviceID: String?
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

    public func start(workspaceID: String? = nil, ownerDeviceID: String? = nil, syncHandler: ((DeviceSyncRequest, String) throws -> DeviceSyncResponse)? = nil, attachmentHandler: ((String, String, Data) throws -> BridgeAttachmentPayload)? = nil, handler: @escaping @Sendable (BridgeChatRequest) async throws -> BridgeChatResult) {
        guard listener == nil else { return }
        self.handler = handler
        self.syncHandler = syncHandler
        self.attachmentHandler = attachmentHandler
        self.workspaceID = workspaceID
        self.ownerDeviceID = ownerDeviceID
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
        activeChatRequests.values.forEach {
            $0.task.cancel()
            $0.heartbeatTask?.cancel()
        }
        activeChatRequests.removeAll()
        pendingChatCancellations.removeAll()
        listener?.cancel()
        listener = nil
    }

    public func publishChatToolEvent(requestID: String, event: ModelToolExecutionEvent) {
        guard BridgeChatResponse.isAllowedToolEvent(event),
              var active = activeChatRequests[requestID], active.events.count < 128 else { return }
        active.events.append(BridgeSequencedToolEvent(sequence: active.nextSequence, event: event))
        active.nextSequence += 1
        active.heartbeatAt = .now
        activeChatRequests[requestID] = active
    }

    public func publishChatTextDelta(requestID: String, text: String) {
        guard !text.isEmpty, var active = activeChatRequests[requestID],
              active.responseText.utf8.count + text.utf8.count <= 256_000 else { return }
        active.responseText += text
        active.heartbeatAt = .now
        activeChatRequests[requestID] = active
    }

    public func revokeDevice(id: String) {
        do { try SecureStore.deleteBridgeDeviceToken(id: id, scope: storageScope) }
        catch { status = "撤销设备失败：\(error.localizedDescription)"; return }
        let requestIDs = activeChatRequests.filter { $0.value.pairedDeviceID == id }.map(\.key)
        for requestID in requestIDs {
            activeChatRequests[requestID]?.task.cancel()
            activeChatRequests[requestID]?.heartbeatTask?.cancel()
            activeChatRequests.removeValue(forKey: requestID)
        }
        pendingChatCancellations = pendingChatCancellations.filter { $0.value.pairedDeviceID != id }
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
                guard received.count <= AttachmentStore.maximumFileBytes + 64 * 1024 else {
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
        if let attachmentID = Self.attachmentID(from: request.path) {
            attachment(request, attachmentID: attachmentID, connection: connection)
            return
        }
        guard request.method == "POST" else {
            respond(connection, status: 405, body: BridgeErrorBody(message: "Method not allowed.")); return
        }
        if request.path.hasSuffix("/v1/pair") {
            pair(request, connection: connection)
            return
        }
        if request.path.hasSuffix("/v1/sync") {
            sync(request, connection: connection)
            return
        }
        if request.path.hasSuffix("/v1/chat-events") {
            chatEvents(request, connection: connection)
            return
        }
        if request.path.hasSuffix("/v1/cancel") {
            cancelChat(request, connection: connection)
            return
        }
        guard request.path.hasSuffix("/v1/chat") else {
            respond(connection, status: 404, body: BridgeErrorBody(message: "Route not found.")); return
        }
        guard let device = authenticatedDevice(request.headers["authorization"]) else {
            respond(connection, status: 401, body: BridgeErrorBody(message: "Pair this device before using the Mac.")); return
        }
        guard let payload = try? JSONDecoder().decode(BridgeChatRequest.self, from: request.body), payload.isWithinLimits else {
            respond(connection, status: 413, body: BridgeErrorBody(message: "Chat request is invalid or too large.")); return
        }
        if payload.executionTaskID != nil {
            guard ownerDeviceID != nil else {
                respond(connection, status: 503, body: BridgeErrorBody(message: "Task handoff is not enabled on this Mac.")); return
            }
            guard payload.returnOwnerDeviceID == device.syncDeviceID else {
                respond(connection, status: 403, body: BridgeErrorBody(message: "The task return owner does not match this paired device.")); return
            }
        }
        pendingChatCancellations = pendingChatCancellations.filter { $0.value.expiresAt > .now }
        if let cancellation = pendingChatCancellations[payload.requestID], cancellation.pairedDeviceID == device.id {
            pendingChatCancellations.removeValue(forKey: payload.requestID)
            respond(connection, status: 499, body: BridgeErrorBody(message: "This chat request was cancelled before it started."))
            return
        }
        guard activeChatRequests[payload.requestID] == nil else {
            respond(connection, status: 409, body: BridgeErrorBody(message: "A chat request with this ID is already active.")); return
        }
        guard activeChatRequests.count < 4 else {
            respond(connection, status: 429, body: BridgeErrorBody(message: "The Mac is already running its maximum number of chat requests.")); return
        }
        guard let handler else {
            respond(connection, status: 503, body: BridgeErrorBody(message: "The OpenMuse model is not ready on this Mac.")); return
        }
        let requestID = payload.requestID
        let heartbeatTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: 5_000_000_000) }
                catch { return }
                guard !Task.isCancelled else { return }
                self?.refreshChatHeartbeat(requestID: requestID)
            }
        }
        let activeTask = Task { @MainActor [weak self] in
            guard let self else { connection.cancel(); return }
            defer {
                heartbeatTask.cancel()
                self.activeChatRequests.removeValue(forKey: requestID)
            }
            do {
                let result = try await handler(payload)
                try Task.checkCancellation()
                let response = BridgeChatResponse(requestID: payload.requestID, answer: result.answer, toolEvents: result.toolEvents)
                guard response.isWithinLimits else {
                    self.respond(connection, status: 502, body: BridgeErrorBody(message: "The Mac returned an invalid task result."))
                    return
                }
                self.respond(connection, status: 200, body: response)
            } catch is CancellationError {
                self.respond(connection, status: 499, body: BridgeErrorBody(message: "This chat request was cancelled."))
            } catch {
                self.respond(connection, status: 502, body: BridgeErrorBody(message: String(error.localizedDescription.prefix(500))))
            }
        }
        activeChatRequests[requestID] = ActiveChatRequest(pairedDeviceID: device.id, task: activeTask, heartbeatTask: heartbeatTask)
    }

    private func chatEvents(_ request: ParsedHTTPRequest, connection: NWConnection) {
        guard let device = authenticatedDevice(request.headers["authorization"]) else {
            respond(connection, status: 401, body: BridgeErrorBody(message: "Pair this device before reading task activity.")); return
        }
        guard let payload = try? JSONDecoder().decode(BridgeChatEventsRequest.self, from: request.body), payload.isWithinLimits else {
            respond(connection, status: 400, body: BridgeErrorBody(message: "Task activity request is invalid.")); return
        }
        guard let active = activeChatRequests[payload.requestID], active.pairedDeviceID == device.id else {
            respond(connection, status: 200, body: BridgeChatEventsResponse(
                requestID: payload.requestID,
                events: [],
                nextSequence: payload.afterSequence,
                isActive: false,
                heartbeatAt: nil,
                nextTextCharacterOffset: payload.afterTextCharacterOffset
            ))
            return
        }
        guard payload.afterTextCharacterOffset <= active.responseText.count else {
            respond(connection, status: 400, body: BridgeErrorBody(message: "Task text cursor is invalid.")); return
        }
        let events = active.events.filter { $0.sequence > payload.afterSequence }.prefix(8)
        let remainingText = String(active.responseText.dropFirst(payload.afterTextCharacterOffset))
        var textDelta = ""
        var textDeltaBytes = 0
        for character in remainingText {
            let characterBytes = String(character).utf8.count
            guard textDeltaBytes + characterBytes <= 64 * 1024 else { break }
            textDelta.append(character)
            textDeltaBytes += characterBytes
        }
        let response = BridgeChatEventsResponse(
            requestID: payload.requestID,
            events: Array(events),
            nextSequence: active.nextSequence - 1,
            isActive: true,
            heartbeatAt: active.heartbeatAt,
            textDelta: textDelta,
            nextTextCharacterOffset: payload.afterTextCharacterOffset + textDelta.count
        )
        guard response.isWithinLimits else {
            respond(connection, status: 502, body: BridgeErrorBody(message: "The Mac could not safely return task activity.")); return
        }
        respond(connection, status: 200, body: response)
    }

    private func refreshChatHeartbeat(requestID: String) {
        guard var active = activeChatRequests[requestID] else { return }
        active.heartbeatAt = .now
        activeChatRequests[requestID] = active
    }

    private func cancelChat(_ request: ParsedHTTPRequest, connection: NWConnection) {
        guard let device = authenticatedDevice(request.headers["authorization"]) else {
            respond(connection, status: 401, body: BridgeErrorBody(message: "Pair this device before cancelling a Mac request.")); return
        }
        guard let payload = try? JSONDecoder().decode(BridgeCancelRequest.self, from: request.body),
              !payload.requestID.isEmpty, payload.requestID.count <= 100 else {
            respond(connection, status: 400, body: BridgeErrorBody(message: "Cancellation request is invalid.")); return
        }
        if let active = activeChatRequests[payload.requestID] {
            let cancelled = active.pairedDeviceID == device.id
            if cancelled {
                active.task.cancel()
            }
            respond(connection, status: 200, body: BridgeCancelResponse(requestID: payload.requestID, cancelled: cancelled))
            return
        }
        // The cancellation call can reach the Mac just before the chat request on a
        // separate connection. Keep a short, device-scoped intent so the Pi task
        // cannot start after the user has already stopped waiting.
        pendingChatCancellations[payload.requestID] = PendingChatCancellation(
            pairedDeviceID: device.id,
            expiresAt: .now.addingTimeInterval(30)
        )
        guard pendingChatCancellations.count <= 128 else {
            pendingChatCancellations.removeValue(forKey: payload.requestID)
            respond(connection, status: 429, body: BridgeErrorBody(message: "Too many pending cancellation requests."))
            return
        }
        respond(connection, status: 200, body: BridgeCancelResponse(requestID: payload.requestID, cancelled: true))
    }

    private func pair(_ request: ParsedHTTPRequest, connection: NWConnection) {
        guard Date.now < pairingCodeExpiresAt, !isPairingCodeConsumed, pairingAttempts < 5 else {
            respond(connection, status: 429, body: BridgeErrorBody(message: "Pairing code expired. Generate a new code on the Mac.")); return
        }
        guard let payload = try? JSONDecoder().decode(BridgePairRequest.self, from: request.body),
              payload.deviceID == nil || !(payload.deviceID?.isEmpty ?? true) && (payload.deviceID?.count ?? 0) <= 100 else {
            respond(connection, status: 400, body: BridgeErrorBody(message: "Pairing request is invalid.")); return
        }
        pairingAttempts += 1
        guard Self.constantTimeEqual(payload.code.uppercased(), pairingCode) else {
            respond(connection, status: 401, body: BridgeErrorBody(message: "Pairing code does not match.")); return
        }
        let id = UUID().uuidString
        let token = Self.randomToken()
        let syncDeviceID = payload.deviceID ?? UUID().uuidString
        do {
            try SecureStore.saveBridgeDeviceToken(token, id: id, scope: storageScope)
            pairedDevices.append(BridgePairedDevice(id: id, name: String(payload.deviceName.prefix(80)), syncDeviceID: syncDeviceID, pairedAt: .now))
            persistDevices()
            isPairingCodeConsumed = true
            respond(connection, status: 200, body: BridgePairResponse(deviceID: id, token: token, workspaceID: workspaceID, hostDeviceID: ownerDeviceID))
        } catch {
            respond(connection, status: 500, body: BridgeErrorBody(message: "The paired-device token could not be saved."))
        }
    }

    private func authenticated(_ authorization: String?) -> Bool {
        authenticatedDevice(authorization) != nil
    }

    private func authenticatedDevice(_ authorization: String?) -> BridgePairedDevice? {
        guard let authorization, authorization.hasPrefix("Bearer ") else { return nil }
        let supplied = String(authorization.dropFirst(7))
        return pairedDevices.first { device in
            guard let token = SecureStore.readBridgeDeviceToken(id: device.id, scope: storageScope) else { return false }
            return Self.constantTimeEqual(token, supplied)
        }
    }

    private func sync(_ request: ParsedHTTPRequest, connection: NWConnection) {
        guard let device = authenticatedDevice(request.headers["authorization"]) else {
            respond(connection, status: 401, body: BridgeErrorBody(message: "Pair this device before syncing.")); return
        }
        guard let payload = try? JSONDecoder().decode(DeviceSyncRequest.self, from: request.body), payload.isWithinLimits else {
            respond(connection, status: 413, body: BridgeErrorBody(message: "Sync request is invalid or too large.")); return
        }
        guard let workspaceID, payload.workspaceID == workspaceID,
              let pairedDeviceID = device.syncDeviceID, payload.deviceID == pairedDeviceID else {
            respond(connection, status: 403, body: BridgeErrorBody(message: "Sync workspace or paired device does not match.")); return
        }
        guard let syncHandler else {
            respond(connection, status: 503, body: BridgeErrorBody(message: "Sync is not ready on this Mac.")); return
        }
        do {
            let response = try syncHandler(payload, pairedDeviceID)
            respond(connection, status: 200, body: response)
        } catch {
            respond(connection, status: 409, body: BridgeErrorBody(message: String(error.localizedDescription.prefix(500))))
        }
    }

    private func attachment(_ request: ParsedHTTPRequest, attachmentID: String, connection: NWConnection) {
        guard ["HEAD", "GET", "PUT"].contains(request.method),
              BridgeFileTransferID.isValid(attachmentID) else {
            respond(connection, status: 400, body: BridgeErrorBody(message: "附件请求无效。")); return
        }
        guard (request.method == "PUT" && request.headers["content-type"] == "application/octet-stream") ||
              (request.method != "PUT" && request.body.isEmpty) else {
            respond(connection, status: 400, body: BridgeErrorBody(message: "附件请求格式无效。")); return
        }
        guard authenticatedDevice(request.headers["authorization"]) != nil else {
            respond(connection, status: 401, body: BridgeErrorBody(message: "请先配对设备再同步附件。")); return
        }
        guard request.body.count <= AttachmentStore.maximumFileBytes,
              let attachmentHandler else {
            respond(connection, status: request.body.count > AttachmentStore.maximumFileBytes ? 413 : 503,
                    body: BridgeErrorBody(message: "附件传输暂不可用。")); return
        }
        do {
            let payload = try attachmentHandler(request.method, attachmentID, request.body)
            let status = request.method == "PUT" ? 204 : 200
            respondAttachment(connection, status: status, payload: payload, includeBody: request.method == "GET")
        } catch let error as AttachmentStoreError {
            let status: Int
            switch error {
            case .missing, .invalidRecord: status = 404
            case .checksumMismatch: status = 409
            case .tooLarge: status = 413
            case .unsupportedType, .invalidText: status = 400
            }
            respond(connection, status: status, body: BridgeErrorBody(message: error.localizedDescription))
        } catch let error as ArtifactAssetStoreError {
            let status: Int
            switch error {
            case .missing, .invalidRecord: status = 404
            case .checksumMismatch, .conflict: status = 409
            case .tooLarge: status = 413
            case .unsupportedType: status = 400
            }
            respond(connection, status: status, body: BridgeErrorBody(message: error.localizedDescription))
        } catch {
            respond(connection, status: 400, body: BridgeErrorBody(message: String(error.localizedDescription.prefix(300))))
        }
    }

    private func respondAttachment(_ connection: NWConnection, status: Int, payload: BridgeAttachmentPayload, includeBody: Bool) {
        let body = includeBody ? payload.data : Data()
        let reason = Self.reasonPhrase(status)
        var headers = "HTTP/1.1 \(status) \(reason)\r\nContent-Type: application/octet-stream\r\nContent-Length: \(payload.byteCount)\r\nCache-Control: no-store\r\nX-OpenMuse-SHA256: \(payload.sha256)\r\nX-OpenMuse-ByteCount: \(payload.byteCount)\r\nConnection: close\r\n\r\n"
        if status == 204 { headers = "HTTP/1.1 204 No Content\r\nContent-Length: 0\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n" }
        var response = Data(headers.utf8)
        response.append(body)
        connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
    }

    private static func attachmentID(from path: String) -> String? {
        let parts = path.split(separator: "/").map(String.init)
        guard parts.count >= 3, parts.suffix(2).first == "attachments" else { return nil }
        return parts.last
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
        case 409: "Conflict"
        case 429: "Too Many Requests"
        case 499: "Client Closed Request"
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
        guard length >= 0, length <= AttachmentStore.maximumFileBytes + 64 * 1024 else { return .invalid }
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
