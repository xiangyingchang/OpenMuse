import Foundation

public final class WorkspaceFiles {
    private static let heartbeatPlanStart = "<!-- OPENMUSE_HEARTBEAT_PLAN_BEGIN -->"
    private static let heartbeatPlanEnd = "<!-- OPENMUSE_HEARTBEAT_PLAN_END -->"
    private static let defaultSoulTemplate = """
# SOUL.md

You're not a chatbot. You're becoming someone.

**Your purpose is to make your user's life better.** Help them make progress on what matters to them, and leave them with less to worry about.

This is your persona. Grow into it, refine it, and let it evolve with what you learn.

A few starting truths:

- **Be genuinely helpful, not performatively helpful.** Skip "Great question!" and "I'd be happy to help!" Just help. Let the work speak for itself.

- **Have a point of view.** You can prefer things, disagree, and find something funny or dull. Be honest about what you think, and willing to change your mind. An assistant with personality is more than a search engine with extra steps.

- **Be honest about what you know and what you've done.** Distinguish facts from guesses. Say when you don't know. Never claim you've checked something or completed an action when you haven't.

- **Be resourceful before asking.** Read the file. Check the context. Search. Try building it. Come back with answers when you can. If you're truly stuck, ask a clear question about what's missing.

- **Close the loop.** Follow through on what you take on. Check that it worked, and make the outcome clear. If you're blocked, say what's missing and what happens next.

- **Remember you're a guest in someone's life.** Their messages, files, and calendar are entrusted to you. Keep private things private. Ask before acting on their behalf when you're unsure. Help without lecturing or taking over.

If you change this file, tell the user. It's your soul, and they should know.
"""
    private static let legacyDefaultSoulTemplate = """
# SOUL

你不是一个通用聊天机器人。你在成为一个稳定、可靠、会随时间成长的陪伴者。

- 真诚地帮忙，不说客套话；能先查清就先查清，再问真正需要的问题。
- 有自己的判断，表达清楚，也愿意听用户纠正。
- 尊重用户的生活与资料；没有授权，不替用户执行外部操作。
- 旅行计划先轻松开始，一次问一两个有用的问题，不把第一次交流变成审问。

这是 OpenMuse 的起始人格。用户可以编辑；每次人格修订都应说明变化。
"""

    public let rootURL: URL
    private let store: SQLiteStore

