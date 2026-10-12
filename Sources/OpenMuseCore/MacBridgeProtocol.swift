import Foundation

public struct BridgePairRequest: Codable, Sendable {
    public var code: String
    public var deviceName: String
    public var deviceID: String?

    public init(code: String, deviceName: String, deviceID: String? = nil) {
        self.code = code
        self.deviceName = deviceName
        self.deviceID = deviceID
    }
}

public struct BridgePairResponse: Codable, Sendable {
    public var deviceID: String
    public var token: String
    public var workspaceID: String?
    public var hostDeviceID: String?
}

public struct BridgeChatRequest: Codable, Sendable {
    public var requestID: String
    public var systemPrompt: String
    public var messages: [TranscriptMessage]
    public var executionTaskID: String?
    public var executionRunEpoch: Int?
    public var executionCheckpointID: String?
    public var returnOwnerDeviceID: String?

    public init(
        requestID: String = UUID().uuidString,
        systemPrompt: String,
        messages: [TranscriptMessage],
        executionTaskID: String? = nil,
        executionRunEpoch: Int? = nil,
        executionCheckpointID: String? = nil,
        returnOwnerDeviceID: String? = nil
    ) {
        self.requestID = requestID
        self.systemPrompt = systemPrompt
        self.messages = messages
        self.executionTaskID = executionTaskID
        self.executionRunEpoch = executionRunEpoch
        self.executionCheckpointID = executionCheckpointID
        self.returnOwnerDeviceID = returnOwnerDeviceID
    }

    public var isWithinLimits: Bool {
        !requestID.isEmpty && requestID.count <= 100 && systemPrompt.utf8.count <= 32_000 && messages.count <= 40 &&
        executionTaskID.map { !$0.isEmpty && $0.count <= 200 } ?? true &&
        executionRunEpoch.map { $0 > 0 } ?? true &&
        executionCheckpointID.map { !$0.isEmpty && $0.count <= 200 } ?? true &&
        returnOwnerDeviceID.map { !$0.isEmpty && $0.count <= 100 } ?? true &&
        ((executionTaskID == nil && executionRunEpoch == nil && executionCheckpointID == nil && returnOwnerDeviceID == nil) ||
         (executionTaskID != nil && executionRunEpoch != nil && executionCheckpointID != nil && returnOwnerDeviceID != nil)) &&
        messages.allSatisfy { ["user", "assistant"].contains($0.role) && $0.content.utf8.count <= 32_000 } &&
        messages.reduce(systemPrompt.utf8.count) { $0 + $1.content.utf8.count } <= 256_000
    }
}

public struct BridgeChatResponse: Codable, Sendable {
    public var requestID: String
    public var answer: String
    public var toolEvents: [ModelToolExecutionEvent]

    private enum CodingKeys: String, CodingKey {
        case requestID, answer, toolEvents
    }

    public init(requestID: String, answer: String, toolEvents: [ModelToolExecutionEvent] = []) {
        self.requestID = requestID
        self.answer = answer
        self.toolEvents = toolEvents
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        requestID = try values.decode(String.self, forKey: .requestID)
        answer = try values.decode(String.self, forKey: .answer)
        toolEvents = try values.decodeIfPresent([ModelToolExecutionEvent].self, forKey: .toolEvents) ?? []
    }

    public var isWithinLimits: Bool {
        requestID.count <= 100 && answer.utf8.count <= 256_000 && toolEvents.count <= 128 &&
        toolEvents.allSatisfy(Self.isAllowedToolEvent)
    }

    static func isAllowedToolEvent(_ event: ModelToolExecutionEvent) -> Bool {
        guard !event.toolCallID.isEmpty, event.toolCallID.count <= 150,
              ["openmuse_list_files", "openmuse_read_file"].contains(event.toolName),
              ["started", "completed", "failed", "cancelled"].contains(event.status),
              event.isWithinActivityLimits else { return false }
        guard let path = event.relativePath else { return true }
        guard path.count <= 500, !path.hasPrefix("/"), !path.contains("\\") else { return false }
        let components = path.split(separator: "/")
        return !components.contains("..") && !components.contains(".")
    }
}

