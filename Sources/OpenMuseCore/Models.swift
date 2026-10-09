import Foundation

public enum RecordKind {
    public static let conversation = "conversation"
    public static let message = "message"
    public static let goal = "goal"
    public static let artifact = "artifact"
    public static let document = "document"
    public static let task = "task"
}

public enum MessageRole: String, Codable {
    case user
    case assistant
}

public struct ConversationRecord: Codable, Identifiable, Equatable {
    public var id: String
    public var title: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: String = UUID().uuidString, title: String = "新对话", createdAt: Date = .now, updatedAt: Date = .now) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct MessageRecord: Codable, Identifiable, Equatable {
    public var id: String
    public var conversationID: String
    public var role: MessageRole
    public var content: String
    public var createdAt: Date
    public var status: String

    public init(id: String = UUID().uuidString, conversationID: String, role: MessageRole, content: String, createdAt: Date = .now, status: String = "complete") {
        self.id = id
        self.conversationID = conversationID
        self.role = role
        self.content = content
        self.createdAt = createdAt
        self.status = status
    }
}

public struct GoalStep: Codable, Identifiable, Equatable {
    public var id: String
    public var title: String
    public var isComplete: Bool

    public init(id: String = UUID().uuidString, title: String, isComplete: Bool = false) {
        self.id = id
        self.title = title
        self.isComplete = isComplete
    }
}

public struct GoalRecord: Codable, Identifiable, Equatable {
    public var id: String
    public var conversationID: String
    public var title: String
    public var summary: String
    public var status: String
    public var steps: [GoalStep]
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: String = UUID().uuidString, conversationID: String, title: String, summary: String, status: String = "进行中", steps: [GoalStep], createdAt: Date = .now, updatedAt: Date = .now) {
        self.id = id
        self.conversationID = conversationID
        self.title = title
        self.summary = summary
        self.status = status
        self.steps = steps
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct ArtifactRecord: Codable, Identifiable, Equatable {
    public var id: String
    public var title: String
    public var kind: String
    public var conversationID: String
    public var goalID: String?
    public var currentRevision: Int
    public var content: String
    public var updatedAt: Date

    public init(id: String = UUID().uuidString, title: String, kind: String = "travel-plan", conversationID: String, goalID: String?, currentRevision: Int = 1, content: String, updatedAt: Date = .now) {
        self.id = id
        self.title = title
        self.kind = kind
        self.conversationID = conversationID
        self.goalID = goalID
        self.currentRevision = currentRevision
        self.content = content
        self.updatedAt = updatedAt
    }
}

public struct WorkspaceDocument: Codable, Identifiable, Equatable {
    public var id: String { path }
    public var path: String
    public var title: String
    public var content: String
    public var revision: Int
    public var updatedAt: Date

    public init(path: String, title: String, content: String, revision: Int = 1, updatedAt: Date = .now) {
        self.path = path
        self.title = title
        self.content = content
        self.revision = revision
        self.updatedAt = updatedAt
    }
}

public struct ActivityRecord: Codable, Identifiable, Equatable {
    public var id: String
    public var conversationID: String
    public var title: String
    public var stage: String
    public var status: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: String = UUID().uuidString, conversationID: String, title: String, stage: String, status: String = "running", createdAt: Date = .now, updatedAt: Date = .now) {
        self.id = id
        self.conversationID = conversationID
        self.title = title
        self.stage = stage
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public enum ModelProvider: String, Codable, CaseIterable, Identifiable, Sendable {
    case openAI = "OpenAI"
    case deepSeek = "DeepSeek"
    case custom = "OpenAI 兼容接口"

    public var id: String { rawValue }

    public var defaultEndpoint: String {
        switch self {
        case .openAI: "https://api.openai.com/v1"
        case .deepSeek: "https://api.deepseek.com/v1"
        case .custom: "https://"
        }
    }

    public var defaultModel: String {
        switch self {
        case .openAI: "gpt-4o-mini"
        case .deepSeek: "deepseek-chat"
        case .custom: "your-model-id"
        }
    }
}

public struct ModelConfiguration: Codable, Equatable, Sendable {
    public var provider: ModelProvider
    public var endpoint: String
    public var model: String
    public var contextWindow: Int

    public init(provider: ModelProvider = .deepSeek, endpoint: String = ModelProvider.deepSeek.defaultEndpoint, model: String = ModelProvider.deepSeek.defaultModel, contextWindow: Int = 32_000) {
        self.provider = provider
        self.endpoint = endpoint
        self.model = model
        self.contextWindow = contextWindow
    }

    public var isReady: Bool {
        let rawEndpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: rawEndpoint),
              let scheme = components.scheme?.lowercased(),
              let host = components.host?.lowercased(),
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil,
              !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        return scheme == "https" || ((host == "localhost" || host == "127.0.0.1" || host == "::1") && scheme == "http")
    }

    public var credentialAccount: String {
        let rawEndpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedEndpoint: String
        if var components = URLComponents(string: rawEndpoint) {
            if let scheme = components.scheme { components.scheme = scheme.lowercased() }
            if let host = components.host { components.host = host.lowercased() }
            components.path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            normalizedEndpoint = components.string ?? rawEndpoint
        } else {
            normalizedEndpoint = rawEndpoint
        }
        return "model-api-key:\(provider.rawValue):\(normalizedEndpoint)"
    }
}

public struct TranscriptMessage: Codable, Sendable {
    public var role: String
    public var content: String
}

public enum WorkspaceSection: String, CaseIterable, Identifiable {
    case chat = "聊天"
    case goals = "目标"
    case feed = "动态"
    case ideas = "点子"
    case library = "资源库"

    public var id: String { rawValue }

    public var symbol: String {
        switch self {
        case .chat: "bubble.left.and.bubble.right.fill"
        case .goals: "target"
        case .feed: "sparkles"
        case .ideas: "lightbulb"
        case .library: "square.grid.2x2"
        }
    }
}

public enum OpenMuseSheet: Identifiable {
    case settings
    case memories
    case activity
    case artifact(ArtifactRecord)
    case document(WorkspaceDocument)

    public var id: String {
        switch self {
        case .settings: "settings"
        case .memories: "memories"
        case .activity: "activity"
        case .artifact(let item): "artifact-\(item.id)"
        case .document(let item): "document-\(item.path)"
        }
    }
}