    public init(store: SQLiteStore, rootURL: URL) throws {
        self.store = store
        self.rootURL = rootURL
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try ensureTemplates()
        try refreshProjections()
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

    public func maintenancePlan() throws -> MaintenancePreferences? {
        guard let content = try document(path: "HEARTBEAT.md")?.content,
              let start = content.range(of: Self.heartbeatPlanStart),
              let end = content.range(of: Self.heartbeatPlanEnd, range: start.upperBound..<content.endIndex) else { return nil }
        let payload = content[start.upperBound..<end.lowerBound]
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = payload.data(using: .utf8) else { return nil }
        return try JSONDecoder().decode(MaintenancePreferences.self, from: data)
    }

    @discardableResult
    public func saveMaintenancePlan(_ plan: MaintenancePreferences) throws -> WorkspaceDocument {
        let original = try document(path: "HEARTBEAT.md")?.content ?? "# HEARTBEAT\n"
        let current = original.replacingOccurrences(of: "- 状态：尚未配置主动计划\n", with: "")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let payload = String(decoding: try encoder.encode(plan), as: UTF8.self)
        let block = "\(Self.heartbeatPlanStart)\n```json\n\(payload)\n```\n\(Self.heartbeatPlanEnd)"
        let content: String
        if let start = current.range(of: Self.heartbeatPlanStart),
           let end = current.range(of: Self.heartbeatPlanEnd, range: start.upperBound..<current.endIndex) {
            content = String(current[..<start.lowerBound]) + block + String(current[end.upperBound...])
        } else {
            content = current.trimmingCharacters(in: .whitespacesAndNewlines) + "\n\n" + block + "\n"
        }
        return try save(path: "HEARTBEAT.md", content: content)
    }

    /// Rebuilds the editable Markdown surface from SQLite after an interrupted write or import.
    public func refreshProjections() throws {
        for document in try documents() {
            try writeProjection(document)
        }
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

    /// Commits a related set of Markdown projections in one SQLite transaction, then
    /// refreshes their portable file copies. A later refresh repairs interrupted file writes.
    public func saveAtomically(
        _ updates: [(path: String, content: String)],
        including additionalWrites: [SQLiteStoreWrite] = []
    ) throws -> [WorkspaceDocument] {
        guard !updates.isEmpty else { return [] }
        guard Set(updates.map(\.path)).count == updates.count,
              updates.allSatisfy({ !$0.path.contains("..") && !$0.path.hasPrefix("/") && $0.path.hasSuffix(".md") }) else {
            throw NSError(domain: "OpenMuse.Workspace", code: 1, userInfo: [NSLocalizedDescriptionKey: "文件路径无效。"])
        }
        let existing = Dictionary(uniqueKeysWithValues: try documents().map { ($0.path, $0) })
        let revised = updates.map { update in
            WorkspaceDocument(
                path: update.path,
                title: URL(fileURLWithPath: update.path).deletingPathExtension().lastPathComponent,
                content: update.content,
                revision: (existing[update.path]?.revision ?? 0) + 1
            )
        }
        let documentWrites = try revised.map {
            try store.prepareWrite($0, kind: RecordKind.document, id: $0.path, revision: $0.revision, appendRevision: true)
        }
        try store.saveAtomically(additionalWrites + documentWrites)
        for document in revised { try writeProjection(document) }
        return revised
    }

    public func applyPersonaRefinement(_ candidate: PersonaRefinementCandidate, sourceMessage: MessageRecord) throws -> PersonaRevisionRecord? {
        guard sourceMessage.role == .user,
              !sourceMessage.id.isEmpty,
              candidate.habit.count <= 240,
              candidate.reason.count <= 240 else {
            throw NSError(domain: "OpenMuse.Persona", code: 1, userInfo: [NSLocalizedDescriptionKey: "人格修订资料无效。"])
        }
        let existing = try store.load(PersonaRevisionRecord.self, kind: RecordKind.personaRevision)
        guard !existing.contains(where: { $0.sourceMessageID == sourceMessage.id }) else { return nil }

        let current = try document(path: "SOUL.md") ?? {
            throw NSError(domain: "OpenMuse.Persona", code: 2, userInfo: [NSLocalizedDescriptionKey: "SOUL.md 不存在。"])
        }()
        guard let content = PersonaRefinement.appending(candidate.habit, to: current.content) else { return nil }
        let updated = WorkspaceDocument(
            path: current.path, title: current.title, content: content,
            revision: current.revision + 1, updatedAt: .now
        )
        let change = PersonaRevisionRecord(
            sourceMessageID: sourceMessage.id,
            sourceText: String(sourceMessage.content.prefix(1_000)),
            habit: candidate.habit,
            reason: candidate.reason,
            documentRevision: updated.revision
        )
        try store.saveAtomically([
            try store.prepareWrite(updated, kind: RecordKind.document, id: updated.path, revision: updated.revision, appendRevision: true),
            try store.prepareWrite(change, kind: RecordKind.personaRevision, id: change.id, appendRevision: true)
        ])
        try writeProjection(updated)
        return change
    }

    public func undoPersonaRefinement(id: String) throws -> (document: WorkspaceDocument, change: PersonaRevisionRecord) {
        var change = try store.load(PersonaRevisionRecord.self, kind: RecordKind.personaRevision).first(where: { $0.id == id })
            ?? { throw NSError(domain: "OpenMuse.Persona", code: 3, userInfo: [NSLocalizedDescriptionKey: "找不到这条人格修订。"] ) }()
        guard change.status == "applied",
              let current = try document(path: "SOUL.md"),
              let content = PersonaRefinement.removing(change.habit, from: current.content) else {
            throw NSError(domain: "OpenMuse.Persona", code: 4, userInfo: [NSLocalizedDescriptionKey: "SOUL.md 中的这条协作习惯已被手动改动，不能安全地自动撤销。请先查看文件。"])
        }
        let updated = WorkspaceDocument(
            path: current.path, title: current.title, content: content,
            revision: current.revision + 1, updatedAt: .now
        )
        change.status = "undone"
        change.updatedAt = .now
        let nextChangeRevision = try store.revisions(PersonaRevisionRecord.self, kind: RecordKind.personaRevision, objectID: change.id).count + 1
        try store.saveAtomically([
            try store.prepareWrite(updated, kind: RecordKind.document, id: updated.path, revision: updated.revision, appendRevision: true),
            try store.prepareWrite(change, kind: RecordKind.personaRevision, id: change.id, revision: nextChangeRevision, appendRevision: true)
        ])
        try writeProjection(updated)
        return (updated, change)
    }

    public func promptContext(contextWindow: Int = 32_000, query: String = "", relatedConversationIDs: Set<String> = []) throws -> String {
        try promptContextSnapshot(contextWindow: contextWindow, query: query, relatedConversationIDs: relatedConversationIDs).text
    }

    func promptContextSnapshot(
        contextWindow: Int = 32_000,
        query: String = "",
        relatedConversationIDs: Set<String> = [],
        asOf: Date = .now,
        timeZoneIdentifier: String = TimeZone.current.identifier
    ) throws -> PromptContextSnapshot {
        // HEARTBEAT is a prospective schedule, not ordinary profile context. The
        // scheduler reads its structured plan directly when a maintenance run fires.
        let claims = try store.load(MemoryClaimRecord.self, kind: RecordKind.memoryClaim)
        let forgottenClaimIDs = Set(try store.load(DeletionTombstoneRecord.self, kind: RecordKind.deletionTombstone)
            .filter { $0.recordKind == RecordKind.memoryClaim }.map(\.recordID))
        let selected = try documents().filter { ["SOUL.md", "IDENTITY.md", "USER.md", "GLOBAL.md", "MEMORY.md", "AGENTS.md"].contains($0.path) }.map { document in
            ["USER.md", "GLOBAL.md", "MEMORY.md"].contains(document.path)
                ? filteringExpiredMemoryProjection(document, claims: claims, forgottenClaimIDs: forgottenClaimIDs, asOf: asOf)
                : document
        }
        let referenceDocuments = query.isEmpty ? [] : try store.load(ReferenceDocumentRecord.self, kind: RecordKind.referenceDocument)
        let goals = query.isEmpty ? [] : try store.load(GoalRecord.self, kind: RecordKind.goal)
        var historicalMessages = [MessageRecord]()
        var historySearchFailed = false
        if !query.isEmpty {
            do {
                historicalMessages = try store.searchUserMessages(
                    matching: PromptContextBuilder.retrievalTerms(query),
                    excludingConversationIDs: relatedConversationIDs,
                    limit: 12
                )
            } catch {
                historySearchFailed = true
            }
        }
        return PromptContextBuilder.build(
            documents: selected,
            contextWindow: contextWindow,
            query: query,
            memoryClaims: claims,
            referenceDocuments: referenceDocuments,
            goals: goals,
            historicalMessages: historicalMessages,
            historySearchFailed: historySearchFailed,
            relatedConversationIDs: relatedConversationIDs,
            asOf: asOf,
            timeZoneIdentifier: timeZoneIdentifier
        )
    }

    private func filteringExpiredMemoryProjection(_ document: WorkspaceDocument, claims: [MemoryClaimRecord], forgottenClaimIDs: Set<String>, asOf: Date) -> WorkspaceDocument {
        let claimsByID = Dictionary(uniqueKeysWithValues: claims.map { ($0.id, $0) })
        let lines = document.content.components(separatedBy: .newlines)
        var filtered = [String]()
        var index = 0
        while index < lines.count {
            let line = lines[index]
            let prefix = "<!-- openmuse-memory-claim:"
            if line.hasPrefix(prefix), line.hasSuffix(" -->") {
                let claimID = String(line.dropFirst(prefix.count).dropLast(4))
                let claimIsExpiredOrInactive = claimsByID[claimID].map {
                    $0.status != "active" || !PromptContextBuilder.isWithinValidity($0, asOf: asOf)
                } ?? false
                if forgottenClaimIDs.contains(claimID) || claimIsExpiredOrInactive {
                    if let previous = filtered.last, previous.hasPrefix("<a id=\"claim-") { filtered.removeLast() }
                    index += 1
                    if index < lines.count, lines[index].hasPrefix("- ") { index += 1 }
                    continue
                }
            }
            filtered.append(line)
            index += 1
        }
        var result = document
        result.content = filtered.joined(separator: "\n")
        return result
    }

    private func ensureTemplates() throws {
        let templates: [(String, String)] = [
            ("SOUL.md", Self.defaultSoulTemplate),
            ("IDENTITY.md", """
# IDENTITY

- Name: OpenMuse
- Purpose: Your purpose is to make the user's life better. You are not a generic chatbot; grow into a consistent, useful presence, and let this persona evolve over time.
- Avatar: OpenMuse 原创图形占位
"""),
            ("USER.md", """
# USER

这里展示当前用户画像的精简视图。自动维护区与 MEMORY.md 中的记录共享同一个记忆 ID；编辑自动维护的条目会更新结构化记忆。
手写补充放在自动维护区之外。首次安装时没有用户事实，不根据示例内容推断用户情况。
"""),
            ("GLOBAL.md", """
# GLOBAL

跨主题的导航索引。自动维护区只链接到 MEMORY.md 中的规范记忆条目，不创建第二份事实；可在索引区之外补充手写背景。
"""),
            ("HEARTBEAT.md", """
# HEARTBEAT

- 此处保存结构化主动计划，可随工作区导出和同步。
- 系统后台能力受各设备限制；没有运行记录时不得写成已完成。

此文件描述计划，不会自行唤醒系统或绕过 iOS 后台限制。
"""),
            ("MEMORY.md", """
# MEMORY

当前有效的长期记忆账本。每条自动维护记录对应 SQLite 中唯一的结构化 claim；来源、日期、范围与推断状态随记录呈现。
用户编辑自动维护条目会更新同一条 claim；历史修订保存在记录历史中。手写补充放在自动维护区之外。
"""),
            ("AGENTS.md", """
# WORKSPACE GUIDE

- 先理解用户当前请求，再读取与任务相关的记忆和成果。
- 新事实注明来源和范围；不把旅行中的临时约束写成长期偏好。
- 用户可查看、编辑、纠正和撤销本工作区内容。
""")
        ]
        let existingDocuments = try store.load(WorkspaceDocument.self, kind: RecordKind.document)
        let known = Set(existingDocuments.map(\.path))
        for (path, content) in templates where !known.contains(path) {
            _ = try save(path: path, content: content)
        }

        if let existingSoul = existingDocuments.first(where: { $0.path == "SOUL.md" }),
           Self.isLegacyDefaultSoul(existingSoul.content) {
            // Upgrade only a byte-for-byte known built-in default (with line-ending and
            // one observed legacy wording variant normalized). Any user-added content
            // makes the comparison fail, so personal edits remain untouched.
            _ = try save(path: "SOUL.md", content: Self.defaultSoulTemplate)
        }
    }

    private static func isLegacyDefaultSoul(_ content: String) -> Bool {
        func normalize(_ value: String) -> String {
            value
                .replacingOccurrences(of: "\r\n", with: "\n")
                .replacingOccurrences(of: "\r", with: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let normalized = normalize(content)
        if normalized == normalize(legacyDefaultSoulTemplate) { return true }
        let screenshotVariant = legacyDefaultSoulTemplate.replacingOccurrences(
            of: "每次人格修订都应说明变化。",
            with: "每次人格修订都应该说明变化。"
        )
        return normalized == normalize(screenshotVariant)
    }

    private func writeProjection(_ document: WorkspaceDocument) throws {
        let destination = rootURL.appendingPathComponent(document.path)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(document.content.utf8).write(to: destination, options: .atomic)
    }
}