public struct BridgeChatEventsRequest: Codable, Sendable {
    public var requestID: String
    public var afterSequence: Int
    public var afterTextCharacterOffset: Int

    private enum CodingKeys: String, CodingKey { case requestID, afterSequence, afterTextCharacterOffset }

    public init(requestID: String, afterSequence: Int = 0, afterTextCharacterOffset: Int = 0) {
        self.requestID = requestID
        self.afterSequence = afterSequence
        self.afterTextCharacterOffset = afterTextCharacterOffset
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        requestID = try values.decode(String.self, forKey: .requestID)
        afterSequence = try values.decodeIfPresent(Int.self, forKey: .afterSequence) ?? 0
        afterTextCharacterOffset = try values.decodeIfPresent(Int.self, forKey: .afterTextCharacterOffset) ?? 0
    }

    public var isWithinLimits: Bool {
        !requestID.isEmpty && requestID.count <= 100 && afterSequence >= 0 && (0...256_000).contains(afterTextCharacterOffset)
    }
}

public struct BridgeSequencedToolEvent: Codable, Equatable, Sendable {
    public var sequence: Int
    public var event: ModelToolExecutionEvent

    public init(sequence: Int, event: ModelToolExecutionEvent) {
        self.sequence = sequence
        self.event = event
    }
}

public struct BridgeChatEventsResponse: Codable, Sendable {
    public var requestID: String
    public var events: [BridgeSequencedToolEvent]
    public var nextSequence: Int
    public var isActive: Bool
    public var heartbeatAt: Date?
    public var textDelta: String
    public var nextTextCharacterOffset: Int

    private enum CodingKeys: String, CodingKey { case requestID, events, nextSequence, isActive, heartbeatAt, textDelta, nextTextCharacterOffset }

    public init(requestID: String, events: [BridgeSequencedToolEvent], nextSequence: Int, isActive: Bool, heartbeatAt: Date?, textDelta: String = "", nextTextCharacterOffset: Int = 0) {
        self.requestID = requestID
        self.events = events
        self.nextSequence = nextSequence
        self.isActive = isActive
        self.heartbeatAt = heartbeatAt
        self.textDelta = textDelta
        self.nextTextCharacterOffset = nextTextCharacterOffset
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        requestID = try values.decode(String.self, forKey: .requestID)
        events = try values.decodeIfPresent([BridgeSequencedToolEvent].self, forKey: .events) ?? []
        nextSequence = try values.decodeIfPresent(Int.self, forKey: .nextSequence) ?? 0
        isActive = try values.decodeIfPresent(Bool.self, forKey: .isActive) ?? false
        heartbeatAt = try values.decodeIfPresent(Date.self, forKey: .heartbeatAt)
        textDelta = try values.decodeIfPresent(String.self, forKey: .textDelta) ?? ""
        nextTextCharacterOffset = try values.decodeIfPresent(Int.self, forKey: .nextTextCharacterOffset) ?? 0
    }

    public var isWithinLimits: Bool {
        requestID.count <= 100 && events.count <= 8 && nextSequence >= 0 &&
        textDelta.utf8.count <= 64 * 1024 && (0...256_000).contains(nextTextCharacterOffset) &&
        events.allSatisfy { $0.sequence > 0 && BridgeChatResponse.isAllowedToolEvent($0.event) } &&
        zip(events, events.dropFirst()).allSatisfy { $0.0.sequence < $0.1.sequence }
    }
}

public struct BridgeChatResult: Sendable {
    public let answer: String
    public let toolEvents: [ModelToolExecutionEvent]

    public init(answer: String, toolEvents: [ModelToolExecutionEvent] = []) {
        self.answer = answer
        self.toolEvents = toolEvents
    }
}

private actor BridgeStreamTextBuffer {
    private var storage = ""
    func append(_ text: String) { storage += text }
    func value() -> String { storage }
}

public struct BridgeCancelRequest: Codable, Sendable {
    public var requestID: String

    public init(requestID: String) { self.requestID = requestID }
}

public struct BridgeCancelResponse: Codable, Sendable {
    public var requestID: String
    public var cancelled: Bool

