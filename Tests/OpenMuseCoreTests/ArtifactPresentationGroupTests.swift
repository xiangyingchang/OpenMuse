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
}
