import CryptoKit
import Foundation

public enum OnDeviceRuntimeArea: String, CaseIterable, Equatable, Sendable {
    case offloads
    case attachments
    case workspace
    case browser

    public var guestPath: String { "/var/minis/\(rawValue)" }
}

public enum OnDeviceRuntimeAreaAccess: String, Equatable, Sendable {
    case readOnly
    case readWrite
}

public struct OnDeviceRuntimeMount: Sendable, Equatable {
    public let area: OnDeviceRuntimeArea
    public let guestPath: String
    public let hostURL: URL
    public let access: OnDeviceRuntimeAreaAccess
}

public enum OnDeviceRuntimeFilesystemError: Error, LocalizedError, Equatable {
    case invalidConversation
    case unsafeArea(OnDeviceRuntimeArea)
    case attachmentsTooLarge

    public var errorDescription: String? {
        switch self {
        case .invalidConversation: "本机运行会话无效。"
        case .unsafeArea(let area): "本机运行区“\(area.rawValue)”不是安全的普通目录。"
        case .attachmentsTooLarge: "当前对话附件总量超过 iSH 单次可挂载的 50 MB。"
        }
    }
}

/// Host-side directory map for one on-device execution session.
/// Every guest-visible directory is a private runtime area. In particular,
/// `workspace` is scratch space and is never the approved Swift workspace or
/// a projection of formal memory. Product databases, Keychain data, and the
/// rest of the app container are never included.
public struct OnDeviceRuntimeFilesystem {
    public let sessionRootURL: URL
    private let fileManager: FileManager

    public init(
        rootURL: URL,
        conversationID: String,
        fileManager: FileManager = .default
    ) throws {
        guard !conversationID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OnDeviceRuntimeFilesystemError.invalidConversation
        }
        let root = rootURL.standardizedFileURL
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        try Self.requireDirectory(root, fileManager: fileManager, error: .unsafeArea(.workspace))

        let digest = SHA256.hash(data: Data(conversationID.utf8))
        let identifier = digest.map { String(format: "%02x", $0) }.joined()
        let sessionRoot = root.appendingPathComponent(identifier, isDirectory: true)
        try fileManager.createDirectory(at: sessionRoot, withIntermediateDirectories: true)
        try Self.requireDirectory(sessionRoot, fileManager: fileManager, error: .unsafeArea(.workspace))

        self.sessionRootURL = sessionRoot
        self.fileManager = fileManager
    }

    public static func applicationSupportRootURL(fileManager: FileManager = .default) throws -> URL {
        let support = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return support.appendingPathComponent("OpenMuse", isDirectory: true)
            .appendingPathComponent("AgentRuntimeSessions", isDirectory: true)
    }

    /// Creates stable per-session mount directories and returns the only host
    /// paths that an iSH adapter may expose to guest code. The access value is
    /// a contract for the adapter: it must mount read-only areas as read-only.
    public func prepareMounts() throws -> [OnDeviceRuntimeMount] {
        try Self.requireDirectory(sessionRootURL, fileManager: fileManager, error: .unsafeArea(.workspace))
        return try OnDeviceRuntimeArea.allCases.map { area in
            let hostURL = sessionRootURL.appendingPathComponent(area.rawValue, isDirectory: true)
            if !fileManager.fileExists(atPath: hostURL.path) {
                try fileManager.createDirectory(at: hostURL, withIntermediateDirectories: false)
            }
            try Self.requireDirectory(hostURL, fileManager: fileManager, error: .unsafeArea(area))
            guard hostURL.standardizedFileURL.path.hasPrefix(sessionRootURL.standardizedFileURL.path + "/") else {
                throw OnDeviceRuntimeFilesystemError.unsafeArea(area)
            }
            #if os(iOS)
            try fileManager.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: hostURL.path
            )
            #endif
            return OnDeviceRuntimeMount(
                area: area,
                guestPath: area.guestPath,
                hostURL: hostURL,
                access: area == .attachments ? .readOnly : .readWrite
            )
        }
    }

    public func directory(for area: OnDeviceRuntimeArea) throws -> URL {
        guard let mount = try prepareMounts().first(where: { $0.area == area }) else {
            throw OnDeviceRuntimeFilesystemError.unsafeArea(area)
        }
        return mount.hostURL
    }

    /// Refreshes the read-only guest attachment area from this conversation's
    /// checked attachment records. Files are copied under opaque IDs so guest
    /// tools never receive paths into the app's attachment store.
    public func stageAttachments(
        _ records: [AttachmentRecord],
        conversationID: String,
        store: AttachmentStore
    ) throws {
        let scoped = records
            .filter { $0.conversationID == conversationID && $0.isValid }
            .sorted { $0.createdAt < $1.createdAt }
        let totalBytes = scoped.reduce(0) { $0 + $1.byteCount }
        guard totalBytes <= 50 * 1024 * 1024 else {
            throw OnDeviceRuntimeFilesystemError.attachmentsTooLarge
        }

        // Read and checksum every source before clearing the previous view, so
        // a missing/corrupt attachment cannot leave a partially staged set.
        let verified = try scoped.map { record in
            (record, try store.data(for: record))
        }
        let root = try directory(for: .attachments)
        for child in try fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) {
            try fileManager.removeItem(at: child)
        }
        for (record, data) in verified {
            let ext: String
            switch record.mediaType {
            case "text/plain": ext = "txt"
            case "text/markdown": ext = "md"
            case "application/pdf": ext = "pdf"
            default: continue
            }
            let name = Self.safeAttachmentName(record.displayName)
            let destination = root.appendingPathComponent("\(record.id)-\(name).\(ext)")
            try data.write(to: destination, options: .atomic)
        }
    }

    private static func safeAttachmentName(_ name: String) -> String {
        let scalars = name.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_. ")).contains(scalar) ? Character(scalar) : "_"
        }
        let normalized = String(scalars)
            .trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        return String((normalized.isEmpty ? "attachment" : normalized).prefix(100))
    }

    private static func requireDirectory(
        _ url: URL,
        fileManager: FileManager,
        error: OnDeviceRuntimeFilesystemError
    ) throws {
        guard fileManager.fileExists(atPath: url.path),
              let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
              values.isDirectory == true,
              values.isSymbolicLink != true else {
            throw error
        }
    }
}
