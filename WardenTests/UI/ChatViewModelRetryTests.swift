import XCTest
@testable import Warden

@MainActor
final class ChatViewModelRetryTests: XCTestCase {
    func testRetryIntentTargetsConcreteUserTurnAndFollowingAssistant() {
        let fixture = InMemoryChatFixture()
        let user = fixture.addMessage("retry this", own: true)
        let assistant = fixture.addMessage("old response", own: false)
        let model = ChatViewModel(chat: fixture.chat, viewContext: fixture.persistence.container.viewContext)

        let intent = model.retryIntent(for: user)

        XCTAssertTrue(intent?.userTurn === user)
        XCTAssertTrue(intent?.assistantTarget === assistant)
    }

    func testConfigurationErrorIsNotRetryable() {
        XCTAssertEqual(ChatViewModel.retryState(for: APIError.noApiService("missing")), .configurationError)
    }

    func testRetryRoutesNonStreamingConfigurationThroughNonStreamingManager() async throws {
        let fixture = InMemoryChatFixture()
        let user = fixture.addMessage("retry this", own: true)
        let assistant = fixture.addMessage("old response", own: false)
        let service = RecordingNonStreamingAPIService(result: .success(("new response", nil)))
        let manager = MessageManager(apiService: service, viewContext: fixture.persistence.container.viewContext, fetchStreamTools: false)
        let model = ChatViewModel(chat: fixture.chat, viewContext: fixture.persistence.container.viewContext)
        model.messageManager = manager

        try await withCheckedThrowingContinuation { continuation in
            model.retryLastTurn(contextSize: 10, useStreamResponse: false) { result in
                continuation.resume(with: result)
            }
        }

        XCTAssertEqual(service.requests.count, 1)
        XCTAssertEqual(fixture.chat.messagesArray.filter { $0.own }.map(\.body), [user.body])
        XCTAssertEqual(fixture.chat.messagesArray.filter { !$0.own }.map(\.body), ["new response"])
        XCTAssertTrue(fixture.chat.messagesArray.filter { !$0.own }.first === assistant)
        XCTAssertFalse(fixture.chat.waitingForResponse)
    }
}
