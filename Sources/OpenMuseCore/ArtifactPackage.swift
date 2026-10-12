import CryptoKit
import Foundation
import ZIPFoundation

public struct ArtifactPackageAsset: Codable, Equatable, Sendable {
    public let id: String
    public let mediaType: String
    public let data: Data

    public init(id: String, mediaType: String, data: Data) {
        self.id = id
        self.mediaType = mediaType
        self.data = data
    }
}

public struct ArtifactPackage: Equatable, Sendable {
    public let artifact: ArtifactRecord
    public let history: [ArtifactRecord]
    public let assets: [ArtifactPackageAsset]
    public let exportedAt: Date

    public init(artifact: ArtifactRecord, history: [ArtifactRecord] = [], assets: [ArtifactPackageAsset] = [], exportedAt: Date = .now) {
        self.artifact = artifact
        self.history = history
        self.assets = assets
        self.exportedAt = exportedAt
    }
}

public enum ArtifactPackageError: Error, LocalizedError, Equatable {
    case invalidArchive
    case invalidManifest
    case unsupportedVersion
    case checksumMismatch
    case tooLarge

    public var errorDescription: String? {
        switch self {
        case .invalidArchive: "构件包格式无效或包含不允许的路径。"
        case .invalidManifest: "构件包清单不完整。"
        case .unsupportedVersion: "此构件包需要更新版本的 OpenMuse。"
        case .checksumMismatch: "构件包内容校验失败，原有构件没有被替换。"
        case .tooLarge: "构件包超过安全大小限制。"
        }
    }
}

/// Self-contained package for one artifact. Archive paths are allow-listed and every file is hashed.
public enum ArtifactPortablePackage {
    public static let maximumBytes = 25_000_000
    private static let maximumEntries = 2_000
    private static let fixedPaths: Set<String> = ["artifact.json", "revisions.jsonl"]

    public static func encode(_ package: ArtifactPackage) throws -> Data {
        guard package.history.count <= maximumEntries - 2,
              package.assets.count <= 1_000,
              Set(package.assets.map(\.id)).count == package.assets.count,
              package.assets.allSatisfy({ isSafeID($0.id) && !$0.mediaType.isEmpty && $0.mediaType.count <= 160 }),
              package.artifact.content.utf8.count <= maximumBytes,
              package.history.allSatisfy(validTravelPlanVariants),
              validTravelPlanVariants(package.artifact) else { throw ArtifactPackageError.tooLarge }

        let contentPath = package.artifact.kind == "web" ? "content/index.html" : "content/plan.md"
        var files: [String: Data] = [
            "artifact.json": try encodeJSON(package.artifact),
            "revisions.jsonl": try encodeJSONL(package.history),
            contentPath: Data(package.artifact.content.utf8)
        ]
        for asset in package.assets {
            let path = "assets/\(asset.id).bin"
            guard safePath(path), asset.data.count <= maximumBytes else { throw ArtifactPackageError.invalidArchive }
            files[path] = asset.data
        }
        let assetTypes = Dictionary(uniqueKeysWithValues: package.assets.map { ("assets/\($0.id).bin", $0.mediaType) })
        let descriptors = files.map { path, data in
            FileDescriptor(path: path, byteCount: data.count, sha256: digest(data), mediaType: assetTypes[path])
        }.sorted { $0.path < $1.path }
        let manifest = Manifest(
            formatVersion: 1,
            minimumReaderVersion: 1,
            exportedAt: package.exportedAt,
            artifactID: package.artifact.id,
            artifactKind: package.artifact.kind,
            contentPath: contentPath,
            historyCount: package.history.count,
            assetCount: package.assets.count,
            filesSHA256: digest(try encodeJSON(descriptors)),
            files: descriptors
        )
        files["manifest.json"] = try encodeJSON(manifest)
        guard files.values.reduce(0, { $0 + $1.count }) <= maximumBytes else { throw ArtifactPackageError.tooLarge }
        return try makeZip(files)
    }

