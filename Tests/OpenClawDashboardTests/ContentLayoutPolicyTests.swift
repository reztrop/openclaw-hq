import XCTest
@testable import OpenClawDashboard

final class ContentLayoutPolicyTests: XCTestCase {
    func testCompactChatPreservesSidebarCollapsedState() {
        let state = ContentLayoutPolicy.state(for: 1299, selectedTab: .chat, currentSidebarCollapsed: true)

        XCTAssertTrue(state.isCompactWindow)
        XCTAssertTrue(state.isMainSidebarCollapsed)
    }

    func testCompactNonChatForcesSidebarVisible() {
        let state = ContentLayoutPolicy.state(for: 1299, selectedTab: .tasks, currentSidebarCollapsed: true)

        XCTAssertTrue(state.isCompactWindow)
        XCTAssertFalse(state.isMainSidebarCollapsed)
    }

    func testThresholdWidthIsNotCompactAndForcesSidebarVisible() {
        let state = ContentLayoutPolicy.state(for: ContentLayoutPolicy.compactThreshold, selectedTab: .chat, currentSidebarCollapsed: true)

        XCTAssertFalse(state.isCompactWindow)
        XCTAssertFalse(state.isMainSidebarCollapsed)
    }
}
