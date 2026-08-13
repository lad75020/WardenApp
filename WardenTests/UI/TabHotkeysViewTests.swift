import XCTest
@testable import Warden

@MainActor
final class TabHotkeysViewTests: XCTestCase {
    func testQuickChatRegistrationFailureSurfacesRecommendationText() {
        XCTAssertEqual(
            TabHotkeysView.quickChatWarning(for: .mappingFailure),
            "Quick Chat shortcut could not be registered. Try another combination."
        )
        XCTAssertEqual(
            TabHotkeysView.quickChatWarning(for: .registrationFailure),
            TabHotkeysView.quickChatRegistrationWarning
        )
        XCTAssertNil(TabHotkeysView.quickChatWarning(for: .registered))
    }
}
