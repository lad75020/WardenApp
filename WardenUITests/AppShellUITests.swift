import XCTest

final class AppShellUITests: XCTestCase {
    func testSetupRequiredWelcomeExposesSetupAndSettings() {
        let app = AppShellTestSupport.launchApp()
        XCTAssertTrue(AppShellTestSupport.element("welcome.container", in: app).waitForExistence(timeout: 10))
        XCTAssertTrue(AppShellTestSupport.element("welcome.startSetup", in: app).exists)
        XCTAssertTrue(AppShellTestSupport.element("welcome.openSettings", in: app).exists)
    }
    func testOnboardingNavigationAndSettingsAreReachable() {
        let app = AppShellTestSupport.launchApp()
        AppShellTestSupport.element("welcome.startSetup", in: app).tap()
        let next = AppShellTestSupport.element("onboarding.next", in: app)
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        next.tap()
        XCTAssertTrue(AppShellTestSupport.element("onboarding.openSettings", in: app).exists)
        XCTAssertTrue(AppShellTestSupport.element("onboarding.back", in: app).exists)
    }
}
