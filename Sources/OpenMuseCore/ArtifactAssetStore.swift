import CryptoKit
import Foundation

public struct ArtifactAssetDescriptor: Codable, Equatable, Sendable {
    public let id: String
    public let mediaType: String
    public let byteCount: Int
    public let sha256: String

    public init(id: String, mediaType: String, byteCount: Int, sha256: String) {
        self.id = id
        self.mediaType = mediaType
        self.byteCount = byteCount
        self.sha256 = sha256
    }

    public var isValid: Bool {
        ArtifactAssetStore.isSafeID(id) && ArtifactAssetStore.allowedMediaTypes.contains(mediaType) &&
        byteCount > 0 && byteCount <= ArtifactAssetStore.maximumAssetBytes &&
        sha256.count == 64 && sha256.allSatisfy(\.isHexDigit)
    }
}

public struct PendingArtifactAsset: Equatable, Sendable {
    public let id: String
    public let displayName: String
    public let mediaType: String
    public let data: Data

    public init(id: String = UUID().uuidString, displayName: String, mediaType: String, data: Data) {
        self.id = id
        self.displayName = displayName
        self.mediaType = mediaType
        self.data = data
    }
}

public enum ArtifactAssetStoreError: Error, LocalizedError, Equatable {
    case unsupportedType
    case tooLarge
    case invalidRecord
    case missing
    case checksumMismatch
    case conflict

    public var errorDescription: String? {
        switch self {
        case .unsupportedType: "构件素材目前只支持 PNG、JPEG、GIF、WebP 和 HEIC 图片。"
        case .tooLarge: "单张图片不能超过 5 MB，单个构件最多保存 20 MB 图片。"
        case .invalidRecord: "构件图片资料无效。"
        case .missing: "构件图片文件已不存在于这台设备。"
        case .checksumMismatch: "构件图片校验失败，文件没有显示或导出。"
        case .conflict: "构件图片 ID 已被不同内容占用。"
        }
    }
}

/// Stores portable image assets separately from artifact JSON and verifies each read by SHA-256.
public final class ArtifactAssetStore: @unchecked Sendable {
    public static let maximumAssetBytes = 5 * 1024 * 1024
    public static let maximumAssetsPerArtifact = 32
    public static let maximumTotalBytesPerArtifact = 20 * 1024 * 1024
    public static let allowedMediaTypes: Set<String> = ["image/png", "image/jpeg", "image/gif", "image/webp", "image/heic"]

    private let rootURL: URL
    private let lock = NSRecursiveLock()

    public init(rootURL: URL) throws {
        self.rootURL = rootURL
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    public static func prepareFile(at url: URL) throws -> PendingArtifactAsset {
        let mediaType = mediaType(forExtension: url.pathExtension)
        guard allowedMediaTypes.contains(mediaType) else { throw ArtifactAssetStoreError.unsupportedType }
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
              values.isRegularFile == true, let size = values.fileSize, size > 0 else {
            throw ArtifactAssetStoreError.invalidRecord
        }
        guard size <= maximumAssetBytes else { throw ArtifactAssetStoreError.tooLarge }
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        guard !data.isEmpty, data.count <= maximumAssetBytes else { throw ArtifactAssetStoreError.tooLarge }
        return PendingArtifactAsset(displayName: safeDisplayName(url.lastPathComponent), mediaType: mediaType, data: data)
    }

    @discardableResult
    public func write(_ asset: PendingArtifactAsset, for artifactID: String) throws -> ArtifactAssetDescriptor {
        guard Self.isSafeID(artifactID), Self.isSafeID(asset.id), Self.allowedMediaTypes.contains(asset.mediaType) else {
            throw ArtifactAssetStoreError.invalidRecord
        }
        guard !asset.data.isEmpty, asset.data.count <= Self.maximumAssetBytes else { throw ArtifactAssetStoreError.tooLarge }
        let descriptor = ArtifactAssetDescriptor(
            id: asset.id, mediaType: asset.mediaType, byteCount: asset.data.count, sha256: Self.sha256(asset.data)
        )
        lock.lock(); defer { lock.unlock() }
        let directory = try artifactDirectoryURL(artifactID: artifactID, createIfMissing: true)
        let url = directory.appendingPathComponent(asset.id, isDirectory: false)
        if FileManager.default.fileExists(atPath: url.path) {
            guard (try? data(for: descriptor, artifactID: artifactID)) == asset.data else { throw ArtifactAssetStoreError.conflict }
            return descriptor
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try asset.data.write(to: url, options: .atomic)
        return descriptor
    }

    public func data(for descriptor: ArtifactAssetDescriptor, artifactID: String) throws -> Data {
        guard descriptor.isValid, Self.isSafeID(artifactID) else { throw ArtifactAssetStoreError.invalidRecord }
        lock.lock(); defer { lock.unlock() }
        let directory = try artifactDirectoryURL(artifactID: artifactID, createIfMissing: false)
        let url = directory.appendingPathComponent(descriptor.id, isDirectory: false)
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey]),
              values.isRegularFile == true, values.isSymbolicLink != true,
              values.fileSize == descriptor.byteCount else { throw ArtifactAssetStoreError.missing }
        let bytes = try Data(contentsOf: url, options: [.mappedIfSafe])
        guard Self.sha256(bytes) == descriptor.sha256 else { throw ArtifactAssetStoreError.checksumMismatch }
        return bytes
    }

