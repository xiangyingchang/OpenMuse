#if os(macOS)
import Foundation

public struct MacPiReadSnapshot: Equatable, Sendable {
    public let url: URL
    public let fileCount: Int
    public let skippedCount: Int

    public init(url: URL, fileCount: Int, skippedCount: Int) {
        self.url = url
        self.fileCount = fileCount
        self.skippedCount = skippedCount
    }
}

public struct MacPiToolAuditEntry: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let createdAt: Date
    public let toolCallID: String
    public let toolName: String
    public let relativePath: String?
    public let status: String

    public init(toolCallID: String, toolName: String, relativePath: String?, status: String, createdAt: Date = .now) {
        id = "\(toolCallID)-\(UUID().uuidString)"
        self.createdAt = createdAt
        self.toolCallID = toolCallID
        self.toolName = toolName
        self.relativePath = relativePath
        self.status = status
    }
}

/// Holds only a local security-scoped bookmark. Pi receives a temporary, read-only snapshot,
/// never the original folder URL or permission to modify source files.
public enum MacPiReadAccess {
    private static let bookmarkKey = "openmuse.pi.read-only-folder.bookmark.v1"
    private static let allowedExtensions: Set<String> = ["csv", "json", "jsonl", "md", "txt", "yaml", "yml"]
    private static let maximumDepth = 4
    private static let maximumFiles = 200
    private static let maximumScannedEntries = 2_000
    private static let maximumFileBytes = 128 * 1024
    private static let maximumTotalBytes = 8 * 1024 * 1024

