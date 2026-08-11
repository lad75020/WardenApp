import XCTest

final class PersistenceRecoveryUITests: XCTestCase {
    func testValidPersistedHistoryIsRestoredAfterTerminateAndRelaunch() {
        let app = PersistenceRecoveryTestSupport.launchAppWithValidPersistedHistory(testCase: self)
        assertValidPersistedHistory(in: app)

        PersistenceRecoveryTestSupport.relaunchApp(app)
        assertValidPersistedHistory(in: app)
    }

    func testUnavailableChatWithoutCandidateOffersSettingsAndDeleteControl() {
        let app = PersistenceRecoveryTestSupport.launchApp(hasCandidate: false)
        XCTAssertTrue(app.descendants(matching: .any)["persistenceRecovery.unavailableSummary"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["persistenceRecovery.sendingDisabled"].exists)
        XCTAssertTrue(app.buttons["persistenceRecovery.openSettings"].exists)
        XCTAssertTrue(app.buttons["persistenceRecovery.delete"].exists)
        XCTAssertFalse(app.buttons["persistenceRecovery.repair"].exists)
        XCTAssertEqual(
            app.staticTexts["persistenceRecovery.sendingDisabled"].value as? String,
            "Sending is disabled until this chat is repaired"
        )
        XCTAssertEqual(app.buttons["persistenceRecovery.openSettings"].label, "Open Service Settings")
        XCTAssertEqual(app.buttons["persistenceRecovery.delete"].label, "Delete unavailable chat")

        app.buttons["persistenceRecovery.openSettings"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["settings.apiServices"].waitForExistence(timeout: 5))
    }

    func testUnavailableChatWithCandidateRepairsOnlyAfterChoosingService() {
        let app = PersistenceRecoveryTestSupport.launchApp(hasCandidate: true)
        XCTAssertTrue(app.descendants(matching: .any)["persistenceRecovery.container"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.popUpButtons["persistenceRecovery.servicePicker"].exists)
        XCTAssertFalse(app.buttons["persistenceRecovery.repair"].isEnabled)
        let servicePicker = app.popUpButtons["persistenceRecovery.servicePicker"]
        servicePicker.click()
        let testService = app.menuItems.matching(NSPredicate(format: "title == %@", "Test service")).firstMatch
        XCTAssertTrue(testService.waitForExistence(timeout: 2))
        testService.click()
        XCTAssertTrue(app.buttons["persistenceRecovery.repair"].isEnabled)
        XCTAssertEqual(app.popUpButtons["persistenceRecovery.servicePicker"].label, "Choose a service to repair this chat")
        XCTAssertEqual(app.buttons["persistenceRecovery.repair"].label, "Repair chat using selected service")

        // Keyboard focus reaches the repair action: Tab moves focus onto it and Return
        // activates the focused control, clearing recovery without a pointer tap.
        app.typeKey(.tab, modifierFlags: [])
        app.typeKey(.return, modifierFlags: [])
        XCTAssertFalse(
            app.descendants(matching: .any)["persistenceRecovery.unavailableSummary"]
                .waitForExistence(timeout: 1),
            "Keyboard-activated repair should remove the unavailable chat"
        )
        XCTAssertFalse(app.buttons["persistenceRecovery.delete"].exists)
    }

    func testDeleteRequiresConfirmationBeforeRemovingUnavailableChat() {
        let app = PersistenceRecoveryTestSupport.launchApp(hasCandidate: false)
        let unavailable = app.descendants(matching: .any)["persistenceRecovery.unavailableSummary"]
        XCTAssertTrue(unavailable.waitForExistence(timeout: 5))

        app.buttons["persistenceRecovery.delete"].tap()
        let confirmation = app.sheets.firstMatch
        XCTAssertTrue(confirmation.waitForExistence(timeout: 2))
        let cancel = confirmation.buttons["Cancel deletion"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 2))
        cancel.tap()
        XCTAssertTrue(unavailable.exists)

        app.buttons["persistenceRecovery.delete"].tap()
        XCTAssertTrue(confirmation.waitForExistence(timeout: 2))
        let delete = confirmation.buttons["Confirm deletion of unavailable chat"]
        XCTAssertTrue(delete.waitForExistence(timeout: 2))
        delete.tap()
        XCTAssertFalse(unavailable.waitForExistence(timeout: 1))
    }

    private func assertValidPersistedHistory(in app: XCUIApplication) {
        // The restored chat's persisted messages are the authoritative evidence that the
        // same valid history survived terminate/relaunch from the on-disk Core Data store.
        let request = app.staticTexts.matching(NSPredicate(format: "value == %@", "Fixture request")).firstMatch
        let response = app.staticTexts.matching(NSPredicate(format: "value == %@", "Fixture response")).firstMatch
        XCTAssertTrue(request.waitForExistence(timeout: 5))
        XCTAssertTrue(response.waitForExistence(timeout: 5))
        XCTAssertLessThan(request.frame.minY, response.frame.minY)
        XCTAssertFalse(app.descendants(matching: .any)["persistenceRecovery.unavailableSummary"].exists)
    }
}
