import XCTest
@testable import Warden

final class MessageListScrollBehaviorTests: XCTestCase {
    func testNearBottomFollowsStreamingOutput() {
        XCTAssertTrue(MessageListScrollBehavior.shouldFollowStreaming(distanceFromBottom: 24, threshold: 48))
    }

    func testIntentionalUpwardScrollDoesNotFollowStreamingOutput() {
        XCTAssertFalse(MessageListScrollBehavior.shouldFollowStreaming(distanceFromBottom: 160, threshold: 48))
    }

    func testFinalPersistedMessageDoesNotFollowWhenUserIsScrolling() {
        XCTAssertFalse(MessageListScrollBehavior.shouldAutoScrollPersistedMessage(
            isStreaming: false,
            userIsScrolling: true
        ))
    }
}
