import Foundation
import ZIPFoundation

public struct ChatArchiveMessage: Equatable, Sendable, Identifiable {
    public let id: String
    public let role: MessageRole
    public let content: String
    public let createdAt: Date

    public init(id: String, role: MessageRole, content: String, createdAt: Date) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
    }
}

public struct ChatArchiveConversation: Equatable, Sendable, Identifiable {
    public let sourceID: String
    public let title: String
    public let createdAt: Date
    public let messages: [ChatArchiveMessage]
    public var id: String { sourceID }

    public init(sourceID: String, title: String, createdAt: Date, messages: [ChatArchiveMessage]) {
        self.sourceID = sourceID
        self.title = title
        self.createdAt = createdAt
        self.messages = messages
    }
}

public enum ChatArchiveImporter {
    public static let maximumBytes = 50_000_000
    public static let maximumArchiveEntries = 100_000
    public static let maximumConversations = 10_000
    public static let maximumMessages = 200_000

    public static func parseChatGPTFile(at url: URL) throws -> [ChatArchiveConversation] {
        switch url.pathExtension.lowercased() {
        case "json":
            if let fileSize = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, fileSize > maximumBytes {
                throw ChatArchiveImportError.tooLarge
            }
            return try parseChatGPTJSON(Data(contentsOf: url, options: .mappedIfSafe))
        case "zip":
            return try parseChatGPTZIP(at: url)
        default:
            throw ChatArchiveImportError.invalidFormat
        }
    }

    public static func parseChatGPTZIP(at url: URL) throws -> [ChatArchiveConversation] {
        let archive: Archive
        do { archive = try Archive(url: url, accessMode: .read) }
        catch { throw ChatArchiveImportError.invalidArchive }

        var entryCount = 0
        var conversationEntries: [Entry] = []
        for entry in archive {
            entryCount += 1
            guard entryCount <= maximumArchiveEntries else { throw ChatArchiveImportError.tooManyArchiveEntries }
            let filename = entry.path.split(separator: "/").last.map(String.init)
            if filename == "conversations.json", entry.type == .file {
                conversationEntries.append(entry)
                guard conversationEntries.count <= 1 else { throw ChatArchiveImportError.ambiguousConversationFile }
            }
        }
        guard let entry = conversationEntries.first else { throw ChatArchiveImportError.invalidFormat }
        guard entry.uncompressedSize <= UInt64(maximumBytes) else { throw ChatArchiveImportError.tooLarge }

        var data = Data()
        data.reserveCapacity(Int(entry.uncompressedSize))
        do {
            _ = try archive.extract(entry, bufferSize: 16 * 1024) { chunk in
                guard data.count <= maximumBytes - chunk.count else { throw ChatArchiveImportError.tooLarge }
                data.append(chunk)
            }
        } catch let error as ChatArchiveImportError {
            throw error
        } catch {
            throw ChatArchiveImportError.invalidArchive
        }
        return try parseChatGPTJSON(data)
    }

    public static func parseChatGPTJSON(_ data: Data) throws -> [ChatArchiveConversation] {
        guard data.count <= maximumBytes else { throw ChatArchiveImportError.tooLarge }
        let exported: [ExportConversation]
        do { exported = try JSONDecoder().decode([ExportConversation].self, from: data) }
        catch { throw ChatArchiveImportError.invalidFormat }
        guard exported.count <= maximumConversations else { throw ChatArchiveImportError.tooManyConversations }

        var totalMessages = 0
        let parsed = exported.compactMap { item -> ChatArchiveConversation? in
            guard !item.id.isEmpty, item.id.count <= 200 else { return nil }
            let orderedNodes = orderedMessageNodes(in: item)
            let messages = orderedNodes.compactMap { node -> ChatArchiveMessage? in
                guard let message = node.message,
                      let role = MessageRole(rawValue: message.author.role),
                      let content = message.content.text,
                      !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      content.utf8.count <= 2_000_000 else { return nil }
                return ChatArchiveMessage(
                    id: message.id ?? node.id,
                    role: role,
                    content: content,
                    createdAt: Date(timeIntervalSince1970: message.createTime ?? item.createTime ?? 0)
                )
            }
            totalMessages += messages.count
            guard !messages.isEmpty else { return nil }
            return ChatArchiveConversation(
                sourceID: item.id,
                title: item.title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "导入的对话",
                createdAt: Date(timeIntervalSince1970: item.createTime ?? 0),
                messages: messages
            )
        }
        guard totalMessages <= maximumMessages else { throw ChatArchiveImportError.tooManyMessages }
        return parsed.sorted { $0.createdAt > $1.createdAt }
    }

