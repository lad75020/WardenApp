import XCTest
@testable import Warden

final class MultiAgentServiceSelectorTests: XCTestCase {
    func testUnselectedServiceIsDisabledAtSharedMaximum() {
        XCTAssertTrue(
            MultiAgentServiceSelector.isServiceSelectionDisabled(
                selectedCount: AppConstants.MultiAgent.maxConcurrentServices,
                isSelected: false
            )
        )
    }

    func testSelectedServiceRemainsEnabledAtSharedMaximum() {
        XCTAssertFalse(
            MultiAgentServiceSelector.isServiceSelectionDisabled(
                selectedCount: AppConstants.MultiAgent.maxConcurrentServices,
                isSelected: true
            )
        )
    }
}
