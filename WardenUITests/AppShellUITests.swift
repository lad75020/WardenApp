import XCTest

final class AppShellUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testCleanLaunchShowsSetupWelcomeAndPrimaryActions() {
        let app = AppShellTestSupport.launchApp()

        XCTAssertTrue(app.descendants(matching: .any)["welcome.container"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["welcome.startSetup"].exists)
        XCTAssertTrue(app.buttons["welcome.openSettings"].exists)
    }

    func testOnboardingNavigatesAndSettingsKeepsTheGuideRecoverable() {
        let app = AppShellTestSupport.launchApp()
        app.buttons["welcome.startSetup"].tap()

        XCTAssertTrue(app.descendants(matching: .any)["onboarding.container"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.progressIndicators["onboarding.progress"].exists)
        app.buttons["onboarding.next"].tap()
        XCTAssertTrue(app.buttons["onboarding.back"].exists)
        XCTAssertTrue(app.buttons["onboarding.openSettings"].exists)

        app.buttons["onboarding.openSettings"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["onboarding.container"].exists)
    }

    func testShellSurfacesAndCommandCommaExposeGeneralSettingsControls() {
        let app = AppShellTestSupport.launchApp()

        XCTAssertTrue(app.descendants(matching: .any)["appShell.navigation"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["appShell.sidebar"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["appShell.detail"].exists)

        app.typeKey(",", modifierFlags: .command)
        XCTAssertTrue(app.descendants(matching: .any)["settings.window"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["settings.generalTab"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["settings.theme"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["settings.chatFont"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["settings.sidebarIcons"].exists)
    }

    func testSettingsReopensAndGeneralPreferencesPersistInIsolatedTestDefaults() {
        let app = AppShellTestSupport.launchApp()
        openSettings(using: app)
        openSettings(using: app)
        XCTAssertEqual(app.windows.matching(identifier: "settings.window").count, 1)

        let theme = app.descendants(matching: .any)["settings.theme"]
        XCTAssertTrue(theme.waitForExistence(timeout: 5))
        selectTheme(theme, option: .system)
        selectTheme(theme, option: .light)
        selectTheme(theme, option: .dark)
        selectTheme(theme, option: .light)

        let chatFont = app.popUpButtons["settings.chatFont"]
        chatFont.click()
        app.menuItems["20 pt"].tap()
        XCTAssertEqual(chatFont.value as? String, "20 pt")

        let sidebarIcons = app.descendants(matching: .any)["settings.sidebarIcons"]
        XCTAssertTrue(sidebarIcons.exists)
        let originalSidebarLabel = sidebarIcons.label
        sidebarIcons.tap()
        XCTAssertNotEqual(sidebarIcons.label, originalSidebarLabel)

        let settingsWindow = app.windows["settings.window"]
        XCTAssertTrue(settingsWindow.waitForExistence(timeout: 5))
        settingsWindow.buttons[XCUIIdentifierCloseWindow].tap()
        XCTAssertFalse(settingsWindow.waitForExistence(timeout: 3))

        openSettings(using: app)
        XCTAssertTrue(app.windows["settings.window"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.descendants(matching: .any)["settings.theme"].value as? String, "Light")
        XCTAssertEqual(app.popUpButtons["settings.chatFont"].value as? String, "20 pt")
        XCTAssertNotEqual(app.descendants(matching: .any)["settings.sidebarIcons"].label, originalSidebarLabel)

        AppShellTestSupport.relaunchApp(app)
        openSettings(using: app)
        XCTAssertEqual(app.descendants(matching: .any)["settings.theme"].value as? String, "Light")
        XCTAssertEqual(app.popUpButtons["settings.chatFont"].value as? String, "20 pt")
        XCTAssertNotEqual(app.descendants(matching: .any)["settings.sidebarIcons"].label, originalSidebarLabel)
    }

    func testMalformedImportShowsNonDestructiveFeedback() throws {
        let app = AppShellTestSupport.launchApp()
        let malformedBackup = try AppShellTestSupport.makeMalformedBackupFile()
        addTeardownBlock {
            try? FileManager.default.removeItem(at: malformedBackup)
        }

        openSettings(using: app)
        app.buttons["Import"].tap()

        app.typeKey("g", modifierFlags: [.command, .shift])
        let goToFolderField = app.textFields.firstMatch
        XCTAssertTrue(goToFolderField.waitForExistence(timeout: 5))
        goToFolderField.typeText(malformedBackup.path)
        app.typeKey(.return, modifierFlags: [])
        let openPanel = app.windows["open-panel"]
        XCTAssertTrue(openPanel.waitForExistence(timeout: 5))
        openPanel.buttons["OKButton"].tap()

        XCTAssertTrue(app.staticTexts["The selected backup could not be read."].waitForExistence(timeout: 5))
    }

    private func openSettings(using app: XCUIApplication) {
        app.typeKey(",", modifierFlags: .command)
        XCTAssertTrue(app.windows["settings.window"].waitForExistence(timeout: 5))
    }

    private func selectTheme(_ theme: XCUIElement, option: ThemeOption) {
        let themeOption = theme.radioButtons[option.expectedValue]
        XCTAssertTrue(themeOption.waitForExistence(timeout: 2))
        themeOption.tap()
        XCTAssertEqual(theme.value as? String, option.expectedValue)
    }

    private enum ThemeOption {
        case system
        case light
        case dark

        var expectedValue: String {
            switch self {
            case .system: return "System"
            case .light: return "Light"
            case .dark: return "Dark"
            }
        }
    }
}
