import XCTest
@testable import Warden

final class HotkeyModelsTests: XCTestCase {
    func testDisplayStringRoundTripsThroughParser() throws {
        let shortcut = KeyboardShortcut(
            key: "k",
            modifiers: [.command, .option, .control, .shift]
        )

        let parsed = try XCTUnwrap(KeyboardShortcut.from(displayString: shortcut.displayString))

        XCTAssertEqual(parsed, shortcut)
        XCTAssertEqual(parsed.displayString, "⌘⌥⌃⇧K")
    }
}
