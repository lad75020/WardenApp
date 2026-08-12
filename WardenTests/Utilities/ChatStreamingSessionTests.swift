import XCTest
@testable import Warden

@MainActor
final class ChatStreamingSessionTests: XCTestCase {
    func testSessionsAreIsolatedAndRejectStaleCallbacks() {
        let registry = ChatStreamingSessionRegistry()
        let conversationA = UUID()
        let conversationB = UUID()
        let requestA = UUID()
        let replacementA = UUID()
        let requestB = UUID()

        let sessionA = registry.session(for: conversationA)
        let sessionB = registry.session(for: conversationB)
        XCTAssertFalse(sessionA === sessionB)

        sessionA.begin(requestID: requestA)
        XCTAssertTrue(sessionA.append("first", requestID: requestA))
        sessionA.begin(requestID: replacementA)

        XCTAssertFalse(sessionA.append(" stale", requestID: requestA))
        XCTAssertTrue(sessionA.append("current", requestID: replacementA))
        sessionA.publishPending(requestID: replacementA)
        XCTAssertEqual(sessionA.visibleAssistantText, "current")

        sessionB.begin(requestID: requestB)
        XCTAssertTrue(sessionB.append("B", requestID: requestB))
        sessionB.publishPending(requestID: requestB)
        XCTAssertEqual(sessionB.visibleAssistantText, "B")
        XCTAssertEqual(sessionA.visibleAssistantText, "current")
    }

    func testFinalizationAndCancellationAreExactlyOnce() {
        let session = ChatStreamingSession(conversationID: UUID())
        let request = UUID()
        session.begin(requestID: request)

        XCTAssertTrue(session.cancel(requestID: request))
        XCTAssertEqual(session.phase, .cancelling)
        XCTAssertFalse(session.cancel(requestID: request))
        XCTAssertTrue(session.claimFinalization(requestID: request))
        XCTAssertFalse(session.claimFinalization(requestID: request))
        XCTAssertFalse(session.append("late", requestID: request))
    }

    func testAttachmentMarkerDetectorFindsMarkersSplitAcrossChunks() {
        var detector = AttachmentMarkerDetector()

        XCTAssertFalse(detector.consume("before <ima"))
        XCTAssertTrue(detector.consume("ge-uuid>asset</image-uuid>"))

        detector = AttachmentMarkerDetector()
        XCTAssertFalse(detector.consume("<fi"))
        XCTAssertTrue(detector.consume("le-uuid>file</file-uuid>"))
    }
}

final class StreamingTaskControllerTests: XCTestCase {
    func testKeyedReplacementAndInvalidationDoNotCrossConversations() async {
        let controller = StreamingTaskController()
        let conversationA = UUID()
        let conversationB = UUID()
        let requestA = UUID()
        let requestB = UUID()

        await controller.replace(conversationID: conversationA, requestID: requestA, task: Task {})
        await controller.replace(conversationID: conversationB, requestID: requestB, task: Task {})
        let aIsCurrent = await controller.isCurrent(conversationID: conversationA, requestID: requestA)
        let bIsCurrent = await controller.isCurrent(conversationID: conversationB, requestID: requestB)
        XCTAssertTrue(aIsCurrent)
        XCTAssertTrue(bIsCurrent)

        await controller.invalidate(conversationID: conversationA)
        let aWasInvalidated = await controller.isCurrent(conversationID: conversationA, requestID: requestA)
        let bRemainsCurrent = await controller.isCurrent(conversationID: conversationB, requestID: requestB)
        XCTAssertFalse(aWasInvalidated)
        XCTAssertTrue(bRemainsCurrent)
    }

    func testCancellationTombstoneRejectsLateTaskRegistration() async {
        let controller = StreamingTaskController()
        let conversation = UUID()
        let request = UUID()
        let task = Task<Void, Never> {}

        await controller.cancel(conversationID: conversation, requestID: request)
        await controller.replace(conversationID: conversation, requestID: request, task: task)

        XCTAssertFalse(await controller.isCurrent(conversationID: conversation, requestID: request))
        XCTAssertTrue(task.isCancelled)
    }
}
