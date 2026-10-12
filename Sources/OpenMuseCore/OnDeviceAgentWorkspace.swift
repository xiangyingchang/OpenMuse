import CryptoKit
import Foundation

public enum OnDeviceAgentWorkspaceError: Error, LocalizedError, Equatable {
    case invalidSession
    case invalidPath
    case unsupportedFileType
    case notFound
    case notRegularFile
    case tooManyFiles
    case fileTooLarge
    case workspaceTooLarge
    case invalidText

    public var errorDescription: String? {
        switch self {
        case .invalidSession: "当前会话工作区无效。"
        case .invalidPath: "工作区路径无效；只能使用相对路径。"
        case .unsupportedFileType: "本机工作区只支持 Markdown、文本、JSON 和 CSV 文件。"
        case .notFound: "本机工作区中找不到这个文件。"
        case .notRegularFile: "工作区路径必须指向普通文件。"
        case .tooManyFiles: "当前对话工作区文件过多；请先整理后再继续。"
        case .fileTooLarge: "工作区单个文件超过 256 KB 上限。"
        case .workspaceTooLarge: "当前任务工作区达到 16 MB 上限；请先整理中间文件。"
        case .invalidText: "工作区文件必须是有效的 UTF-8 文本。"
        }
    }
}

public struct OnDeviceAgentWorkspaceWritePreview: Equatable, Sendable {
    public let path: String
    public let byteCount: Int
    public let replacesExistingFile: Bool
    public let existingFileByteCount: Int
    public let existingFileSHA256: String?

    public init(path: String, byteCount: Int, replacesExistingFile: Bool, existingFileByteCount: Int, existingFileSHA256: String?) {
        self.path = path
        self.byteCount = byteCount
        self.replacesExistingFile = replacesExistingFile
        self.existingFileByteCount = existingFileByteCount
        self.existingFileSHA256 = existingFileSHA256
    }
}

/// A persistent conversation-scoped workspace for the on-device agent.
/// It is deliberately separate from SQLite-backed memory and shared documents.
public struct OnDeviceAgentWorkspace: Sendable {
    public static let maximumFileBytes = 256 * 1024
    public static let maximumListedFiles = 80
    public static let maximumWorkspaceBytes = 16 * 1024 * 1024
    private static let supportedExtensions: Set<String> = ["md", "txt", "json", "csv"]
    private static let legacyMigrationMarker = ".legacy-cache-migrated-v1"

