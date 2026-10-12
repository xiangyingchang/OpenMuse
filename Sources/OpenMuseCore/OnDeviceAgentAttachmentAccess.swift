import Foundation

public struct OnDeviceAgentAttachmentSummary: Equatable, Sendable {
    public let id: String
    public let displayName: String
    public let mediaType: String
    public let byteCount: Int
    public let createdAt: Date
}

public struct OnDeviceAgentAttachmentListing: Equatable, Sendable {
    public let items: [OnDeviceAgentAttachmentSummary]
    public let totalCount: Int

    public var isTruncated: Bool { totalCount > items.count }
}

public struct OnDeviceAgentAttachmentContent: Equatable, Sendable {
    public let attachment: OnDeviceAgentAttachmentSummary
    public let extractedText: String
}

public enum OnDeviceAgentAttachmentAccessError: Error, LocalizedError, Equatable {
    case invalidConversation
    case notFound
    case invalidLimit

    public var errorDescription: String? {
        switch self {
        case .invalidConversation: "当前对话附件范围无效。"
        case .notFound: "当前对话中找不到这个附件。"
        case .invalidLimit: "附件读取范围无效。"
        }
    }
}

/// Read-only access to files explicitly attached in one conversation.
/// It exposes extracted text, never a path into the app's attachment store.
public struct OnDeviceAgentAttachmentAccess: Sendable {
    public static let maximumListedAttachments = 40
    public static let maximumExtractedTextBytes = AttachmentStore.maximumExtractedTextBytesPerAttachment

    private let conversationID: String
    private let records: [AttachmentRecord]
    private let store: AttachmentStore

    public init(conversationID: String, records: [AttachmentRecord], store: AttachmentStore) throws {
        guard !conversationID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OnDeviceAgentAttachmentAccessError.invalidConversation
        }
        self.conversationID = conversationID
        self.records = records
        self.store = store
    }

    public func list() -> OnDeviceAgentAttachmentListing {
        let scoped = scopedRecords()
        return OnDeviceAgentAttachmentListing(
            items: scoped.prefix(Self.maximumListedAttachments).map(Self.summary),
            totalCount: scoped.count
        )
    }

    public func readText(id: String, maximumBytes: Int = maximumExtractedTextBytes) throws -> OnDeviceAgentAttachmentContent {
        guard (1...Self.maximumExtractedTextBytes).contains(maximumBytes) else {
            throw OnDeviceAgentAttachmentAccessError.invalidLimit
        }
        guard AttachmentRecord.isSafeIdentifier(id),
              let record = scopedRecords().first(where: { $0.id == id }) else {
            throw OnDeviceAgentAttachmentAccessError.notFound
        }
        return OnDeviceAgentAttachmentContent(
            attachment: Self.summary(record),
            extractedText: try store.extractedText(for: record, maximumBytes: maximumBytes)
        )
    }

    private func scopedRecords() -> [AttachmentRecord] {
        records
            .filter { $0.conversationID == conversationID && $0.isValid }
            .sorted {
                if $0.createdAt != $1.createdAt { return $0.createdAt > $1.createdAt }
                return $0.id < $1.id
            }
    }

    private static func summary(_ record: AttachmentRecord) -> OnDeviceAgentAttachmentSummary {
        OnDeviceAgentAttachmentSummary(
            id: record.id,
            displayName: record.displayName,
            mediaType: record.mediaType,
            byteCount: record.byteCount,
            createdAt: record.createdAt
        )
    }
}
