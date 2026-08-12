import XCTest
@testable import Warden

@MainActor
final class MessageManagerRetryTests: XCTestCase {
    func testNonStreamRetryUsesOriginalUserOnceAndReplacesExistingAssistant() async throws {
        let fixture = InMemoryChatFixture()
        let user = fixture.addMessage("repeat me", own: true)
        let oldAssistant = fixture.addMessage("old answer", own: false)
        let service = RecordingNonStreamingAPIService(result: .success(("new answer", nil)))
        let manager = MessageManager(apiService: service, viewContext: fixture.persistence.container.viewContext, fetchStreamTools: false)

        try await retryNonStream(manager, user: user, target: oldAssistant, in: fixture.chat)

        XCTAssertEqual(fixture.chat.messagesArray.filter { $0.own }.map(\.body), ["repeat me"])
        XCTAssertEqual(fixture.chat.messagesArray.filter { !$0.own }.map(\.body), ["new answer"])
        XCTAssertTrue(fixture.chat.messagesArray.filter { !$0.own }.first === oldAssistant)
        XCTAssertEqual(service.requests.count, 1)
        XCTAssertEqual(service.requests[0].filter { $0["role"] == "user" }.map { $0["content"] }, ["repeat me"])
        XCTAssertFalse(service.requests[0].contains { $0["content"] == "old answer" })
    }

    func testNonStreamImmediateRetryFailurePreservesExistingAssistant() async throws {
        let fixture = InMemoryChatFixture()
        let user = fixture.addMessage("repeat me", own: true)
        let oldAssistant = fixture.addMessage("old answer", own: false)
        let service = RecordingNonStreamingAPIService(result: .failure(.unknown("controlled failure")))
        let manager = MessageManager(apiService: service, viewContext: fixture.persistence.container.viewContext, fetchStreamTools: false)

        await XCTAssertThrowsErrorAsync { try await self.retryNonStream(manager, user: user, target: oldAssistant, in: fixture.chat) }

        XCTAssertEqual(fixture.chat.messagesArray.filter { !$0.own }.map(\.body), ["old answer"])
        XCTAssertFalse(fixture.chat.waitingForResponse)
    }

    func testNonStreamEmptyRetryResponsePreservesExistingAssistant() async throws {
        let fixture = InMemoryChatFixture()
        let user = fixture.addMessage("repeat me", own: true)
        let oldAssistant = fixture.addMessage("old answer", own: false)
        let service = RecordingNonStreamingAPIService(result: .success(("   ", nil)))
        let manager = MessageManager(apiService: service, viewContext: fixture.persistence.container.viewContext, fetchStreamTools: false)

        await XCTAssertThrowsErrorAsync { try await self.retryNonStream(manager, user: user, target: oldAssistant, in: fixture.chat) }

        XCTAssertEqual(fixture.chat.messagesArray.filter { !$0.own }.map(\.body), ["old answer"])
        XCTAssertFalse(fixture.chat.waitingForResponse)
    }

    func testRetryUsesOriginalUserOnceExcludesSupersededAssistantAndReplacesIt() async throws {
        let fixture = InMemoryChatFixture()
        let user = fixture.addMessage("repeat me", own: true)
        let oldAssistant = fixture.addMessage("old answer", own: false)
        var captured: [[String: String]] = []
        let manager = MessageManager(apiService: FixtureAPIService(), viewContext: fixture.persistence.container.viewContext, fetchStreamTools: false) { _, messages, _, _, onChunk in
            captured = messages
            await onChunk("new answer")
            return nil
        }

        try await retry(manager, user: user, target: oldAssistant, in: fixture.chat)

        XCTAssertEqual(fixture.chat.messagesArray.filter { $0.own }.map(\.body), ["repeat me"])
        XCTAssertEqual(fixture.chat.messagesArray.filter { !$0.own }.map(\.body), ["new answer"])
        XCTAssertEqual(captured.filter { $0["role"] == "user" }.map { $0["content"] }, ["repeat me"])
        XCTAssertFalse(captured.contains { $0["content"] == "old answer" })
    }

    func testImmediateRetryFailurePreservesExistingAssistant() async throws {
        let fixture = InMemoryChatFixture()
        let user = fixture.addMessage("repeat me", own: true)
        let oldAssistant = fixture.addMessage("old answer", own: false)
        let manager = MessageManager(apiService: FixtureAPIService(), viewContext: fixture.persistence.container.viewContext, fetchStreamTools: false) { _, _, _, _, _ in
            throw DeterministicStreamingService.FixtureError.controlledFailure
        }

        await XCTAssertThrowsErrorAsync { try await self.retry(manager, user: user, target: oldAssistant, in: fixture.chat) }
        XCTAssertEqual(fixture.chat.messagesArray.filter { !$0.own }.map(\.body), ["old answer"])
        XCTAssertFalse(fixture.chat.waitingForResponse)
    }

    private func retry(_ manager: MessageManager, user: MessageEntity, target: MessageEntity, in chat: ChatEntity) async throws {
        try await withCheckedThrowingContinuation { continuation in
            manager.retryMessageStream(userTurn: user, assistantTarget: target, in: chat, contextSize: 10) { result in
                continuation.resume(with: result)
            }
        }
    }

    private func retryNonStream(_ manager: MessageManager, user: MessageEntity, target: MessageEntity, in chat: ChatEntity) async throws {
        try await withCheckedThrowingContinuation { continuation in
            manager.retryMessage(userTurn: user, assistantTarget: target, in: chat, contextSize: 10) { result in
                continuation.resume(with: result)
            }
        }
    }
}

final class RecordingNonStreamingAPIService: APIService {
    let name = "Fixture"
    let baseURL = URL(string: "http://fixture.invalid")!
    let session = URLSession.shared
    let model = "fixture"
    private let result: Result<(String?, [ToolCall]?), APIError>
    private(set) var requests: [[[String: String]]] = []

    init(result: Result<(String?, [ToolCall]?), APIError>) {
        self.result = result
    }

    func sendMessage(
        _ requestMessages: [[String: String]],
        tools: [[String: Any]]?,
        temperature: Float,
        completion: @escaping (Result<(String?, [ToolCall]?), APIError>) -> Void
    ) {
        requests.append(requestMessages)
        completion(result)
    }

    func sendMessageStream(
        _: [[String: String]],
        tools: [[String: Any]]?,
        temperature: Float
    ) async throws -> AsyncThrowingStream<(String?, [ToolCall]?), Error> {
        AsyncThrowingStream { $0.finish() }
    }

    func prepareRequest(
        requestMessages: [[String: String]],
        tools: [[String: Any]]?,
        model: String,
        temperature: Float,
        stream: Bool
    ) throws -> URLRequest {
        URLRequest(url: baseURL)
    }

    func parseJSONResponse(data: Data) -> (String?, String?, [ToolCall]?)? { nil }

    func parseDeltaJSONResponse(data: Data?) -> (Bool, Error?, String?, String?, [ToolCall]?) {
        (false, nil, nil, nil, nil)
    }
}
