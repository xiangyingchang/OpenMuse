import CryptoKit
import Foundation
import PDFKit
import Vision

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

public struct AttachmentRecord: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var conversationID: String
    public var messageID: String
    public var displayName: String
    public var mediaType: String
    public var byteCount: Int
    public var sha256: String
    public var createdAt: Date

    public init(id: String = UUID().uuidString, conversationID: String, messageID: String, displayName: String, mediaType: String, byteCount: Int, sha256: String, createdAt: Date = .now) {
        self.id = id
        self.conversationID = conversationID
        self.messageID = messageID
        self.displayName = displayName
        self.mediaType = mediaType
        self.byteCount = byteCount
        self.sha256 = sha256
        self.createdAt = createdAt
    }

    public var isValid: Bool {
        Self.isSafeIdentifier(id) && !conversationID.isEmpty && conversationID.count <= 200 &&
        !messageID.isEmpty && messageID.count <= 200 && !displayName.isEmpty && displayName.count <= 240 &&
        Self.allowedMediaTypes.contains(mediaType) && byteCount > 0 && byteCount <= AttachmentStore.maximumFileBytes &&
        sha256.count == 64 && sha256.allSatisfy(\.isHexDigit)
    }

    public static let allowedMediaTypes: Set<String> = ["text/plain", "text/markdown", "application/pdf"]

    public static func isSafeIdentifier(_ value: String) -> Bool {
        !value.isEmpty && value.count <= 100 && value.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
    }
}

public struct PendingAttachment: Identifiable, Equatable, Sendable {
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

    public var byteCount: Int { data.count }
}

public enum AttachmentStoreError: Error, LocalizedError, Equatable {
    case unsupportedType
    case tooLarge
    case invalidText
    case missing
    case checksumMismatch
    case invalidRecord

    public var errorDescription: String? {
        switch self {
        case .unsupportedType: "目前支持 TXT、Markdown 和 PDF 文件。"
        case .tooLarge: "单个附件不能超过 10 MB。"
        case .invalidText: "文本附件不是有效的 UTF-8 文件。"
        case .missing: "附件文件已不存在于这台设备。"
        case .checksumMismatch: "附件校验失败，文件没有交给模型。"
        case .invalidRecord: "附件记录无效。"
        }
    }
}

/// Stores imported files under opaque IDs and verifies every read against the saved digest.
public final class AttachmentStore: @unchecked Sendable {
    public static let maximumFileBytes = 10 * 1024 * 1024
    public static let maximumAttachmentsPerMessage = 5
    public static let maximumExtractedTextBytesPerAttachment = 20_000
    public static let maximumExtractedTextBytesPerTurn = 20_000
    public static let maximumPDFPagesForOCR = 20
    private let rootURL: URL
    private let lock = NSRecursiveLock()

