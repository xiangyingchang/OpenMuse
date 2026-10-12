import Foundation
import ZIPFoundation

public enum WorkspaceBackupError: Error, LocalizedError, Equatable {
    case invalidPackage
    case packageSizeUnavailable
    case destinationNotSelected
    case destinationUnavailable

    public var errorDescription: String? {
        switch self {
        case .invalidPackage:
            return "备份包结构无效或已损坏。"
        case .packageSizeUnavailable:
            return "无法确认所选文件的大小，未读取备份。"
        case .destinationNotSelected:
            return "请先选择备份文件夹。"
        case .destinationUnavailable:
            return "无法访问备份文件夹。请重新选择文件夹后再试。"
        }
    }
}

/// A plain ZIP bundle: Markdown copies are convenient for AI tools and people,
/// while workspace.zip remains the canonical, validated import payload.
public enum WorkspaceBackupPackage {
    private static let indexPath = "openmuse-backup.json"
    private static let archivePath = "workspace.zip"
    private static let readmePath = "README.md"
    public static let maximumPackageBytes = WorkspacePortableArchive.maximumCompressedBytes + 8_000_000
    private static let maximumEntryCount = 10_000

    public static func make(
        workspaceArchive: Data,
        documents: [WorkspaceDocument],
        date: Date = .now
    ) throws -> Data {
        guard workspaceArchive.count <= WorkspacePortableArchive.maximumCompressedBytes else {
            throw WorkspaceArchiveError.tooLarge
        }
        let decoded = try WorkspacePortableArchive.decode(workspaceArchive)
        let markdown = try readableDocuments(documents)
        let includesConversations = !decoded.manifest.omittedKinds.contains(RecordKind.conversation)
        let index = BackupPackageIndex(
            formatVersion: 1,
            createdAt: date,
            workspaceArchivePath: archivePath,
            markdownPaths: markdown.keys.sorted(),
            includesConversations: includesConversations,
            recordCount: decoded.manifest.recordCount
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var files: [String: Data] = [
            indexPath: try encoder.encode(index),
            archivePath: workspaceArchive,
            readmePath: Data(readme(for: index).utf8)
        ]
        for (path, data) in markdown { files["memory/\(path)"] = data }
        let package = try zip(files)
        guard package.count <= maximumPackageBytes else { throw WorkspaceArchiveError.tooLarge }
        return package
    }

    /// Returns the canonical workspace archive for this bundle, or nil when the
    /// selected file is a legacy migration archive rather than a backup bundle.
    public static func workspaceArchive(fromPackage data: Data) throws -> Data? {
        guard data.count >= 4, data.prefix(2) == Data([0x50, 0x4B]) else { return nil }
        guard data.count <= maximumPackageBytes,
              let archive = try? Archive(data: data, accessMode: .read, pathEncoding: nil) else {
            throw WorkspaceBackupError.invalidPackage
        }
        guard let indexEntry = archive[indexPath] else { return nil }
        var entryCount = 0
        var entryPaths = Set<String>()
        for entry in archive {
            guard entryCount < maximumEntryCount,
                  entry.type == .file,
                  entryPaths.insert(entry.path).inserted else {
                throw WorkspaceBackupError.invalidPackage
            }
            entryCount += 1
        }
        guard indexEntry.type == .file,
              indexEntry.uncompressedSize <= 1_000_000 else {
            throw WorkspaceBackupError.invalidPackage
        }
        let indexData = try extract(indexEntry, from: archive, limit: 1_000_000)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let index = try? decoder.decode(BackupPackageIndex.self, from: indexData),
              index.formatVersion == 1,
              index.workspaceArchivePath == archivePath,
              let entry = archive[archivePath],
              entry.type == .file,
              entry.uncompressedSize <= UInt64(WorkspacePortableArchive.maximumCompressedBytes) else {
            throw WorkspaceBackupError.invalidPackage
        }
        let payload = try extract(entry, from: archive, limit: WorkspacePortableArchive.maximumCompressedBytes)
        _ = try WorkspacePortableArchive.decode(payload)
        return payload
    }

    private static func readableDocuments(_ documents: [WorkspaceDocument]) throws -> [String: Data] {
        var result: [String: Data] = [:]
        for document in documents {
            let path = document.path
            guard path.hasSuffix(".md"),
                  !path.hasPrefix("/"),
                  !path.contains("\\"),
                  !path.split(separator: "/").contains(".."),
                  !path.split(separator: "/").contains(".") else {
                throw WorkspaceBackupError.invalidPackage
            }
            result[path] = Data(document.content.utf8)
        }
        return result
    }

    private static func readme(for index: BackupPackageIndex) -> String {
        let date = ISO8601DateFormatter().string(from: index.createdAt)
        let transcriptNote = index.includesConversations ? "聊天记录、活动和任务草稿已包含在 `workspace.zip` 中。" : "聊天记录、活动和任务草稿未包含在 `workspace.zip` 中。"
        let markdownList = index.markdownPaths.isEmpty
            ? "没有可读的 Markdown 记忆文件。"
            : index.markdownPaths.map { "- `memory/\($0)`" }.joined(separator: "\n")
        return """
        # OpenMuse 备份

        - 生成时间：\(date)
        - 结构化记录：\(index.recordCount) 条
        - \(transcriptNote)

        ## 如何读取

        `memory/` 下的 Markdown 是便于阅读的工作区文件副本。完整结构化数据、修订历史、附件和校验清单位于 `workspace.zip` 中；记录以 JSONL 保存，可按其中的 `kind`、`recordID` 和 `payload` 字段读取。将备份交给其他 AI 前，请先检查其中的个人资料，并只分享你允许读取的内容。

        API 密钥、邮箱凭证、模型端点偏好、备份计划/位置、iSH 系统/运行时目录、浏览器 Cookie/缓存，以及本机 AlarmKit 闹钟和计时器不会导出；请在新设备重新配置凭证和备份计划。

        ## Markdown 文件

        \(markdownList)

        ## 恢复

        在 OpenMuse 的“备份与恢复”中选择整个 ZIP。OpenMuse 会验证内层工作区包，再把记录合并到当前工作区；API 密钥不包含在备份中。
        """
    }

    private static func zip(_ files: [String: Data]) throws -> Data {
        let archive = try Archive(data: Data(), accessMode: .create, pathEncoding: nil)
        for (path, contents) in files.sorted(by: { $0.key < $1.key }) {
            try archive.addEntry(
                with: path,
                type: .file,
                uncompressedSize: Int64(contents.count),
                compressionMethod: .deflate
            ) { position, size in
                let lower = Int(position)
                let upper = min(lower + size, contents.count)
                guard lower >= 0, lower <= upper else { throw WorkspaceBackupError.invalidPackage }
                return contents.subdata(in: lower..<upper)
            }
        }
        guard let data = archive.data, data.count <= maximumPackageBytes else {
            throw WorkspaceArchiveError.tooLarge
        }
        return data
    }

    private static func extract(_ entry: Entry, from archive: Archive, limit: Int) throws -> Data {
        guard entry.uncompressedSize <= UInt64(limit) else { throw WorkspaceBackupError.invalidPackage }
        var data = Data()
        data.reserveCapacity(Int(entry.uncompressedSize))
        _ = try archive.extract(entry, bufferSize: 16 * 1024) { chunk in
            guard data.count <= limit - chunk.count else { throw WorkspaceBackupError.invalidPackage }
            data.append(chunk)
        }
        return data
    }

    private struct BackupPackageIndex: Codable {
        let formatVersion: Int
        let createdAt: Date
        let workspaceArchivePath: String
        let markdownPaths: [String]
        let includesConversations: Bool
        let recordCount: Int
    }
}

public struct WorkspaceBackupSchedule: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var hour: Int
    public var minute: Int
    public var retentionCount: Int