    public func writeSyncedData(_ data: Data, matching descriptor: ArtifactAssetDescriptor, artifactID: String) throws {
        guard descriptor.isValid, Self.isSafeID(artifactID), data.count == descriptor.byteCount,
              Self.sha256(data) == descriptor.sha256 else { throw ArtifactAssetStoreError.checksumMismatch }
        do {
            let existing = try self.data(for: descriptor, artifactID: artifactID)
            guard existing == data else { throw ArtifactAssetStoreError.conflict }
            return
        } catch ArtifactAssetStoreError.missing {
            try? remove(id: descriptor.id, for: artifactID)
        } catch ArtifactAssetStoreError.checksumMismatch {
            try remove(id: descriptor.id, for: artifactID)
        }
        let asset = PendingArtifactAsset(id: descriptor.id, displayName: "图片", mediaType: descriptor.mediaType, data: data)
        _ = try write(asset, for: artifactID)
    }

    public func remove(id: String, for artifactID: String) throws {
        guard Self.isSafeID(id), Self.isSafeID(artifactID) else { throw ArtifactAssetStoreError.invalidRecord }
        lock.lock(); defer { lock.unlock() }
        let directory = try artifactDirectoryURL(artifactID: artifactID, createIfMissing: false)
        let url = directory.appendingPathComponent(id, isDirectory: false)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }

    public func removeAll(for artifactID: String) throws {
        guard Self.isSafeID(artifactID) else { throw ArtifactAssetStoreError.invalidRecord }
        lock.lock(); defer { lock.unlock() }
        let directory = rootURL.appendingPathComponent(artifactID, isDirectory: true)
        if FileManager.default.fileExists(atPath: directory.path) {
            guard let values = try? directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                  values.isDirectory == true, values.isSymbolicLink != true else { throw ArtifactAssetStoreError.invalidRecord }
            try FileManager.default.removeItem(at: directory)
        }
    }

    public func removeOrphanedFiles(keeping references: [String: Set<String>]) throws {
        lock.lock(); defer { lock.unlock() }
        let artifactDirectories = try FileManager.default.contentsOfDirectory(
            at: rootURL, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles]
        )
        for directory in artifactDirectories {
            let artifactID = directory.lastPathComponent
            guard Self.isSafeID(artifactID),
                  let values = try? directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                  values.isDirectory == true, values.isSymbolicLink != true else { continue }
            guard let allowedIDs = references[artifactID] else {
                try FileManager.default.removeItem(at: directory)
                continue
            }
            let files = try FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles]
            )
            for file in files where !allowedIDs.contains(file.lastPathComponent) {
                try FileManager.default.removeItem(at: file)
            }
        }
    }

    public static func isSafeID(_ value: String) -> Bool {
        !value.isEmpty && value.count <= 100 && value.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
    }

    public static func mediaType(forExtension fileExtension: String) -> String {
        switch fileExtension.lowercased() {
        case "png": "image/png"
        case "jpg", "jpeg": "image/jpeg"
        case "gif": "image/gif"
        case "webp": "image/webp"
        case "heic", "heif": "image/heic"
        default: "application/octet-stream"
        }
    }

    private func artifactDirectoryURL(artifactID: String, createIfMissing: Bool) throws -> URL {
        guard Self.isSafeID(artifactID) else { throw ArtifactAssetStoreError.invalidRecord }
        let directory = rootURL.appendingPathComponent(artifactID, isDirectory: true)
        if !FileManager.default.fileExists(atPath: directory.path) {
            guard createIfMissing else { throw ArtifactAssetStoreError.missing }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        guard let values = try? directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
              values.isDirectory == true, values.isSymbolicLink != true else { throw ArtifactAssetStoreError.invalidRecord }
        return directory
    }

    private static func safeDisplayName(_ name: String) -> String {
        let safe = URL(fileURLWithPath: name).lastPathComponent
            .components(separatedBy: .controlCharacters).joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String((safe.isEmpty ? "图片" : safe).prefix(240))
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