    private static func orderedMessageNodes(in conversation: ExportConversation) -> [ExportNode] {
        guard let mapping = conversation.mapping else { return [] }
        if let currentNode = conversation.currentNode {
            var path: [ExportNode] = []
            var cursor: String? = currentNode
            var visited = Set<String>()
            while let nodeID = cursor, visited.insert(nodeID).inserted, let node = mapping[nodeID] {
                path.append(node.withFallbackID(nodeID))
                cursor = node.parent
            }
            if !path.isEmpty { return path.reversed() }
        }
        return mapping.keys.sorted().compactMap { key in
            mapping[key].map { $0.withFallbackID(key) }
        }.sorted { left, right in
            let leftTime = left.message?.createTime ?? 0
            let rightTime = right.message?.createTime ?? 0
            if leftTime != rightTime { return leftTime < rightTime }
            return left.id < right.id
        }
    }
}

public enum ChatArchiveImportError: Error, LocalizedError {
    case tooLarge
    case invalidFormat
    case invalidArchive
    case ambiguousConversationFile
    case tooManyArchiveEntries
    case tooManyConversations
    case tooManyMessages

    public var errorDescription: String? {
        switch self {
        case .tooLarge: "文件超过 50 MB，未读取。"
        case .invalidFormat: "这不是可识别的 ChatGPT conversations.json 文件。"
        case .invalidArchive: "ZIP 文件无法安全读取或内容已损坏。"
        case .ambiguousConversationFile: "ZIP 中发现多个 conversations.json，无法确定要导入哪一个。"
        case .tooManyArchiveEntries: "ZIP 文件包含过多项目，未继续读取。"
        case .tooManyConversations: "文件包含的对话过多，未导入。"
        case .tooManyMessages: "文件包含的消息过多，未导入。"
        }
    }
}

private struct ExportConversation: Decodable {
    let id: String
    let title: String?
    let createTime: Double?
    let currentNode: String?
    let mapping: [String: ExportNode]?

    enum CodingKeys: String, CodingKey {
        case id, title, mapping
        case createTime = "create_time"
        case currentNode = "current_node"
    }
}

private struct ExportNode: Decodable {
    let id: String
    let parent: String?
    let message: ExportMessage?

    func withFallbackID(_ fallback: String) -> ExportNode {
        ExportNode(id: id.isEmpty ? fallback : id, parent: parent, message: message)
    }
}

private struct ExportMessage: Decodable {
    let id: String?
    let author: ExportAuthor
    let content: ExportContent
    let createTime: Double?

    enum CodingKeys: String, CodingKey {
        case id, author, content
        case createTime = "create_time"
    }
}

private struct ExportAuthor: Decodable {
    let role: String
}

private struct ExportContent: Decodable {
    let text: String?

    enum CodingKeys: String, CodingKey { case text, parts }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let directText = try container.decodeIfPresent(String.self, forKey: .text) {
            text = directText
        } else {
            text = try container.decodeIfPresent([FlexiblePart].self, forKey: .parts)?
                .compactMap(\.text)
                .joined(separator: "\n")
        }
    }
}

private struct FlexiblePart: Decodable {
    let text: String?

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        text = try? value.decode(String.self)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