    public init(enabled: Bool = false, hour: Int = 21, minute: Int = 0, retentionCount: Int = 7) {
        self.enabled = enabled
        self.hour = min(max(hour, 0), 23)
        self.minute = min(max(minute, 0), 59)
        self.retentionCount = min(max(retentionCount, 1), 30)
    }

    public func nextRun(after date: Date, calendar: Calendar = .current) -> Date? {
        guard enabled else { return nil }
        var matching = DateComponents()
        matching.hour = hour
        matching.minute = minute
        matching.second = 0
        return calendar.nextDate(after: date, matching: matching, matchingPolicy: .nextTime, direction: .forward)
    }

    public func isDue(at date: Date, lastCompletedAt: Date?, calendar: Calendar = .current) -> Bool {
        guard enabled,
              let scheduled = calendar.date(
                bySettingHour: hour,
                minute: minute,
                second: 0,
                of: date,
                matchingPolicy: .nextTime
              ),
              date >= scheduled else { return false }
        return lastCompletedAt.map { $0 < scheduled } ?? true
    }
}

public enum WorkspaceBackupKind: Equatable, Sendable {
    /// A user-requested export is a durable file and is never removed by retention.
    case manualExport
    /// A scheduled snapshot participates in the configured retention policy.
    case scheduled

    fileprivate var filenamePrefix: String {
        switch self {
        case .manualExport: "OpenMuse-Export-"
        case .scheduled: "OpenMuse-ScheduledBackup-"
        }
    }
}

