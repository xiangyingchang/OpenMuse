import XCTest
@testable import OpenMuseCore

final class ArtifactPresentationGroupTests: XCTestCase {
    func testSameNamedArtifactsAppearInOneGroupAndRemainSelectable() {
        let older = ArtifactRecord(
            id: "older", title: "旅行计划草稿", conversationID: "main", goalID: "goal-a",
            content: "older draft", updatedAt: Date(timeIntervalSince1970: 1)
        )
        let newer = ArtifactRecord(
            id: "newer", title: " 旅行计划草稿 ", conversationID: "main", goalID: "goal-b",
            content: "newer draft", updatedAt: Date(timeIntervalSince1970: 2)
        )
        let other = ArtifactRecord(
            id: "other", title: "预算清单", conversationID: "main", goalID: nil,
            content: "budget", updatedAt: Date(timeIntervalSince1970: 3)
        )

        let groups = ArtifactPresentationGroup.make(from: [older, newer, other])

        XCTAssertEqual(groups.count, 2)
        let travel = try! XCTUnwrap(groups.first(where: { $0.records.count == 2 }))
        XCTAssertEqual(travel.latest.id, "newer")
        XCTAssertEqual(Set(travel.records.map(\.id)), ["older", "newer"])
    }

    func testDifferentArtifactKindsDoNotShareAChatCard() {
        let travel = ArtifactRecord(id: "travel", title: "结果", conversationID: "main", goalID: nil, content: "text")
        let web = ArtifactRecord(id: "web", title: "结果", kind: "web", conversationID: "main", goalID: nil, content: "<p>web</p>")

        XCTAssertEqual(ArtifactPresentationGroup.make(from: [travel, web]).count, 2)
    }

    func testChatTimelinePlacesGroupedArtifactAfterLatestSourceAndBeforeLaterMessages() {
        let firstUser = MessageRecord(
            id: "trip-user-1", conversationID: "main", role: .user, content: "计划一次旅行。",
            createdAt: Date(timeIntervalSince1970: 1)
        )
        let firstReply = MessageRecord(
            id: "trip-assistant-1", conversationID: "main", role: .assistant, content: "这是旅行计划草稿。",
            createdAt: Date(timeIntervalSince1970: 2)
        )
        let followupUser = MessageRecord(
            id: "unrelated-user-2", conversationID: "main", role: .user, content: "后来我又问了一个问题。",
            createdAt: Date(timeIntervalSince1970: 3)
        )
        let followupReply = MessageRecord(
            id: "unrelated-assistant-2", conversationID: "main", role: .assistant, content: "这是另一个回答。",
            createdAt: Date(timeIntervalSince1970: 4)
        )
        let older = ArtifactRecord(
            id: "trip-artifact-older", title: "旅行计划草稿", conversationID: "main", goalID: "goal-older",
            content: "旧草稿", sourceMessageIDs: [firstUser.id], updatedAt: Date(timeIntervalSince1970: 2)
        )
        let latest = ArtifactRecord(
            id: "trip-artifact-latest", title: " 旅行计划草稿 ", conversationID: "main", goalID: "goal-latest",
            content: "最新草稿", sourceMessageIDs: [firstUser.id, firstReply.id], updatedAt: Date(timeIntervalSince1970: 5)
        )
        let groups = ArtifactPresentationGroup.make(from: [older, latest])

        let entries = ChatTimeline.entries(
            messages: [firstUser, firstReply, followupUser, followupReply], artifactGroups: groups
        )

        XCTAssertEqual(entries.map(\.id), [
            "message:\(firstUser.id)",
            "message:\(firstReply.id)",
            "artifact:\(try! XCTUnwrap(groups.first?.id))",
            "message:\(followupUser.id)",
            "message:\(followupReply.id)"
        ])
    }

    func testChatTimelineOmitsArtifactsWithoutAResolvableSourceMessage() {
        let message = MessageRecord(id: "later-message", conversationID: "main", role: .user, content: "后来聊天")
        let artifact = ArtifactRecord(
            id: "legacy-artifact", title: "旧旅行计划", conversationID: "main", goalID: nil,
            content: "旧草稿", sourceMessageIDs: ["missing-source-message"]
        )
        let entries = ChatTimeline.entries(
            messages: [message], artifactGroups: ArtifactPresentationGroup.make(from: [artifact])
        )

        XCTAssertEqual(entries.map(\.id), ["message:\(message.id)"])
    }
}