    public static func decode(_ data: Data) throws -> ArtifactPackage {
        guard !data.isEmpty, data.count <= maximumBytes else { throw ArtifactPackageError.tooLarge }
        let archive: Archive
        do { archive = try Archive(data: data, accessMode: .read) }
        catch { throw ArtifactPackageError.invalidArchive }

        var entries: [String: Entry] = [:]
        for entry in archive {
            guard entries.count < maximumEntries,
                  entry.type == .file,
                  safePath(entry.path),
                  entries[entry.path] == nil else { throw ArtifactPackageError.invalidArchive }
            entries[entry.path] = entry
        }
        guard let manifestEntry = entries["manifest.json"], manifestEntry.uncompressedSize <= 1_000_000 else {
            throw ArtifactPackageError.invalidManifest
        }
        let manifestData = try extract(manifestEntry, from: archive, limit: 1_000_000)
        let manifest: Manifest
        do { manifest = try JSONDecoder().decode(Manifest.self, from: manifestData) }
        catch { throw ArtifactPackageError.invalidManifest }
        guard manifest.formatVersion == 1, manifest.minimumReaderVersion <= 1 else { throw ArtifactPackageError.unsupportedVersion }
        guard !manifest.artifactID.isEmpty, manifest.artifactID.count <= 200,
              ["content/index.html", "content/plan.md"].contains(manifest.contentPath),
              manifest.historyCount >= 0, manifest.historyCount <= maximumEntries,
              manifest.assetCount >= 0, manifest.assetCount <= 1_000,
              manifest.files.count <= maximumEntries,
              Set(manifest.files.map(\.path)).count == manifest.files.count,
              fixedPaths.isSubset(of: Set(manifest.files.map(\.path))),
              manifest.files.allSatisfy({ safePath($0.path) && $0.byteCount >= 0 && $0.byteCount <= maximumBytes && isSHA256($0.sha256) && (($0.path.hasPrefix("assets/") && ($0.mediaType?.isEmpty == false) && ($0.mediaType?.count ?? 0) <= 160) || (!$0.path.hasPrefix("assets/") && $0.mediaType == nil)) }) else {
            throw ArtifactPackageError.invalidManifest
        }
        let descriptors = Dictionary(uniqueKeysWithValues: manifest.files.map { ($0.path, $0) })
        guard Set(entries.keys) == Set(descriptors.keys).union(["manifest.json"]) else { throw ArtifactPackageError.invalidArchive }

        var contents: [String: Data] = [:]
        for descriptor in manifest.files {
            guard let entry = entries[descriptor.path], entry.uncompressedSize == UInt64(descriptor.byteCount) else {
                throw ArtifactPackageError.invalidArchive
            }
            let bytes = try extract(entry, from: archive, limit: descriptor.byteCount)
            guard digest(bytes) == descriptor.sha256 else { throw ArtifactPackageError.checksumMismatch }
            contents[descriptor.path] = bytes
        }
        let actualDescriptors = manifest.files.map { descriptor in
            FileDescriptor(path: descriptor.path, byteCount: contents[descriptor.path]?.count ?? -1, sha256: contents[descriptor.path].map(digest) ?? "", mediaType: descriptor.mediaType)
        }.sorted { $0.path < $1.path }
        guard digest(try encodeJSON(actualDescriptors)) == manifest.filesSHA256 else { throw ArtifactPackageError.checksumMismatch }
        guard let artifactData = contents["artifact.json"], let contentData = contents[manifest.contentPath],
              let content = String(data: contentData, encoding: .utf8),
              let artifact = try? JSONDecoder().decode(ArtifactRecord.self, from: artifactData),
              artifact.id == manifest.artifactID, artifact.kind == manifest.artifactKind,
              artifact.content == content,
              manifest.contentPath == (artifact.kind == "web" ? "content/index.html" : "content/plan.md"),
              let historyData = contents["revisions.jsonl"] else { throw ArtifactPackageError.invalidManifest }
        let history = try decodeJSONL(ArtifactRecord.self, from: historyData)
        guard history.count == manifest.historyCount,
              history.allSatisfy({ $0.id == artifact.id }),
              history.allSatisfy(validTravelPlanVariants),
              validTravelPlanVariants(artifact),
              history.map(\.currentRevision).count == Set(history.map(\.currentRevision)).count else {
            throw ArtifactPackageError.invalidManifest
        }
        let assets = try manifest.files.compactMap { descriptor -> ArtifactPackageAsset? in
            guard descriptor.path.hasPrefix("assets/") else { return nil }
            let id = String(descriptor.path.dropFirst("assets/".count).dropLast(".bin".count))
            guard isSafeID(id), let bytes = contents[descriptor.path] else { throw ArtifactPackageError.invalidArchive }
            return ArtifactPackageAsset(id: id, mediaType: descriptor.mediaType ?? "application/octet-stream", data: bytes)
        }
        guard assets.count == manifest.assetCount else { throw ArtifactPackageError.invalidManifest }
        return ArtifactPackage(artifact: artifact, history: history, assets: assets, exportedAt: manifest.exportedAt)
    }