public enum WorkspaceBackupPreferences {
    private static let scheduleKey = "openmuse.backup.schedule.v1"
    private static let bookmarkKey = "openmuse.backup.folder-bookmark.v1"
    private static let folderNameKey = "openmuse.backup.folder-name.v1"
    private static let lastCompletedKey = "openmuse.backup.last-completed.v1"
    private static let lastResultKey = "openmuse.backup.last-result.v1"

    public static func loadSchedule(defaults: UserDefaults = .standard) -> WorkspaceBackupSchedule {
        guard let data = defaults.data(forKey: scheduleKey),
              let schedule = try? JSONDecoder().decode(WorkspaceBackupSchedule.self, from: data) else {
            return WorkspaceBackupSchedule()
        }
        return schedule
    }

    public static func saveSchedule(_ schedule: WorkspaceBackupSchedule, defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(schedule) else { return }
        defaults.set(data, forKey: scheduleKey)
    }

    public static var selectedFolderName: String? {
        UserDefaults.standard.string(forKey: folderNameKey)
    }

    public static var lastCompletedAt: Date? {
        UserDefaults.standard.object(forKey: lastCompletedKey) as? Date
    }

    public static var lastResult: String? {
        UserDefaults.standard.string(forKey: lastResultKey)
    }

    public static func saveFolder(_ url: URL, defaults: UserDefaults = .standard) throws {
        var options: URL.BookmarkCreationOptions = []
        #if os(macOS)
        options.insert(.withSecurityScope)
        #endif
        let bookmark = try url.bookmarkData(options: options, includingResourceValuesForKeys: nil, relativeTo: nil)
        defaults.set(bookmark, forKey: bookmarkKey)
        defaults.set(url.lastPathComponent, forKey: folderNameKey)
    }

    public static func resolveFolder(defaults: UserDefaults = .standard) throws -> URL {
        guard let bookmark = defaults.data(forKey: bookmarkKey) else {
            throw WorkspaceBackupError.destinationNotSelected
        }
        var stale = false
        var options: URL.BookmarkResolutionOptions = []
        #if os(macOS)
        options.insert(.withSecurityScope)
        #endif
        guard let url = try? URL(
            resolvingBookmarkData: bookmark,
            options: options,
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) else {
            throw WorkspaceBackupError.destinationUnavailable
        }
        if stale { try? saveFolder(url, defaults: defaults) }
        return url
    }

    public static func recordCompleted(_ date: Date, result: String = "备份完成", defaults: UserDefaults = .standard) {
        defaults.set(date, forKey: lastCompletedKey)
        defaults.set(result, forKey: lastResultKey)
    }

    public static func recordFailure(_ result: String, defaults: UserDefaults = .standard) {
        defaults.set(result, forKey: lastResultKey)
    }
}

public enum WorkspaceBackupStorage {
    public static func write(
        _ package: Data,
        to folder: URL,
        date: Date = .now,
        retentionCount: Int = 7,
        kind: WorkspaceBackupKind = .manualExport
    ) throws -> URL {
        let hasAccess = folder.startAccessingSecurityScopedResource()
        defer { if hasAccess { folder.stopAccessingSecurityScopedResource() } }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw WorkspaceBackupError.destinationUnavailable
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let filename = "\(kind.filenamePrefix)\(formatter.string(from: date))-\(UUID().uuidString.prefix(8)).zip"
        let destination = folder.appendingPathComponent(filename, isDirectory: false)
        var coordinationError: NSError?
        var writeError: Error?
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: destination, options: [], error: &coordinationError) { coordinatedURL in
            do { try package.write(to: coordinatedURL, options: .atomic) }
            catch { writeError = error }
        }
        if let coordinationError { throw coordinationError }
        if let writeError { throw writeError }
        if kind == .scheduled {
            pruneBackups(in: folder, keeping: min(max(retentionCount, 1), 30))
        }
        return destination
    }

    public static func pruneBackups(in folder: URL, keeping count: Int) {
        let hasAccess = folder.startAccessingSecurityScopedResource()
        defer { if hasAccess { folder.stopAccessingSecurityScopedResource() } }
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        let backups = contents
            .filter { $0.lastPathComponent.hasPrefix(WorkspaceBackupKind.scheduled.filenamePrefix) && $0.pathExtension == "zip" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
        for oldURL in backups.dropFirst(max(count, 1)) {
            var coordinationError: NSError?
            NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: oldURL, options: .forDeleting, error: &coordinationError) { url in
                try? FileManager.default.removeItem(at: url)
            }
        }
    }
}
