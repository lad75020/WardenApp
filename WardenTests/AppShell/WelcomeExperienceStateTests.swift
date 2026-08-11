@testable import Warden
import XCTest

final class WelcomeExperienceStateTests: XCTestCase {
    func testNoProviderRequiresSetup() {
        XCTAssertEqual(WelcomeExperienceState.resolve(providerCount: 0, chatCount: 0, hasSelection: false), .setupRequired)
    }
    func testConfiguredProviderWithoutChatsIsReadyForFirstChat() {
        XCTAssertEqual(WelcomeExperienceState.resolve(providerCount: 1, chatCount: 0, hasSelection: false), .readyForFirstChat)
    }
    func testExistingChatsWithoutSelectionRequiresSelection() {
        XCTAssertEqual(WelcomeExperienceState.resolve(providerCount: 1, chatCount: 1, hasSelection: false), .readyForSelection)
    }
    func testNegativeCountsAreTreatedAsZero() {
        XCTAssertEqual(WelcomeExperienceState.resolve(providerCount: -1, chatCount: -1, hasSelection: false), .setupRequired)
    }
}