    public init(requestID: String, cancelled: Bool) {
        self.requestID = requestID
        self.cancelled = cancelled
    }
}

public struct BridgeAttachmentPayload: Sendable {
    public let data: Data
    public let byteCount: Int
    public let sha256: String

    public init(data: Data, byteCount: Int, sha256: String) {
        self.data = data
        self.byteCount = byteCount
        self.sha256 = sha256
    }
}

public enum BridgeFileTransferID {
    private static let artifactMarker = "artifact~"

    public static func artifactAsset(artifactID: String, assetID: String) -> String? {
        guard ArtifactAssetStore.isSafeID(artifactID), ArtifactAssetStore.isSafeID(assetID) else { return nil }
        return "\(artifactMarker)\(artifactID)~\(assetID)"
    }

    public static func artifactAssetComponents(from value: String) -> (artifactID: String, assetID: String)? {
        guard value.hasPrefix(artifactMarker) else { return nil }
        let parts = value.dropFirst(artifactMarker.count).split(separator: "~", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        let artifactID = String(parts[0])
        let assetID = String(parts[1])
        guard ArtifactAssetStore.isSafeID(artifactID), ArtifactAssetStore.isSafeID(assetID) else { return nil }
        return (artifactID, assetID)
    }

    public static func isValid(_ value: String) -> Bool {
        AttachmentRecord.isSafeIdentifier(value) || artifactAssetComponents(from: value) != nil
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

    public static func pair(address: String, code: String, deviceID: String = UUID().uuidString, session: URLSession? = nil) async throws -> (endpoint: String, token: String, workspaceID: String?, hostDeviceID: String?) {
        guard let base = baseURL(address) else { throw MacBridgeError.invalidAddress }
        let requestBody = BridgePairRequest(code: code.trimmingCharacters(in: .whitespacesAndNewlines), deviceName: deviceName, deviceID: deviceID)
        let data = try JSONEncoder().encode(requestBody)
        let responseData = try await send(path: "v1/pair", base: base, body: data, token: nil, session: session ?? directSession)
        let response = try JSONDecoder().decode(BridgePairResponse.self, from: responseData)
        return (base.absoluteString, response.token, response.workspaceID, response.hostDeviceID)
    }

    public static func reply(address: String, token: String, request: BridgeChatRequest, session: URLSession? = nil) async throws -> String {
        try await replyWithEvents(address: address, token: token, request: request, session: session).answer
    }

    public static func replyWithEvents(
        address: String,
        token: String,
        request: BridgeChatRequest,
        session: URLSession? = nil,
        onEvent: @escaping @Sendable (ModelToolExecutionEvent) async -> Void = { _ in },
        onDelta: @escaping @Sendable (String) async -> Void = { _ in },
        onHeartbeat: @escaping @Sendable (Date?) async -> Void = { _ in }
    ) async throws -> BridgeChatResponse {
        guard request.isWithinLimits, let base = baseURL(address) else { throw MacBridgeError.invalidAddress }
        let activeSession = session ?? directSession
        let streamedText = BridgeStreamTextBuffer()
        let eventPoller = Task {
            var cursor = 0
            var textCursor = 0
            var missedHeartbeats = 0
            while !Task.isCancelled {
                do {
                    let snapshot = try await Self.chatEvents(
                        address: address,
                        token: token,
                        request: BridgeChatEventsRequest(requestID: request.requestID, afterSequence: cursor, afterTextCharacterOffset: textCursor),
                        session: activeSession
                    )
                    for item in snapshot.events where item.sequence > cursor {
                        cursor = item.sequence
                        await onEvent(item.event)
                    }
                    if !snapshot.textDelta.isEmpty {
                        textCursor = snapshot.nextTextCharacterOffset
                        await streamedText.append(snapshot.textDelta)
                        await onDelta(snapshot.textDelta)
                    }
                    if snapshot.isActive, let heartbeatAt = snapshot.heartbeatAt,
                       Date.now.timeIntervalSince(heartbeatAt) <= 15 {
                        missedHeartbeats = 0
                        await onHeartbeat(heartbeatAt)
                    } else if snapshot.isActive {
                        missedHeartbeats += 1
                    }
                } catch is CancellationError {
                    return
                } catch {
                    // A poll can race the initial chat request or briefly lose the
                    // private route. Keep the main reply authoritative and retry.
                    missedHeartbeats += 1
                }
                if missedHeartbeats == 3 { await onHeartbeat(nil) }
                do { try await Task.sleep(nanoseconds: 800_000_000) }
                catch { return }
            }
        }
        defer { eventPoller.cancel() }
        let response = try await withTaskCancellationHandler {
            let data = try await send(path: "v1/chat", base: base, body: try JSONEncoder().encode(request), token: token, session: activeSession)
            guard data.count <= 512 * 1024 else { throw MacBridgeError.invalidResponse }
            let response = try JSONDecoder().decode(BridgeChatResponse.self, from: data)
            guard response.isWithinLimits,
                  response.requestID == request.requestID,
                  !response.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw MacBridgeError.invalidResponse
            }
            return response
        } onCancel: {
            Task.detached {
                _ = try? await Self.cancel(address: address, token: token, requestID: request.requestID, session: activeSession)
            }
        }
        eventPoller.cancel()
        await eventPoller.value
        let alreadyStreamed = await streamedText.value()
        if response.answer.hasPrefix(alreadyStreamed) {
            let remainder = String(response.answer.dropFirst(alreadyStreamed.count))
            if !remainder.isEmpty { await onDelta(remainder) }
        } else if alreadyStreamed.isEmpty {
            await onDelta(response.answer)
        }
        return response
    }

    public static func chatEvents(address: String, token: String, request: BridgeChatEventsRequest, session: URLSession? = nil) async throws -> BridgeChatEventsResponse {
        guard request.isWithinLimits, let base = baseURL(address) else { throw MacBridgeError.invalidAddress }
        let data = try await send(
            path: "v1/chat-events",
            base: base,
            body: try JSONEncoder().encode(request),
            token: token,
            session: session ?? directSession,
            timeout: 8
        )
        guard data.count <= 256 * 1024 else { throw MacBridgeError.invalidResponse }
        let response = try JSONDecoder().decode(BridgeChatEventsResponse.self, from: data)
        guard response.isWithinLimits,
              response.requestID == request.requestID,
              response.events.allSatisfy({ $0.sequence > request.afterSequence }),
              response.nextSequence >= (response.events.last?.sequence ?? request.afterSequence),
              response.nextTextCharacterOffset >= request.afterTextCharacterOffset,
              response.nextTextCharacterOffset <= request.afterTextCharacterOffset + response.textDelta.count else {
            throw MacBridgeError.invalidResponse
        }
        return response
    }

    @discardableResult
    public static func cancel(address: String, token: String, requestID: String, session: URLSession? = nil) async throws -> Bool {
        guard !requestID.isEmpty, requestID.count <= 100, let base = baseURL(address) else { throw MacBridgeError.invalidAddress }
        let body = try JSONEncoder().encode(BridgeCancelRequest(requestID: requestID))
        let data = try await send(path: "v1/cancel", base: base, body: body, token: token, session: session ?? directSession)
        let response = try JSONDecoder().decode(BridgeCancelResponse.self, from: data)
        guard response.requestID == requestID else { throw MacBridgeError.invalidResponse }
        return response.cancelled
    }

    public static func sync(address: String, token: String, request: DeviceSyncRequest, session: URLSession? = nil) async throws -> DeviceSyncResponse {
        guard request.isWithinLimits, let base = baseURL(address) else { throw MacBridgeError.invalidAddress }
        let data = try await send(path: "v1/sync", base: base, body: try JSONEncoder().encode(request), token: token, session: session ?? directSession)
        guard data.count <= 1_000_000 else { throw MacBridgeError.invalidResponse }
        let response = try JSONDecoder().decode(DeviceSyncResponse.self, from: data)
        let requestedIDs = Set(request.events.map(\.eventID))
        guard response.isWithinLimits,
              response.acceptedEventIDs.allSatisfy(requestedIDs.contains),
              response.events.allSatisfy({ $0.workspaceID == request.workspaceID }) else { throw MacBridgeError.invalidResponse }
        return response
    }

    public static func attachmentDigest(address: String, token: String, id: String, session: URLSession? = nil) async throws -> (sha256: String, byteCount: Int)? {
        guard BridgeFileTransferID.isValid(id), let base = baseURL(address) else { throw MacBridgeError.invalidAddress }
        var request = URLRequest(url: base.appendingPathComponent("v1/attachments/\(id)"))
        request.httpMethod = "HEAD"
        request.timeoutInterval = 30
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (_, response) = try await attachmentRequest(request, session: session ?? directSession)
        guard let http = response as? HTTPURLResponse else { throw MacBridgeError.invalidResponse }
        if http.statusCode == 404 { return nil }
        guard http.statusCode == 200 else { throw MacBridgeError.rejected("Mac 附件检查返回 HTTP \(http.statusCode)。") }
        guard let digest = http.value(forHTTPHeaderField: "X-OpenMuse-SHA256"), digest.count == 64, digest.allSatisfy(\.isHexDigit) else {
            throw MacBridgeError.rejected("Mac 的附件检查响应缺少有效 SHA-256 摘要。")
        }
        guard let length = Int(http.value(forHTTPHeaderField: "X-OpenMuse-ByteCount") ?? ""), length > 0,
              length <= AttachmentStore.maximumFileBytes else {
            throw MacBridgeError.rejected("Mac 的附件检查响应缺少有效文件大小（\(http.allHeaderFields)）。")
        }
        return (digest.lowercased(), length)
    }

    public static func uploadAttachment(address: String, token: String, id: String, payload: BridgeAttachmentPayload, session: URLSession? = nil) async throws {
        guard BridgeFileTransferID.isValid(id), payload.data.count == payload.byteCount,
              payload.byteCount > 0, payload.byteCount <= AttachmentStore.maximumFileBytes,
              payload.sha256.count == 64, payload.sha256.allSatisfy(\.isHexDigit), let base = baseURL(address) else {
            throw MacBridgeError.invalidAddress
        }
        var request = URLRequest(url: base.appendingPathComponent("v1/attachments/\(id)"))
        request.httpMethod = "PUT"
        request.timeoutInterval = 180
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.setValue(payload.sha256.lowercased(), forHTTPHeaderField: "X-OpenMuse-SHA256")
        request.httpBody = payload.data
        let (data, response) = try await attachmentRequest(request, session: session ?? directSession)
        guard let http = response as? HTTPURLResponse, http.statusCode == 204, data.isEmpty else {
            throw MacBridgeError.rejected((try? JSONDecoder().decode(BridgeErrorResponse.self, from: data))?.message ?? "附件上传失败。")
        }
    }

    public static func downloadAttachment(address: String, token: String, id: String, expectedByteCount: Int, expectedSHA256: String, session: URLSession? = nil) async throws -> Data {
        guard BridgeFileTransferID.isValid(id), expectedByteCount > 0,
              expectedByteCount <= AttachmentStore.maximumFileBytes,
              expectedSHA256.count == 64, expectedSHA256.allSatisfy(\.isHexDigit), let base = baseURL(address) else {
            throw MacBridgeError.invalidAddress
        }
        var request = URLRequest(url: base.appendingPathComponent("v1/attachments/\(id)"))
        request.httpMethod = "GET"
        request.timeoutInterval = 180
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await attachmentRequest(request, session: session ?? directSession)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              data.count == expectedByteCount,
              http.value(forHTTPHeaderField: "X-OpenMuse-SHA256")?.lowercased() == expectedSHA256.lowercased() else {
            throw MacBridgeError.invalidResponse
        }
        return data
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

    private static func send(path: String, base: URL, body: Data, token: String?, session: URLSession, timeout: TimeInterval = 180) async throws -> Data {
        var request = URLRequest(url: base.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
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
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch let error as MacBridgeError {
            throw error
        } catch {
            throw MacBridgeError.unavailable
        }
    }

    private static func attachmentRequest(_ request: URLRequest, session: URLSession) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
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