    public init(rootURL: URL) throws {
        self.rootURL = rootURL
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    public func importData(
        _ data: Data,
        displayName: String,
        mediaType: String,
        conversationID: String,
        messageID: String,
        id: String = UUID().uuidString
    ) throws -> AttachmentRecord {
        guard AttachmentRecord.allowedMediaTypes.contains(mediaType) else { throw AttachmentStoreError.unsupportedType }
        guard !data.isEmpty, data.count <= Self.maximumFileBytes else { throw AttachmentStoreError.tooLarge }
        try Self.validate(data: data, mediaType: mediaType)
        let safeName = Self.safeDisplayName(displayName)
        let record = AttachmentRecord(
            id: id, conversationID: conversationID, messageID: messageID, displayName: safeName,
            mediaType: mediaType, byteCount: data.count, sha256: Self.sha256(data)
        )
        guard record.isValid else { throw AttachmentStoreError.invalidRecord }
        lock.lock(); defer { lock.unlock() }
        if FileManager.default.fileExists(atPath: fileURL(id: id).path) {
            guard (try? self.data(for: record)) == data else { throw AttachmentStoreError.checksumMismatch }
            return record
        }
        try data.write(to: fileURL(id: id), options: .atomic)
        return record
    }

    public func importFile(
        at sourceURL: URL,
        mediaType: String,
        conversationID: String,
        messageID: String
    ) throws -> (record: AttachmentRecord, extractedText: String) {
        guard AttachmentRecord.allowedMediaTypes.contains(mediaType) else { throw AttachmentStoreError.unsupportedType }
        let accessing = sourceURL.startAccessingSecurityScopedResource()
        defer { if accessing { sourceURL.stopAccessingSecurityScopedResource() } }
        try Self.validateFileSize(at: sourceURL)
        let data = try Data(contentsOf: sourceURL, options: [.mappedIfSafe])
        let extractedText = try Self.extractText(from: data, mediaType: mediaType)
        let record = try importData(
            data, displayName: sourceURL.lastPathComponent, mediaType: mediaType,
            conversationID: conversationID, messageID: messageID
        )
        return (record, extractedText)
    }

    public static func prepareFile(at sourceURL: URL, mediaType: String) throws -> PendingAttachment {
        guard AttachmentRecord.allowedMediaTypes.contains(mediaType) else { throw AttachmentStoreError.unsupportedType }
        let accessing = sourceURL.startAccessingSecurityScopedResource()
        defer { if accessing { sourceURL.stopAccessingSecurityScopedResource() } }
        try validateFileSize(at: sourceURL)
        let data = try Data(contentsOf: sourceURL, options: [.mappedIfSafe])
        guard !data.isEmpty, data.count <= maximumFileBytes else { throw AttachmentStoreError.tooLarge }
        try validate(data: data, mediaType: mediaType)
        return PendingAttachment(displayName: safeDisplayName(sourceURL.lastPathComponent), mediaType: mediaType, data: data)
    }

    public func data(for record: AttachmentRecord) throws -> Data {
        guard record.isValid else { throw AttachmentStoreError.invalidRecord }
        lock.lock(); defer { lock.unlock() }
        let url = fileURL(id: record.id)
        guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) else { throw AttachmentStoreError.missing }
        guard data.count == record.byteCount, Self.sha256(data) == record.sha256 else { throw AttachmentStoreError.checksumMismatch }
        return data
    }

    public func url(for record: AttachmentRecord) throws -> URL {
        guard record.isValid else { throw AttachmentStoreError.invalidRecord }
        lock.lock(); defer { lock.unlock() }
        let url = fileURL(id: record.id)
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
              values.isRegularFile == true, values.fileSize == record.byteCount else { throw AttachmentStoreError.missing }
        return url
    }

    public func contains(_ record: AttachmentRecord) -> Bool {
        (try? data(for: record)) != nil
    }

    public func remove(id: String) throws {
        guard AttachmentRecord.isSafeIdentifier(id) else { throw AttachmentStoreError.invalidRecord }
        lock.lock(); defer { lock.unlock() }
        let url = fileURL(id: id)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }

    public func removeOrphanedFiles(keeping referencedIDs: Set<String>) throws {
        lock.lock(); defer { lock.unlock() }
        let urls = try FileManager.default.contentsOfDirectory(
            at: rootURL, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]
        )
        for url in urls {
            let id = url.lastPathComponent
            guard AttachmentRecord.isSafeIdentifier(id), !referencedIDs.contains(id) else { continue }
            try FileManager.default.removeItem(at: url)
        }
    }

    public func writeSyncedData(_ data: Data, matching record: AttachmentRecord) throws {
        guard record.isValid, data.count == record.byteCount, Self.sha256(data) == record.sha256 else {
            throw AttachmentStoreError.checksumMismatch
        }
        lock.lock(); defer { lock.unlock() }
        if FileManager.default.fileExists(atPath: fileURL(id: record.id).path) {
            guard (try? self.data(for: record)) == data else { throw AttachmentStoreError.checksumMismatch }
            return
        }
        try data.write(to: fileURL(id: record.id), options: .atomic)
    }

    public func extractedText(for record: AttachmentRecord, maximumBytes: Int = maximumExtractedTextBytesPerTurn) throws -> String {
        let data = try data(for: record)
        return try Self.extractText(from: data, mediaType: record.mediaType, maximumBytes: maximumBytes)
    }

    private func fileURL(id: String) -> URL { rootURL.appendingPathComponent(id, isDirectory: false) }

    private static func validate(data: Data, mediaType: String) throws {
        if mediaType == "application/pdf" {
            guard PDFDocument(data: data) != nil else { throw AttachmentStoreError.invalidText }
        } else if String(data: data, encoding: .utf8) == nil {
            throw AttachmentStoreError.invalidText
        }
    }

    private static func extractText(from data: Data, mediaType: String, maximumBytes: Int = maximumExtractedTextBytesPerAttachment) throws -> String {
        let maximumBytes = max(0, maximumBytes)
        let raw: String
        if mediaType == "application/pdf" {
            guard let document = PDFDocument(data: data) else { throw AttachmentStoreError.invalidText }
            var pages: [String] = []
            var processedOCRPages = 0
            var skippedScannedPages = false
            let skippedDocumentPages = document.pageCount > 100
            for index in 0..<min(document.pageCount, 100) {
                guard let page = document.page(at: index) else { continue }
                if let text = page.string?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                    pages.append(text)
                    continue
                }
                guard processedOCRPages < maximumPDFPagesForOCR else {
                    skippedScannedPages = true
                    continue
                }
                processedOCRPages += 1
                if let text = recognizeScannedPage(page), !text.isEmpty { pages.append(text) }
            }
            var notices: [String] = []
            if skippedScannedPages { notices.append("[扫描 PDF 的 OCR 仅覆盖前 \(maximumPDFPagesForOCR) 个无文本页面]") }
            if skippedDocumentPages { notices.append("[PDF 文本仅读取前 100 页]") }
            raw = (notices + (pages.isEmpty ? [] : [pages.joined(separator: "\n\n")])).joined(separator: "\n\n")
        } else {
            guard let text = String(data: data, encoding: .utf8) else { throw AttachmentStoreError.invalidText }
            raw = text
        }
        let bytes = Data(raw.utf8)
        guard bytes.count > maximumBytes else { return raw }
        var prefix = bytes.prefix(maximumBytes)
        while String(data: prefix, encoding: .utf8) == nil, !prefix.isEmpty { prefix = prefix.dropLast() }
        return String(decoding: prefix, as: UTF8.self) + "\n[附件文本已截断]"
    }

    private static func recognizeScannedPage(_ page: PDFPage) -> String? {
        let thumbnail = page.thumbnail(of: CGSize(width: 1_600, height: 1_600), for: .mediaBox)
        #if canImport(UIKit)
        guard let image = thumbnail.cgImage else { return nil }
        #elseif canImport(AppKit)
        guard let image = thumbnail.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        #else
        return nil
        #endif

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["zh-Hans", "en-US"]

        guard (try? VNImageRequestHandler(cgImage: image).perform([request])) != nil,
              let observations = request.results, !observations.isEmpty else { return nil }
        return observations
            .sorted {
                if abs($0.boundingBox.midY - $1.boundingBox.midY) > 0.015 {
                    return $0.boundingBox.midY > $1.boundingBox.midY
                }
                return $0.boundingBox.minX < $1.boundingBox.minX
            }
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
    }

    private static func safeDisplayName(_ value: String) -> String {
        let name = URL(fileURLWithPath: value).lastPathComponent
            .components(separatedBy: .controlCharacters).joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String((name.isEmpty ? "附件" : name).prefix(240))
    }

    private static func validateFileSize(at url: URL) throws {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
              values.isRegularFile == true else { throw AttachmentStoreError.invalidText }
        guard let size = values.fileSize, size > 0, size <= maximumFileBytes else { throw AttachmentStoreError.tooLarge }
    }

    private static func isSafeID(_ value: String) -> Bool {
        !value.isEmpty && value.count <= 100 && value.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