    public static func isSafePortablePath(_ path: String) -> Bool {
        guard !path.isEmpty, path.utf8.count <= 240, !path.hasPrefix("/"), !path.contains("\\"),
              !path.contains(":"), !path.contains("\0") else { return false }
        let components = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !components.isEmpty,
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && !$0.hasPrefix(".") && $0.count <= 80 }),
              let ext = components.last?.split(separator: ".").last.map(String.init)?.lowercased() else { return false }
        return supportedExtensions.contains(ext)
    }

    public let rootURL: URL
    private var fileManager: FileManager { .default }

    public init(rootURL: URL, conversationID: String, legacyCacheRootURL: URL? = nil) throws {
        guard !conversationID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OnDeviceAgentWorkspaceError.invalidSession
        }
        let fileManager = FileManager.default
        let canonicalRoot = rootURL.standardizedFileURL
        try fileManager.createDirectory(at: canonicalRoot, withIntermediateDirectories: true)
        try Self.requireDirectory(canonicalRoot, fileManager: fileManager)

        let sessionRoot = Self.sessionURL(rootURL: canonicalRoot, conversationID: conversationID)
        try fileManager.createDirectory(at: sessionRoot, withIntermediateDirectories: true)
        try Self.requireDirectory(sessionRoot, fileManager: fileManager)
        self.rootURL = sessionRoot.standardizedFileURL
        if let legacyCacheRootURL {
            try migrateLegacyCacheIfNeeded(from: legacyCacheRootURL.standardizedFileURL, conversationID: conversationID, fileManager: fileManager)
        }
        try protectWorkspaceDirectories(fileManager: fileManager)
        try touchSession()
    }

    public static func applicationSupportRootURL(fileManager: FileManager = .default) throws -> URL {
        let support = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return support.appendingPathComponent("OpenMuse", isDirectory: true)
            .appendingPathComponent("AgentWorkspaces", isDirectory: true)
    }

    /// The cache path used by earlier builds. It is retained only as a
    /// one-time migration source; new workspaces must live in Application Support.
    public static func legacyApplicationCacheRootURL(fileManager: FileManager = .default) throws -> URL {
        let cache = try fileManager.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return cache.appendingPathComponent("OpenMuse", isDirectory: true)
            .appendingPathComponent("AgentSessions", isDirectory: true)
    }

    public static func sessionDirectoryURL(rootURL: URL, conversationID: String) throws -> URL {
        guard !conversationID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              conversationID.count <= 200 else { throw OnDeviceAgentWorkspaceError.invalidSession }
        return sessionURL(rootURL: rootURL.standardizedFileURL, conversationID: conversationID)
    }

    public func listFiles() throws -> [String] {
        var result: [String] = []
        try collectFiles(in: rootURL, relativeTo: rootURL, into: &result)
        guard result.count <= Self.maximumListedFiles else { throw OnDeviceAgentWorkspaceError.tooManyFiles }
        try touchSession()
        return result.sorted()
    }

    public func readFile(path: String, maximumCharacters: Int = 12_000) throws -> String {
        guard let text = String(data: try readFileData(path: path), encoding: .utf8) else {
            throw OnDeviceAgentWorkspaceError.invalidText
        }
        return String(text.prefix(max(0, maximumCharacters)))
    }

    public func readFileData(path: String) throws -> Data {
        let url = try validatedURL(path: path, createParentDirectories: false)
        guard fileManager.fileExists(atPath: url.path) else { throw OnDeviceAgentWorkspaceError.notFound }
        try Self.requireRegularFile(url, fileManager: fileManager)
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        guard ((attributes[.size] as? NSNumber)?.intValue ?? 0) <= Self.maximumFileBytes else {
            throw OnDeviceAgentWorkspaceError.fileTooLarge
        }
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        guard String(data: data, encoding: .utf8) != nil else { throw OnDeviceAgentWorkspaceError.invalidText }
        try touchSession()
        return data
    }

    /// Validates a proposed write without creating directories or changing any file.
    /// The returned fingerprint lets the host reject a stale approval if the target changes.
    public func preflightWrite(path: String, content: String) throws -> OnDeviceAgentWorkspaceWritePreview {
        let data = Data(content.utf8)
        guard data.count <= Self.maximumFileBytes else { throw OnDeviceAgentWorkspaceError.fileTooLarge }
        guard !content.unicodeScalars.contains(where: { $0.value == 0 }) else {
            throw OnDeviceAgentWorkspaceError.invalidText
        }

        let url = try preflightURL(path: path)
        let currentFiles = try listFilesWithoutTouching()
        let replacesExistingFile = fileManager.fileExists(atPath: url.path)
        guard replacesExistingFile && currentFiles.contains(path) || currentFiles.count < Self.maximumListedFiles else {
            throw OnDeviceAgentWorkspaceError.tooManyFiles
        }
        let existingData: Data?
        if replacesExistingFile {
            try Self.requireRegularFile(url, fileManager: fileManager)
            let existingAttributes = try fileManager.attributesOfItem(atPath: url.path)
            let existingBytes = (existingAttributes[.size] as? NSNumber)?.intValue ?? 0
            guard existingBytes <= Self.maximumFileBytes else { throw OnDeviceAgentWorkspaceError.fileTooLarge }
            existingData = try Data(contentsOf: url, options: [.mappedIfSafe])
            guard existingData?.count == existingBytes else { throw OnDeviceAgentWorkspaceError.invalidText }
            guard String(data: existingData ?? Data(), encoding: .utf8) != nil else { throw OnDeviceAgentWorkspaceError.invalidText }
        } else {
            existingData = nil
        }

        let workspaceBytes = try currentFiles.reduce(into: 0) { total, existingPath in
            let existingURL = try validatedURL(path: existingPath, createParentDirectories: false)
            let attributes = try fileManager.attributesOfItem(atPath: existingURL.path)
            total += (attributes[.size] as? NSNumber)?.intValue ?? 0
        }
        let existingByteCount = existingData?.count ?? 0
        guard workspaceBytes - existingByteCount + data.count <= Self.maximumWorkspaceBytes else {
            throw OnDeviceAgentWorkspaceError.workspaceTooLarge
        }

        let digest = existingData.map { value in
            SHA256.hash(data: value).map { String(format: "%02x", $0) }.joined()
        }
        return OnDeviceAgentWorkspaceWritePreview(
            path: path,
            byteCount: data.count,
            replacesExistingFile: replacesExistingFile,
            existingFileByteCount: existingByteCount,
            existingFileSHA256: digest
        )
    }

    @discardableResult
    public func writeFile(path: String, content: String) throws -> Int {
        let data = Data(content.utf8)
        guard data.count <= Self.maximumFileBytes else { throw OnDeviceAgentWorkspaceError.fileTooLarge }
        guard !content.unicodeScalars.contains(where: { $0.value == 0 }) else {
            throw OnDeviceAgentWorkspaceError.invalidText
        }
        let url = try validatedURL(path: path, createParentDirectories: true)
        if fileManager.fileExists(atPath: url.path) {
            try Self.requireRegularFile(url, fileManager: fileManager)
        }
        let existingFiles = try listFilesWithoutTouching()
        guard existingFiles.contains(path) || existingFiles.count < Self.maximumListedFiles else {
            throw OnDeviceAgentWorkspaceError.tooManyFiles
        }
        let existingSize = fileManager.fileExists(atPath: url.path)
            ? ((try fileManager.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0)
            : 0
        let workspaceSize = try existingFiles.reduce(into: 0) { total, existingPath in
            let existingURL = try validatedURL(path: existingPath, createParentDirectories: false)
            let attributes = try fileManager.attributesOfItem(atPath: existingURL.path)
            total += (attributes[.size] as? NSNumber)?.intValue ?? 0
        }
        guard workspaceSize - existingSize + data.count <= Self.maximumWorkspaceBytes else {
            throw OnDeviceAgentWorkspaceError.workspaceTooLarge
        }
        try data.write(to: url, options: .atomic)
        #if os(iOS)
        try? fileManager.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: url.path)
        #endif
        try touchSession()
        return data.count
    }

    private func validatedURL(path: String, createParentDirectories: Bool) throws -> URL {
        guard !path.isEmpty, path.utf8.count <= 240, !path.hasPrefix("/"), !path.contains("\\"),
              !path.contains(":"), !path.contains("\0") else { throw OnDeviceAgentWorkspaceError.invalidPath }
        let components = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !components.isEmpty,
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && !$0.hasPrefix(".") && $0.count <= 80 }) else {
            throw OnDeviceAgentWorkspaceError.invalidPath
        }
        guard let ext = components.last?.split(separator: ".").last.map(String.init)?.lowercased(),
              Self.supportedExtensions.contains(ext) else { throw OnDeviceAgentWorkspaceError.unsupportedFileType }

        var parent = rootURL
        for component in components.dropLast() {
            parent.appendPathComponent(component, isDirectory: true)
            if fileManager.fileExists(atPath: parent.path) {
                try Self.requireDirectory(parent, fileManager: fileManager)
            } else if createParentDirectories {
                try fileManager.createDirectory(at: parent, withIntermediateDirectories: false)
                try Self.requireDirectory(parent, fileManager: fileManager)
            } else {
                throw OnDeviceAgentWorkspaceError.notFound
            }
        }
        let result = parent.appendingPathComponent(components.last!, isDirectory: false).standardizedFileURL
        guard result.path.hasPrefix(rootURL.path + "/") else { throw OnDeviceAgentWorkspaceError.invalidPath }
        if fileManager.fileExists(atPath: result.path) { try Self.requireRegularFile(result, fileManager: fileManager) }
        return result
    }

    private func preflightURL(path: String) throws -> URL {
        guard !path.isEmpty, path.utf8.count <= 240, !path.hasPrefix("/"), !path.contains("\\"),
              !path.contains(":"), !path.contains("\0") else { throw OnDeviceAgentWorkspaceError.invalidPath }
        let components = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !components.isEmpty,
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && !$0.hasPrefix(".") && $0.count <= 80 }) else {
            throw OnDeviceAgentWorkspaceError.invalidPath
        }
        guard let ext = components.last?.split(separator: ".").last.map(String.init)?.lowercased(),
              Self.supportedExtensions.contains(ext) else { throw OnDeviceAgentWorkspaceError.unsupportedFileType }

        var parent = rootURL
        for component in components.dropLast() {
            parent.appendPathComponent(component, isDirectory: true)
            if fileManager.fileExists(atPath: parent.path) {
                try Self.requireDirectory(parent, fileManager: fileManager)
            }
        }
        let result = parent.appendingPathComponent(components.last!, isDirectory: false).standardizedFileURL
        guard result.path.hasPrefix(rootURL.path + "/") else { throw OnDeviceAgentWorkspaceError.invalidPath }
        if fileManager.fileExists(atPath: result.path) { try Self.requireRegularFile(result, fileManager: fileManager) }
        return result
    }

    private func collectFiles(in directory: URL, relativeTo root: URL, into result: inout [String]) throws {
        for child in try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let values = try child.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey])
            if values.isSymbolicLink == true { continue }
            if values.isDirectory == true {
                try collectFiles(in: child, relativeTo: root, into: &result)
            } else if values.isRegularFile == true,
                      Self.supportedExtensions.contains(child.pathExtension.lowercased()) {
                let rootComponents = root.standardizedFileURL.pathComponents
                let childComponents = child.standardizedFileURL.pathComponents
                guard childComponents.count > rootComponents.count,
                      Array(childComponents.prefix(rootComponents.count)) == rootComponents else {
                    throw OnDeviceAgentWorkspaceError.invalidPath
                }
                result.append(childComponents.dropFirst(rootComponents.count).joined(separator: "/"))
                if result.count > Self.maximumListedFiles { throw OnDeviceAgentWorkspaceError.tooManyFiles }
            }
        }
    }

    private func listFilesWithoutTouching() throws -> [String] {
        var result: [String] = []
        try collectFiles(in: rootURL, relativeTo: rootURL, into: &result)
        return result
    }

    private func touchSession() throws {
        try fileManager.setAttributes([.modificationDate: Date()], ofItemAtPath: rootURL.path)
    }

    private func migrateLegacyCacheIfNeeded(from legacyRoot: URL, conversationID: String, fileManager: FileManager) throws {
        let marker = rootURL.appendingPathComponent(Self.legacyMigrationMarker)
        guard !fileManager.fileExists(atPath: marker.path) else { return }
        let legacySession = Self.sessionURL(rootURL: legacyRoot, conversationID: conversationID)
        guard fileManager.fileExists(atPath: legacySession.path) else {
            try Data("done".utf8).write(to: marker, options: .atomic)
            return
        }
        try Self.requireDirectory(legacySession, fileManager: fileManager)
        let legacy = try OnDeviceAgentWorkspace(rootURL: legacyRoot, conversationID: conversationID)
        let existing = Set(try listFilesWithoutTouching())
        for path in try legacy.listFiles() where !existing.contains(path) {
            try writeFile(path: path, content: legacy.readFile(path: path, maximumCharacters: Int.max))
        }
        try Data("done".utf8).write(to: marker, options: .atomic)
    }

    private func protectWorkspaceDirectories(fileManager: FileManager) throws {
        #if os(iOS)
        let protection = FileProtectionType.completeUntilFirstUserAuthentication
        try? fileManager.setAttributes([.protectionKey: protection], ofItemAtPath: rootURL.deletingLastPathComponent().path)
        try? fileManager.setAttributes([.protectionKey: protection], ofItemAtPath: rootURL.path)
        #endif
    }

    private static func sessionURL(rootURL: URL, conversationID: String) -> URL {
        let digest = SHA256.hash(data: Data(conversationID.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return rootURL.appendingPathComponent(String(digest.prefix(32)), isDirectory: true)
    }

    private static func requireDirectory(_ url: URL, fileManager: FileManager) throws {
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeDirectory else {
            throw OnDeviceAgentWorkspaceError.invalidPath
        }
    }

    private static func requireRegularFile(_ url: URL, fileManager: FileManager) throws {
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular else {
            throw OnDeviceAgentWorkspaceError.notRegularFile
        }
    }
}

public struct AgentWorkspaceRestoreReport: Equatable, Sendable {
    public let importedFiles: Int
    public let preservedConflicts: Int
}

/// Exports and restores conversation workspaces without putting them into the
/// synchronized memory database. Imports stage each conversation and swap it
/// into place only after all files for that conversation pass the normal limits.
public enum AgentWorkspaceArchiveManager {
    public static func snapshotExisting(
        rootURL: URL,
        conversationIDs: [String],
        fileManager: FileManager = .default
    ) throws -> [WorkspaceAgentFile] {
        let root = rootURL.standardizedFileURL
        guard fileManager.fileExists(atPath: root.path) else { return [] }
        try requireDirectory(root, fileManager: fileManager)

        var result: [WorkspaceAgentFile] = []
        for conversationID in Set(conversationIDs).sorted() {
            let sessionURL = try OnDeviceAgentWorkspace.sessionDirectoryURL(rootURL: root, conversationID: conversationID)
            guard fileManager.fileExists(atPath: sessionURL.path) else { continue }
            try requireDirectory(sessionURL, fileManager: fileManager)
            let workspace = try OnDeviceAgentWorkspace(rootURL: root, conversationID: conversationID)
            let paths = try workspace.listFiles()
            guard paths.count <= OnDeviceAgentWorkspace.maximumListedFiles else {
                throw OnDeviceAgentWorkspaceError.tooManyFiles
            }
            var conversationBytes = 0
            for path in paths {
                let data = try workspace.readFileData(path: path)
                let file = WorkspaceAgentFile(conversationID: conversationID, path: path, data: data)
                guard file.isValid else { throw WorkspaceArchiveError.invalidAgentWorkspace }
                conversationBytes += data.count
                guard conversationBytes <= OnDeviceAgentWorkspace.maximumWorkspaceBytes else {
                    throw OnDeviceAgentWorkspaceError.workspaceTooLarge
                }
                result.append(file)
            }
        }
        return result.sorted { ($0.conversationID, $0.path) < ($1.conversationID, $1.path) }
    }

    public static func restore(
        _ files: [WorkspaceAgentFile],
        rootURL: URL,
        exportID: String,
        fileManager: FileManager = .default
    ) throws -> AgentWorkspaceRestoreReport {
        guard files.allSatisfy(\.isValid), !exportID.isEmpty else {
            throw WorkspaceArchiveError.invalidAgentWorkspace
        }
        let root = rootURL.standardizedFileURL
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        try requireDirectory(root, fileManager: fileManager)

        let exportDigest = SHA256.hash(data: Data(exportID.utf8)).map { String(format: "%02x", $0) }.joined()
        var importedCount = 0
        var conflictCount = 0
        for (conversationID, archivedFiles) in Dictionary(grouping: files, by: \.conversationID).sorted(by: { $0.key < $1.key }) {
            guard Set(archivedFiles.map(\.path)).count == archivedFiles.count,
                  archivedFiles.count <= OnDeviceAgentWorkspace.maximumListedFiles,
                  archivedFiles.reduce(0, { $0 + $1.byteCount }) <= OnDeviceAgentWorkspace.maximumWorkspaceBytes else {
                throw WorkspaceArchiveError.invalidAgentWorkspace
            }
            let targetURL = try OnDeviceAgentWorkspace.sessionDirectoryURL(rootURL: root, conversationID: conversationID)
            let targetExists = fileManager.fileExists(atPath: targetURL.path)
            if targetExists { try requireDirectory(targetURL, fileManager: fileManager) }

            let stageRoot = root.appendingPathComponent(".workspace-import-\(UUID().uuidString)", isDirectory: true)
            defer { try? fileManager.removeItem(at: stageRoot) }
            let staged = try OnDeviceAgentWorkspace(rootURL: stageRoot, conversationID: conversationID)
            let current = targetExists ? try OnDeviceAgentWorkspace(rootURL: root, conversationID: conversationID) : nil
            var stagedFileCount = 0
            var stagedByteCount = 0

            if let current {
                for path in try current.listFiles() {
                    let data = try current.readFileData(path: path)
                    guard let text = String(data: data, encoding: .utf8) else { throw OnDeviceAgentWorkspaceError.invalidText }
                    try staged.writeFile(path: path, content: text)
                    stagedFileCount += 1
                    stagedByteCount += data.count
                }
                let legacyMarker = current.rootURL.appendingPathComponent(".legacy-cache-migrated-v1")
                if fileManager.fileExists(atPath: legacyMarker.path) {
                    try fileManager.copyItem(at: legacyMarker, to: staged.rootURL.appendingPathComponent(".legacy-cache-migrated-v1"))
                }
            }

            var newFiles = 0
            var conversationConflicts = 0
            for archived in archivedFiles.sorted(by: { $0.path < $1.path }) {
                let importedText = String(data: archived.data, encoding: .utf8)!
                let existingData = try? current?.readFileData(path: archived.path)
                if existingData == archived.data { continue }

                let destinationPath: String
                let isConflictCopy: Bool
                if existingData == nil {
                    destinationPath = archived.path
                    isConflictCopy = false
                } else {
                    destinationPath = try conflictPath(
                        for: archived,
                        exportDigest: String(exportDigest.prefix(16)),
                        in: staged
                    )
                    isConflictCopy = true
                }
                if let existingStaged = try? staged.readFileData(path: destinationPath), existingStaged == archived.data {
                    continue
                }
                try staged.writeFile(path: destinationPath, content: importedText)
                if isConflictCopy { conversationConflicts += 1 }
                stagedFileCount += 1
                stagedByteCount += archived.byteCount
                newFiles += 1
            }

            guard stagedFileCount <= OnDeviceAgentWorkspace.maximumListedFiles,
                  stagedByteCount <= OnDeviceAgentWorkspace.maximumWorkspaceBytes else {
                throw OnDeviceAgentWorkspaceError.workspaceTooLarge
            }
            guard newFiles > 0 else { continue }

            let backupURL = root.appendingPathComponent(".workspace-backup-\(UUID().uuidString)", isDirectory: true)
            if targetExists { try fileManager.moveItem(at: targetURL, to: backupURL) }
            do {
                try fileManager.moveItem(at: staged.rootURL, to: targetURL)
                _ = try OnDeviceAgentWorkspace(rootURL: root, conversationID: conversationID)
                if targetExists { try? fileManager.removeItem(at: backupURL) }
            } catch {
                if fileManager.fileExists(atPath: targetURL.path) {
                    try? fileManager.removeItem(at: targetURL)
                }
                if targetExists, fileManager.fileExists(atPath: backupURL.path) {
                    try? fileManager.moveItem(at: backupURL, to: targetURL)
                }
                throw error
            }
            importedCount += newFiles
            conflictCount += conversationConflicts
        }
        return AgentWorkspaceRestoreReport(importedFiles: importedCount, preservedConflicts: conflictCount)
    }

    private static func conflictPath(
        for file: WorkspaceAgentFile,
        exportDigest: String,
        in workspace: OnDeviceAgentWorkspace
    ) throws -> String {
        let originalName = file.path.split(separator: "/").last.map(String.init) ?? "imported.txt"
        let extensionName = URL(fileURLWithPath: originalName).pathExtension
        let stem = extensionName.isEmpty ? originalName : String(originalName.dropLast(extensionName.count + 1))
        let pathDigest = SHA256.hash(data: Data(file.path.utf8)).map { String(format: "%02x", $0) }.joined()
        let shortStem = String(stem.prefix(48))
        let suffix = String(pathDigest.prefix(12))
        let conflictName = extensionName.isEmpty
            ? "\(shortStem)-\(suffix).txt"
            : "\(shortStem)-\(suffix).\(extensionName)"
        let firstChoice = "_openmuse_import_conflicts/\(exportDigest)/\(conflictName)"
        if (try? workspace.readFileData(path: firstChoice)) == file.data { return firstChoice }
        if (try? workspace.readFileData(path: firstChoice)) == nil { return firstChoice }

        let secondChoice = "_openmuse_import_conflicts/\(exportDigest)/\(shortStem.prefix(32))-\(suffix)-\(String(file.sha256.prefix(8))).\(extensionName.isEmpty ? "txt" : extensionName)"
        if (try? workspace.readFileData(path: secondChoice)) == file.data { return secondChoice }
        if (try? workspace.readFileData(path: secondChoice)) == nil { return secondChoice }

        let unique = "_openmuse_import_conflicts/\(exportDigest)/\(UUID().uuidString)-\(conflictName)"
        guard OnDeviceAgentWorkspace.isSafePortablePath(unique) else { throw WorkspaceArchiveError.invalidAgentWorkspace }
        return unique
    }

    private static func requireDirectory(_ url: URL, fileManager: FileManager) throws {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              attributes[.type] as? FileAttributeType == .typeDirectory else {
            throw OnDeviceAgentWorkspaceError.invalidPath
        }
    }
}
