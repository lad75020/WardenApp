import XCTest

enum PersistenceRecoveryTestSupport {
    private enum Fixture: String {
        case unavailable
        case validHistory = "valid-history"
    }

    static func launchApp(hasCandidate: Bool) -> XCUIApplication {
        launchApp(fixture: .unavailable, hasCandidate: hasCandidate)
    }

    static func launchAppWithValidPersistedHistory(testCase: XCTestCase) -> XCUIApplication {
        launchApp(fixture: .validHistory, hasCandidate: false, testCase: testCase)
    }

    static func relaunchApp(_ app: XCUIApplication) {
        app.terminate()
        app.launchEnvironment["WARDEN_APP_SHELL_UI_TEST_RESET_DEFAULTS"] = "0"
        app.launchEnvironment["WARDEN_PERSISTENCE_RECOVERY_RESET_STORE"] = "0"
        app.launch()
    }

    private static func launchApp(
        fixture: Fixture,
        hasCandidate: Bool,
        testCase: XCTestCase? = nil
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-AppShellUITestMode", "YES",
            "-PersistenceRecoveryUITestMode", "YES",
            "-lastOpenedChatId", "00000000-0000-0000-0000-000000000002"
        ]
        if fixture == .validHistory {
            app.launchArguments += ["-PersistenceRecoveryPersistentFixtureMode", "YES"]
        }
        app.launchEnvironment["WARDEN_APP_SHELL_UI_TEST"] = "1"
        app.launchEnvironment["WARDEN_APP_SHELL_UI_TEST_DEFAULTS_SUITE"] =
            "com.warden.PersistenceRecoveryUITests.\(UUID().uuidString)"
        app.launchEnvironment["WARDEN_APP_SHELL_UI_TEST_RESET_DEFAULTS"] = "1"
        app.launchEnvironment["WARDEN_PERSISTENCE_RECOVERY_FIXTURE"] = fixture.rawValue
        app.launchEnvironment["WARDEN_PERSISTENCE_RECOVERY_HAS_CANDIDATE"] = hasCandidate ? "1" : "0"
        if fixture == .validHistory {
            app.launchEnvironment["WARDEN_PERSISTENCE_RECOVERY_STORE_ID"] = UUID().uuidString
            app.launchEnvironment["WARDEN_PERSISTENCE_RECOVERY_RESET_STORE"] = "1"
        }
        app.launch()
        return app
    }

}