    public static var authorizedFolderName: String? {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey),
              let url = resolveBookmark(data)?.url else { return nil }
        return url.lastPathComponent
    }

    public static var hasAuthorizedFolder: Bool {
        UserDefaults.standard.data(forKey: bookmarkKey) != nil
    }

    public static func authorizeReadOnlyFolder(_ url: URL) throws {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else {
            throw CocoaError(.fileReadUnsupportedScheme, userInfo: [NSLocalizedDescriptionKey: "请选择一个普通文件夹。"])
        }
        let bookmark = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
        UserDefaults.standard.set(bookmark, forKey: bookmarkKey)
    }

    public static func revokeFolderAccess() {
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
    }

    public static func makeReadSnapshot(in piHome: URL, shouldCancel: @Sendable () -> Bool = { false }) throws -> MacPiReadSnapshot? {
        guard let bookmark = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        guard let resolved = resolveBookmark(bookmark) else {
            revokeFolderAccess()
            throw CocoaError(.fileReadNoSuchFile, userInfo: [NSLocalizedDescriptionKey: "已授权的文件夹不可用，请重新选择。"])
        }
        if resolved.isStale {
            try authorizeReadOnlyFolder(resolved.url)
        }
        let startedAccess = resolved.url.startAccessingSecurityScopedResource()
        defer { if startedAccess { resolved.url.stopAccessingSecurityScopedResource() } }
        return try createReadSnapshot(from: resolved.url, in: piHome, shouldCancel: shouldCancel)
    }

    /// Copies only bounded, regular UTF-8 text files into a temporary directory for one Pi run.
    /// Symlinks, hidden paths, binary files, and files outside the selected directory are excluded.
    public static func createReadSnapshot(from folderURL: URL, in piHome: URL, shouldCancel: @Sendable () -> Bool = { false }) throws -> MacPiReadSnapshot {
        let sourceRoot = folderURL.resolvingSymlinksInPath().standardizedFileURL
        let sourceValues = try sourceRoot.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard sourceValues.isDirectory == true, sourceValues.isSymbolicLink != true else {
            throw CocoaError(.fileReadUnsupportedScheme, userInfo: [NSLocalizedDescriptionKey: "授权文件夹不再可用。"])
        }

        let snapshotURL = piHome.appendingPathComponent("read-snapshots", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: snapshotURL, withIntermediateDirectories: true)
        do {
            var included = 0
            var skipped = 0
            var totalBytes = 0
            var scanned = 0
            try copyTextFiles(
                from: sourceRoot,
                into: snapshotURL,
                sourceRoot: sourceRoot,
                depth: 0,
                included: &included,
                skipped: &skipped,
                totalBytes: &totalBytes,
                scanned: &scanned,
                shouldCancel: shouldCancel
            )
            return MacPiReadSnapshot(url: snapshotURL, fileCount: included, skippedCount: skipped)
        } catch {
            try? FileManager.default.removeItem(at: snapshotURL)
            throw error
        }
    }

    public static func appendAudit(_ entry: MacPiToolAuditEntry, supportDirectory: URL) {
        let url = auditURL(in: supportDirectory)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            var line = try encoder.encode(entry)
            line.append(10)
            if FileManager.default.fileExists(atPath: url.path),
               let existing = try? Data(contentsOf: url), existing.count + line.count > 512 * 1024 {
                let retained = existing.suffix(256 * 1024)
                try Data(retained).write(to: url, options: .atomic)
            }
            if FileManager.default.fileExists(atPath: url.path) {
                let handle = try FileHandle(forWritingTo: url)
                try handle.seekToEnd()
                try handle.write(contentsOf: line)
                try handle.close()
            } else {
                try line.write(to: url, options: .atomic)
            }
        } catch {
            // Audit logging must not expose file contents or prevent a read-only answer.
        }
    }

    public static func recentAuditEntries(supportDirectory: URL? = nil, limit: Int = 8) -> [MacPiToolAuditEntry] {
        let support = supportDirectory ?? (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
        guard let support,
              let data = try? Data(contentsOf: auditURL(in: support)),
              let text = String(data: data, encoding: .utf8) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return text.split(separator: "\n").compactMap { try? decoder.decode(MacPiToolAuditEntry.self, from: Data($0.utf8)) }
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(max(0, limit))
            .map { $0 }
    }

    public static func clearAuditLog(supportDirectory: URL? = nil) {
        let support = supportDirectory ?? (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
        guard let support else { return }
        try? FileManager.default.removeItem(at: auditURL(in: support))
    }

    public static func auditURL(in supportDirectory: URL) -> URL {
        supportDirectory.appendingPathComponent("OpenMuse/pi/tool-events.jsonl")
    }

    private static func resolveBookmark(_ data: Data) -> (url: URL, isStale: Bool)? {
        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope, .withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) else { return nil }
        return (url, stale)
    }

    private static func copyTextFiles(
        from source: URL,
        into destination: URL,
        sourceRoot: URL,
        depth: Int,
        included: inout Int,
        skipped: inout Int,
        totalBytes: inout Int,
        scanned: inout Int,
        shouldCancel: @Sendable () -> Bool
    ) throws {
        if shouldCancel() { throw CancellationError() }
        guard depth <= maximumDepth, included < maximumFiles, scanned < maximumScannedEntries else { return }
        let children = try FileManager.default.contentsOfDirectory(
            at: source,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ).sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }

        for child in children {
            if shouldCancel() { throw CancellationError() }
            guard scanned < maximumScannedEntries else { skipped += 1; return }
            scanned += 1
            guard included < maximumFiles else { skipped += 1; continue }
            let values = try child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey])
            guard values.isSymbolicLink != true else { skipped += 1; continue }
            let canonical = child.resolvingSymlinksInPath().standardizedFileURL
            guard isDescendantOrSame(canonical, of: sourceRoot), canonical.path == child.standardizedFileURL.path else {
                skipped += 1
                continue
            }

            if values.isDirectory == true {
                guard depth < maximumDepth else { skipped += 1; continue }
                guard let relative = relativePath(of: canonical, under: sourceRoot) else { skipped += 1; continue }
                let targetDirectory = appendRelativePath(relative, to: destination, isDirectory: true)
                try FileManager.default.createDirectory(at: targetDirectory, withIntermediateDirectories: true)
                try copyTextFiles(
                    from: child,
                    into: destination,
                    sourceRoot: sourceRoot,
                    depth: depth + 1,
                    included: &included,
                    skipped: &skipped,
                    totalBytes: &totalBytes,
                    scanned: &scanned,
                    shouldCancel: shouldCancel
                )
                continue
            }

            let ext = child.pathExtension.lowercased()
            guard values.isDirectory == false, allowedExtensions.contains(ext) else { continue }
            let size = values.fileSize ?? 0
            guard size <= maximumFileBytes, totalBytes + size <= maximumTotalBytes else { skipped += 1; continue }
            let fileHandle = try FileHandle(forReadingFrom: canonical)
            let data: Data
            do {
                data = try fileHandle.read(upToCount: maximumFileBytes + 1) ?? Data()
                try fileHandle.close()
            } catch {
                try? fileHandle.close()
                throw error
            }
            guard data.count <= maximumFileBytes, String(data: data, encoding: .utf8) != nil else { skipped += 1; continue }
            guard let relative = relativePath(of: canonical, under: sourceRoot) else { skipped += 1; continue }
            let target = appendRelativePath(relative, to: destination, isDirectory: false)
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: target, options: .atomic)
            totalBytes += data.count
            included += 1
        }
    }

    private static func isDescendantOrSame(_ child: URL, of root: URL) -> Bool {
        relativePath(of: child, under: root) != nil
    }

    private static func appendRelativePath(_ relative: String, to root: URL, isDirectory: Bool) -> URL {
        let components = relative.split(separator: "/")
        return components.enumerated().reduce(root) { parent, item in
            let isPathDirectory = item.offset < components.count - 1 || isDirectory
            return parent.appendingPathComponent(String(item.element), isDirectory: isPathDirectory)
        }
    }

    private static func relativePath(of child: URL, under root: URL) -> String? {
        let rootComponents = root.standardizedFileURL.pathComponents
        let childComponents = child.standardizedFileURL.pathComponents
        guard childComponents.count >= rootComponents.count,
              Array(childComponents.prefix(rootComponents.count)) == rootComponents else { return nil }
        return childComponents.dropFirst(rootComponents.count).joined(separator: "/")
    }
}
#endif
