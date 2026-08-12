import XCTest
@testable import Warden

@MainActor
final class ChatViewModelStreamingTests: XCTestCase {
    func testRecreatedViewModelsRestoreOnlyTheirConversationSession() {
        let fixture = InMemoryChatFixture()
        let other = InMemoryChatFixture()
        let a = ChatViewModel(chat: fixture.chat, viewContext: fixture.persistence.container.viewContext)
        let b = ChatViewModel(chat: other.chat, viewContext: other.persistence.container.viewContext)
        let request = UUID()

        let session = ChatStreamingSessionRegistry.shared.session(for: fixture.chat.id)
        session.begin(requestID: request)
        XCTAssertTrue(session.append("partial", requestID: request))
        session.publishPending(requestID: request)

        let recreatedA = ChatViewModel(chat: fixture.chat, viewContext: fixture.persistence.container.viewContext)
        XCTAssertEqual(recreatedA.streamingAssistantText, "partial")
        XCTAssertTrue(recreatedA.isStreaming)
        XCTAssertTrue(b.streamingAssistantText.isEmpty)
        ChatStreamingSessionRegistry.shared.invalidate(conversationID: fixture.chat.id)
    }

    func testStopAfterNavigationTargetsOriginatingConversation() {
        let fixture = InMemoryChatFixture()
        let model = ChatViewModel(chat: fixture.chat, viewContext: fixture.persistence.container.viewContext)
        let request = UUID()
        let session = ChatStreamingSessionRegistry.shared.session(for: fixture.chat.id)
        session.begin(requestID: request)

        model.stopStreaming()

        XCTAssertEqual(session.phase, .cancelling)
        ChatStreamingSessionRegistry.shared.invalidate(conversationID: fixture.chat.id)
    }

    func testInvalidationDoesNotRequireAMessageManager() {
        let fixture = InMemoryChatFixture()
        let model = ChatViewModel(chat: fixture.chat, viewContext: fixture.persistence.container.viewContext)
        let session = ChatStreamingSessionRegistry.shared.session(for: fixture.chat.id)
        session.begin(requestID: UUID())

        model.invalidateStreamingBeforeDeletion()

        XCTAssertEqual(session.phase, .idle)
        XCTAssertNil(session.requestID)
    }
}
