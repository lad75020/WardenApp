import Carbon
import XCTest
@testable import Warden

@MainActor
final class GlobalHotkeyHandlerTests: XCTestCase {
    func testRegistrationOutcomeReportsMappingFailureForUnmappedKey() {
        XCTAssertEqual(
            GlobalHotkeyHandler.registrationOutcome(forMappedKeyCode: nil, registrationStatus: nil),
            .mappingFailure
        )
    }

    func testRegistrationOutcomeReportsCarbonFailureAndSuccess() {
        XCTAssertEqual(
            GlobalHotkeyHandler.registrationOutcome(forMappedKeyCode: 0, registrationStatus: noErr),
            .registered
        )
        XCTAssertEqual(
            GlobalHotkeyHandler.registrationOutcome(forMappedKeyCode: 0, registrationStatus: -1),
            .registrationFailure
        )
    }
}