    private static func makeZip(_ files: [String: Data]) throws -> Data {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("OpenMuseArtifact-\(UUID().uuidString).zip")
        defer { try? FileManager.default.removeItem(at: url) }
        do {
            let archive = try Archive(url: url, accessMode: .create)
            for (path, contents) in files.sorted(by: { $0.key < $1.key }) {
                try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(contents.count), compressionMethod: .deflate) { position, size in
                    let lower = Int(position)
                    let upper = min(lower + size, contents.count)
                    guard lower >= 0, lower <= upper else { throw ArtifactPackageError.invalidArchive }
                    return contents.subdata(in: lower..<upper)
                }
            }
        } catch let error as ArtifactPackageError {
            throw error
        } catch {
            throw ArtifactPackageError.invalidArchive
        }
        let bytes = try Data(contentsOf: url, options: .mappedIfSafe)
        guard bytes.count <= maximumBytes else { throw ArtifactPackageError.tooLarge }
        return bytes
    }

    private static func extract(_ entry: Entry, from archive: Archive, limit: Int) throws -> Data {
        guard limit >= 0, entry.uncompressedSize <= UInt64(limit) else { throw ArtifactPackageError.tooLarge }
        var result = Data()
        do {
            _ = try archive.extract(entry, bufferSize: 16 * 1024) { chunk in
                guard result.count <= limit - chunk.count else { throw ArtifactPackageError.tooLarge }
                result.append(chunk)
            }
        } catch let error as ArtifactPackageError {
            throw error
        } catch {
            throw ArtifactPackageError.invalidArchive
        }
        return result
    }

    private static func encodeJSON<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }

    private static func encodeJSONL<T: Encodable>(_ values: [T]) throws -> Data {
        guard !values.isEmpty else { return Data() }
        var bytes = Data()
        for value in values { bytes.append(try encodeJSON(value)); bytes.append(0x0a) }
        return bytes
    }

    private static func decodeJSONL<T: Decodable>(_ type: T.Type, from data: Data) throws -> [T] {
        guard let text = String(data: data, encoding: .utf8), text.isEmpty || text.hasSuffix("\n") else { throw ArtifactPackageError.invalidArchive }
        if text.isEmpty { return [] }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).dropLast()
        guard lines.count <= maximumEntries, lines.allSatisfy({ !$0.isEmpty }) else { throw ArtifactPackageError.invalidArchive }
        do { return try lines.map { try JSONDecoder().decode(type, from: Data($0.utf8)) } }
        catch { throw ArtifactPackageError.invalidArchive }
    }

    private static func safePath(_ path: String) -> Bool {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\"), !path.split(separator: "/").contains("..") else { return false }
        if path == "manifest.json" || fixedPaths.contains(path) || ["content/index.html", "content/plan.md"].contains(path) { return true }
        guard path.hasPrefix("assets/"), path.hasSuffix(".bin") else { return false }
        return isSafeID(String(path.dropFirst("assets/".count).dropLast(".bin".count)))
    }

    private static func isSafeID(_ value: String) -> Bool {
        !value.isEmpty && value.count <= 200 && value.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "-_".contains($0)) }
    }

    private static func validTravelPlanVariants(_ artifact: ArtifactRecord) -> Bool {
        guard let variants = artifact.travelPlanVariants else { return artifact.selectedTravelPlanVariantID == nil }
        guard variants.count <= TravelPlanArtifactUpdater.maximumVariants,
              Set(variants.map(\.id)).count == variants.count,
              variants.allSatisfy({
                  isSafeID($0.id) && !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                      && $0.title.utf8.count <= 200
                      && $0.content.utf8.count <= TravelPlanArtifactUpdater.maximumVariantContentBytes
                      && ($0.expectedDayCount.map { (1...366).contains($0) } ?? true)
                      && ($0.coveredDayCount.map { (0...366).contains($0) } ?? true)
                      && ($0.sourceMessageIDs?.count ?? 0) <= 1_000
                      && ($0.assumptions?.count ?? 0) <= 200
              }) else { return false }
        if let selectedID = artifact.selectedTravelPlanVariantID {
            return variants.contains(where: { $0.id == selectedID })
        }
        return true
    }

    private static func isSHA256(_ value: String) -> Bool { value.count == 64 && value.allSatisfy(\.isHexDigit) }
    private static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    private struct Manifest: Codable {
        let formatVersion: Int
        let minimumReaderVersion: Int
        let exportedAt: Date
        let artifactID: String
        let artifactKind: String
        let contentPath: String
        let historyCount: Int
        let assetCount: Int
        let filesSHA256: String
        let files: [FileDescriptor]
    }

    private struct FileDescriptor: Codable {
        let path: String
        let byteCount: Int
        let sha256: String
        let mediaType: String?
    }
}
