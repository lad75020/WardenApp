import XCTest

enum AppShellTestSupport {
    private static let defaultsSuite = "com.warden.AppShellUITests.\(UUID().uuidString)"

    static func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-AppShellUITestMode", "YES",
            "-hasCompletedOnboarding", "NO",
            "-lastOpenedChatId", ""
        ]
        app.launchEnvironment["WARDEN_APP_SHELL_UI_TEST"] = "1"
        app.launchEnvironment["WARDEN_APP_SHELL_UI_TEST_DEFAULTS_SUITE"] = defaultsSuite
        app.launchEnvironment["WARDEN_APP_SHELL_UI_TEST_RESET_DEFAULTS"] = "1"
        app.launch()
        return app
    }

    static func relaunchApp(_ app: XCUIApplication) {
        app.terminate()
        app.launchEnvironment["WARDEN_APP_SHELL_UI_TEST_RESET_DEFAULTS"] = "0"
        app.launch()
    }

    static func makeMalformedBackupFile() throws -> URL {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("warden-ui-test-\(UUID().uuidString)")
            .appendingPathExtension("json")
        try Data("not a Warden chat backup".utf8).write(to: fileURL, options: .atomic)
        return fileURL
    }

    static func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons[identifier]
    }
}
