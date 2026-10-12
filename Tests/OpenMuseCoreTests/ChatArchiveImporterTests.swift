import Foundation
import XCTest
import ZIPFoundation
@testable import OpenMuseCore

final class ChatArchiveImporterTests: XCTestCase {
    func testChatGPTExportFollowsSelectedBranchAndKeepsOnlyUserAndAssistantText() throws {
        let data = Data(#"""
        [{
          "id":"chat-1",
          "title":"旅行想法",
          "create_time":100,
          "current_node":"assistant-selected",
          "mapping":{
            "root":{"id":"root","parent":null,"message":null},
            "user-1":{"id":"user-1","parent":"root","message":{"id":"user-message","author":{"role":"user"},"content":{"content_type":"text","parts":["想去恩施旅行"]},"create_time":101}},
            "assistant-old":{"id":"assistant-old","parent":"user-1","message":{"id":"old-answer","author":{"role":"assistant"},"content":{"parts":["旧分支回答"]},"create_time":102}},
            "assistant-selected":{"id":"assistant-selected","parent":"user-1","message":{"id":"selected-answer","author":{"role":"assistant"},"content":{"parts":["当前分支回答",{"type":"image"}]},"create_time":103}},
            "tool":{"id":"tool","parent":"assistant-selected","message":{"id":"tool-message","author":{"role":"tool"},"content":{"parts":["私有工具输出"]},"create_time":104}}
          }
        }]
        """#.utf8)

        let parsed = try ChatArchiveImporter.parseChatGPTJSON(data)

        XCTAssertEqual(parsed.count, 1)
        XCTAssertEqual(parsed[0].sourceID, "chat-1")
        XCTAssertEqual(parsed[0].title, "旅行想法")
        XCTAssertEqual(parsed[0].messages.map(\.id), ["user-message", "selected-answer"])
        XCTAssertEqual(parsed[0].messages.map(\.content), ["想去恩施旅行", "当前分支回答"])
        XCTAssertEqual(parsed[0].messages.map(\.role), [.user, .assistant])
    }

    func testChatGPTZipReadsOnlyTheConversationEntryWithoutExtractingArchiveContents() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("OpenMuseChatZip-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let zipURL = directory.appendingPathComponent("chatgpt-export.zip")
        let archive = try Archive(url: zipURL, accessMode: .create)
        let conversationJSON = Data(#"""
        [{"id":"zip-chat-1","title":"ZIP旅行","create_time":100,"current_node":"u","mapping":{"u":{"id":"u","parent":null,"message":{"id":"m1","author":{"role":"user"},"content":{"parts":["一起计划旅行"]},"create_time":101}}}}]
        """#.utf8)
        try archive.addEntry(
            with: "account/conversations.json",
            type: .file,
            uncompressedSize: Int64(conversationJSON.count),
            bufferSize: 1024,
            provider: { position, size in
                let start = Int(position)
                let end = min(start + size, conversationJSON.count)
                return conversationJSON.subdata(in: start..<end)
            }
        )
        let unrelated = Data("must not be extracted".utf8)
        try archive.addEntry(
            with: "../../outside.txt",
            type: .file,
            uncompressedSize: Int64(unrelated.count),
            bufferSize: 1024,
            provider: { position, size in
                let start = Int(position)
                let end = min(start + size, unrelated.count)
                return unrelated.subdata(in: start..<end)
            }
        )

        let parsed = try ChatArchiveImporter.parseChatGPTFile(at: zipURL)

        XCTAssertEqual(parsed.map(\.sourceID), ["zip-chat-1"])
        XCTAssertEqual(parsed.first?.messages.first?.content, "一起计划旅行")
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.deletingLastPathComponent().appendingPathComponent("outside.txt").path))
    }

    @MainActor
    func testImportStoresSelectedChatsAtomicallyWithProvenanceAndDeduplicates() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("OpenMuseChatImport-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let workspace = directory.appendingPathComponent("workspace", isDirectory: true)
        let model = OpenMuseAppModel(
            runtimeOverride: nil,
            workspaceRootOverride: workspace,
            configurationOverride: ModelConfiguration(),
            startMacBridge: false
        )
        let archive = ChatArchiveConversation(
            sourceID: "chat-source-1",
            title: "导入的旅行对话",
            createdAt: Date(timeIntervalSince1970: 100),
            messages: [
                ChatArchiveMessage(id: "source-user-1", role: .user, content: "想去恩施", createdAt: Date(timeIntervalSince1970: 101)),
                ChatArchiveMessage(id: "source-ai-1", role: .assistant, content: "可以先聊聊节奏。", createdAt: Date(timeIntervalSince1970: 102))
            ]
        )

        model.importChatArchiveConversations([archive])
        XCTAssertEqual(model.conversations.filter { $0.importedSourceID == archive.sourceID }.count, 1)
        XCTAssertTrue(model.statusText?.contains("没有加入 USER.md 记忆") == true)
        let imported = try XCTUnwrap(model.conversations.first(where: { $0.importedSourceID == archive.sourceID }))
        XCTAssertEqual(imported.importedFrom, "ChatGPT")
        let provenance = try XCTUnwrap(model.sources.first(where: { $0.sourceType == "chat-history-export" }))
        let importRecord = try XCTUnwrap(model.importRecords.first(where: { $0.externalItemID == archive.sourceID }))
        XCTAssertEqual(importRecord.sourceRecordID, provenance.id)
        XCTAssertEqual(importRecord.targetRecordID, imported.id)
        XCTAssertEqual(importRecord.itemCount, archive.messages.count)
        XCTAssertEqual(importRecord.contentDigest?.count, 64)
        let store = try SQLiteStore(path: directory.appendingPathComponent("OpenMuse.sqlite"))
        let importedMessages = try store.load(MessageRecord.self, kind: RecordKind.message).filter { $0.conversationID == imported.id }
        XCTAssertEqual(importedMessages.count, 2)
        XCTAssertEqual(Set(importedMessages.compactMap(\.importedSourceID)), ["source-user-1", "source-ai-1"])

        model.importChatArchiveConversations([archive])
        XCTAssertEqual(model.conversations.filter { $0.importedSourceID == archive.sourceID }.count, 1)

        let reopened = OpenMuseAppModel(
            runtimeOverride: nil,
            workspaceRootOverride: workspace,
            configurationOverride: ModelConfiguration(),
            startMacBridge: false
        )
        XCTAssertEqual(reopened.conversations.first(where: { $0.importedSourceID == archive.sourceID })?.title, archive.title)
        XCTAssertTrue(reopened.memoryClaims.isEmpty)
        XCTAssertEqual(reopened.sources, model.sources)
        XCTAssertEqual(reopened.importRecords, model.importRecords)
    }
}
