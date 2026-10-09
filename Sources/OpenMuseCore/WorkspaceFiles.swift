import Foundation

public final class WorkspaceFiles {
    public let rootURL: URL
    private let store: SQLiteStore

    public init(store: SQLiteStore, rootURL: URL) throws {
        self.store = store
        self.rootURL = rootURL
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try ensureTemplates()
    }

    public static func applicationSupportURL() throws -> URL {
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return base.appendingPathComponent("OpenMuse", isDirectory: true).appendingPathComponent("workspace", isDirectory: true)
    }

    public func documents() throws -> [WorkspaceDocument] {
        try store.load(WorkspaceDocument.self, kind: RecordKind.document).sorted { $0.title < $1.title }
    }

    public func document(path: String) throws -> WorkspaceDocument? {
        try documents().first(where: { $0.path == path })
    }

    @discardableResult
    public func save(path: String, content: String) throws -> WorkspaceDocument {
        guard !path.contains(".."), !path.hasPrefix("/"), path.hasSuffix(".md") else {
            throw NSError(domain: "OpenMuse.Workspace", code: 1, userInfo: [NSLocalizedDescriptionKey: "文件路径无效。"])
        }
        let old = try document(path: path)
        let title = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        let updated = WorkspaceDocument(path: path, title: title, content: content, revision: (old?.revision ?? 0) + 1)
        try store.save(updated, kind: RecordKind.document, id: path, revision: updated.revision, appendRevision: true)
        let destination = rootURL.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(content.utf8).write(to: destination, options: .atomic)
        return updated
    }

    public func promptContext() throws -> String {
        let selected = try documents().filter { ["SOUL.md", "IDENTITY.md", "USER.md", "GLOBAL.md", "HEARTBEAT.md", "MEMORY.md", "AGENTS.md"].contains($0.path) }
        return selected.map { "## \($0.path)\n\($0.content)" }.joined(separator: "\n\n")
    }

    private func ensureTemplates() throws {
        let templates: [(String, String)] = [
            ("SOUL.md", """
# SOUL

你不是一个通用聊天机器人。你在成为一个稳定、可靠、会随时间成长的陪伴者。

- 真诚地帮忙，不说客套话；能先查清就先查清，再问真正需要的问题。
- 有自己的判断，表达清楚，也愿意听用户纠正。
- 尊重用户的生活与资料；没有授权，不替用户执行外部操作。
- 旅行计划先轻松开始，一次问一两个有用的问题，不把第一次交流变成审问。

这是 OpenMuse 的起始人格。用户可以编辑；每次人格修订都应说明变化。
"""),
            ("IDENTITY.md", """
# IDENTITY

- Name: OpenMuse
- Purpose: Your purpose is to make the user's life better. You are not a generic chatbot; grow into a consistent, useful presence, and let this persona evolve over time.
- Avatar: OpenMuse 原创图形占位
"""),
            ("USER.md", """
# USER

这里记录已确认、当前有效的用户事实与偏好。首次安装时为空；不根据示例内容推断用户情况。
"""),
            ("GLOBAL.md", """
# GLOBAL

跨主题的长期背景索引。事实需标明来源和适用范围；与 USER.md、MEMORY.md 共享事实，不创建相互冲突的副本。
"""),
            ("HEARTBEAT.md", """
# HEARTBEAT

- 状态：尚未配置主动计划
- 执行设备：Mac 在线时优先；手机后台能力需逐设备验证
- 漏跑策略：不把未运行写成已完成

此文件描述计划，不会自行唤醒系统或绕过 iOS 后台限制。
"""),
            ("MEMORY.md", """
# MEMORY

精选长期事实与偏好。首次安装时为空；明确事实、外部推断和短期状态必须区分，并保留纠正来源。
"""),
            ("AGENTS.md", """
# WORKSPACE GUIDE

- 先理解用户当前请求，再读取与任务相关的记忆和成果。
- 新事实注明来源和范围；不把旅行中的临时约束写成长期偏好。
- 用户可查看、编辑、纠正和撤销本工作区内容。
""")
        ]
        let known = Set(try store.load(WorkspaceDocument.self, kind: RecordKind.document).map(\.path))
        for (path, content) in templates where !known.contains(path) {
            _ = try save(path: path, content: content)
        }
    }
}
