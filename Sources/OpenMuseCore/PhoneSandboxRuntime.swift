import Foundation

public struct PhoneSandboxCommandResult: Equatable, Sendable {
    public let output: String
    public let exitCode: Int32
    public let timedOut: Bool
    public let outputTruncated: Bool

    public init(output: String, exitCode: Int32, timedOut: Bool, outputTruncated: Bool) {
        self.output = output
        self.exitCode = exitCode
        self.timedOut = timedOut
        self.outputTruncated = outputTruncated
    }
}

public enum PhoneSandboxCommandError: Error, LocalizedError, Equatable {
    case emptyCommand
    case commandTooLarge
    case containsNullByte
    case runtimeUnavailable
    case executionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .emptyCommand: "命令不能为空。"
        case .commandTooLarge: "命令不能超过 4 KB。"
        case .containsNullByte: "命令包含不支持的空字符。"
        case .runtimeUnavailable: "iSH 运行环境暂不可用。"
        case .executionFailed(let detail): detail
        }
    }
}

public enum PhoneSandboxCommandPolicy {
    public static let maximumCommandBytes = 4_096
    public static let maximumOutputBytes = 12_000
    public static let maximumDuration: TimeInterval = 45

    public static func validate(_ command: String) throws -> String {
        let normalized = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { throw PhoneSandboxCommandError.emptyCommand }
        guard normalized.utf8.count <= maximumCommandBytes else { throw PhoneSandboxCommandError.commandTooLarge }
        guard !normalized.unicodeScalars.contains(where: { $0.value == 0 }) else {
            throw PhoneSandboxCommandError.containsNullByte
        }
        return normalized
    }
}

/// A deliberately narrow boundary between the iOS app target and the model/tool loop.
/// The adapter must only expose the mounts it receives and must enforce timeout and output limits.
public protocol PhoneSandboxCommandRuntime: Sendable {
    func execute(
        command: String,
        mounts: [OnDeviceRuntimeMount],
        timeout: TimeInterval,
        maximumOutputBytes: Int
    ) async throws -> PhoneSandboxCommandResult

    func execute(
        command: String,
        mounts: [OnDeviceRuntimeMount],
        timeout: TimeInterval,
        maximumOutputBytes: Int,
        onOutput: @escaping @Sendable (String) async -> Void
    ) async throws -> PhoneSandboxCommandResult

    /// Context-aware execution lets a native guest bridge use session-scoped
    /// app capabilities (for example, the same browser tabs as the model tool).
    /// Runtimes that do not support such bridges can ignore the identifier.
    func execute(
        command: String,
        conversationID: String,
        mounts: [OnDeviceRuntimeMount],
        timeout: TimeInterval,
        maximumOutputBytes: Int,
        onOutput: @escaping @Sendable (String) async -> Void
    ) async throws -> PhoneSandboxCommandResult
}

public extension PhoneSandboxCommandRuntime {
    func execute(
        command: String,
        conversationID: String,
        mounts: [OnDeviceRuntimeMount],
        timeout: TimeInterval,
        maximumOutputBytes: Int,
        onOutput: @escaping @Sendable (String) async -> Void
    ) async throws -> PhoneSandboxCommandResult {
        try await execute(
            command: command,
            mounts: mounts,
            timeout: timeout,
            maximumOutputBytes: maximumOutputBytes,
            onOutput: onOutput
        )
    }

    /// Existing runtimes remain source-compatible and expose their final output once.
    /// Interactive runtimes can override this to deliver cumulative snapshots while running.
    func execute(
        command: String,
        mounts: [OnDeviceRuntimeMount],
        timeout: TimeInterval,
        maximumOutputBytes: Int,
        onOutput: @escaping @Sendable (String) async -> Void
    ) async throws -> PhoneSandboxCommandResult {
        let result = try await execute(
            command: command,
            mounts: mounts,
            timeout: timeout,
            maximumOutputBytes: maximumOutputBytes
        )
        if !result.output.isEmpty { await onOutput(result.output) }
        return result
    }
}
