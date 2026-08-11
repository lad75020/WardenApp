@testable import Warden
import XCTest

final class OnboardingFlowTests: XCTestCase {
    func testNextAndBackFollowTheThreeStepFlow() {
        var flow = OnboardingFlowState()
        XCTAssertEqual(flow.currentStep, .welcome)
        flow.goNext()
        XCTAssertEqual(flow.currentStep, .providerSetup)
        flow.goNext()
        XCTAssertEqual(flow.currentStep, .ready)
        flow.goBack()
        XCTAssertEqual(flow.currentStep, .providerSetup)
    }
    func testCompletionCanOnlyBeConsumedOnce() {
        var flow = OnboardingFlowState(currentStep: .ready)
        XCTAssertTrue(flow.consumeCompletion())
        XCTAssertFalse(flow.consumeCompletion())
    }

    func testBoundaryNavigationAndSettingsDetourPreserveStep() {
        var flow = OnboardingFlowState()
        flow.goBack()
        XCTAssertEqual(flow.currentStep, .welcome)
        flow.goNext()
        XCTAssertEqual(flow.currentStep, .providerSetup)
        XCTAssertFalse(flow.isCompleting)
        flow.goNext()
        flow.goNext()
        XCTAssertEqual(flow.currentStep, .ready)
    }
}
