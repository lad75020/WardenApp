import XCTest

enum AppShellTestSupport {
    static func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-AppShellUITestMode", "YES"]
        app.launch()
        return app
    }
    static func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }
}
