import XCTest
@testable import Warden

@MainActor
final class MultiAgentQuickChatTests: XCTestCase {
    func testSharedLimitsAndFailureWarningComposeAcrossFeatureBoundaries() {
        XCTAssertEqual(
            MultiAgentMessageManager.cappedServices([1, 2, 3, 4]),
            [1, 2, 3]
        )
        XCTAssertTrue(
            MultiAgentServiceSelector.isServiceSelectionDisabled(
                selectedCount: AppConstants.MultiAgent.maxConcurrentServices,
                isSelected: false
            )
        )
        XCTAssertEqual(
            FloatingPanelManager.clampedHeight(AppConstants.QuickChat.maxPanelHeight + 1),
            AppConstants.QuickChat.maxPanelHeight
        )
        XCTAssertEqual(
            TabHotkeysView.quickChatWarning(for: .mappingFailure),
            TabHotkeysView.quickChatRegistrationWarning
        )
    }
}
