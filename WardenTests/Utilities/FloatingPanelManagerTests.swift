import XCTest
@testable import Warden

final class FloatingPanelManagerTests: XCTestCase {
    func testPanelHeightClampUsesQuickChatConstantBoundaries() {
        XCTAssertEqual(
            FloatingPanelManager.clampedHeight(AppConstants.QuickChat.minPanelHeight - 1),
            AppConstants.QuickChat.minPanelHeight
        )
        XCTAssertEqual(
            FloatingPanelManager.clampedHeight(AppConstants.QuickChat.maxPanelHeight + 1),
            AppConstants.QuickChat.maxPanelHeight
        )
        XCTAssertEqual(
            FloatingPanelManager.clampedHeight(200),
            200
        )
    }
}
