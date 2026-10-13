import XCTest
@testable import OpenMuseCore

final class WorkspaceSectionTests: XCTestCase {
    func testIdeasRemainAvailableForRestorationButArePausedInNavigation() {
        XCTAssertTrue(WorkspaceSection.allCases.contains(.ideas))
        XCTAssertFalse(WorkspaceSection.navigationSections.contains(.ideas))
        XCTAssertEqual(WorkspaceSection.drawerSections, [.chat])
        XCTAssertEqual(WorkspaceSection.navigationSections, [.chat, .feed, .goals, .library])
    }
}
