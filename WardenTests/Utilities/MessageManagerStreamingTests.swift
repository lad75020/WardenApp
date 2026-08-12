import XCTest
@testable import Warden

@MainActor
final class MessageManagerStreamingTests: XCTestCase {
    func testOrderedChunksPersistExactlyOnceAndClearWaitingState() async throws {
        let fixture = InMemoryChatFixture()
        let service = DeterministicStreamingService(chunks: ["hel", "lo", " world"])
        let manager = MessageManager(apiService: FixtureAPIService(), viewContext: fixture.persistence.container.viewContext, fetchStreamTools: false) { _, _, _, _, onChunk in
            try await service.run(onChunk: onChunk)
            return nil
        }

        try await send(manager, "prompt", in: fixture.chat)

        XCTAssertFalse(fixture.chat.waitingForResponse)
        XCTAssertEqual(fixture.chat.messagesArray.filter { !$0.own }.map(\.body), ["hello world"])
        XCTAssertEqual(fixture.chat.requestMessages.filter { $0["role"] == "assistant" }.map { $0["content"] }, ["hello world"])
    }

    func testAttachmentBoundaryChunkPersistsExactlyOnce() async throws {
        let fixture = InMemoryChatFixture()
        let boundaryChunk = "<image-uuid>attachment-1</image-uuid>"
        let expectedResponse = "Before \(boundaryChunk) after"
        let service = DeterministicStreamingService(chunks: ["Before ", boundaryChunk, " after"])
        let manager = MessageManager(apiService: FixtureAPIService(), viewContext: fixture.persistence.container.viewContext, fetchStreamTools: false) { _, _, _, _, onChunk in
            try await service.run(onChunk: onChunk)
            return nil
        }

        try await send(manager, "prompt", in: fixture.chat)

        let persistedAssistantText = fixture.chat.messagesArray.filter { !$0.own }.map(\.body)
        XCTAssertEqual(persistedAssistantText, [expectedResponse])
        XCTAssertEqual(persistedAssistantText.joined().components(separatedBy: boundaryChunk).count - 1, 1)
    }

    func testEmptySuccessAndFailureClearWaitingStateWithoutAssistant() async throws {
        let fixture = InMemoryChatFixture()
        let empty = MessageManager(apiService: FixtureAPIService(), viewContext: fixture.persistence.container.viewContext, fetchStreamTools: false) { _, _, _, _, _ in nil }
        await XCTAssertThrowsErrorAsync { try await self.send(empty, "prompt", in: fixture.chat) }
        XCTAssertFalse(fixture.chat.waitingForResponse)
        XCTAssertTrue(fixture.chat.messagesArray.isEmpty)

        let failing = MessageManager(apiService: FixtureAPIService(), viewContext: fixture.persistence.container.viewContext, fetchStreamTools: false) { _, _, _, _, _ in
            throw DeterministicStreamingService.FixtureError.controlledFailure
        }
        await XCTAssertThrowsErrorAsync { try await self.send(failing, "prompt", in: fixture.chat) }
        XCTAssertFalse(fixture.chat.waitingForResponse)
        XCTAssertTrue(fixture.chat.messagesArray.isEmpty)
    }

    func testCancellationRejectsLateChunksAndPersistsOnePartialAtMost() async throws {
        let fixture = InMemoryChatFixture()
        let service = DeterministicStreamingService(chunks: ["kept", " late"], delay: .milliseconds(100))
        let manager = MessageManager(apiService: FixtureAPIService(), viewContext: fixture.persistence.container.viewContext, fetchStreamTools: false) { _, _, _, _, onChunk in
            try await service.run(onChunk: onChunk)
            return nil
        }
        let completion = expectation(description: "completion")
        manager.sendMessageStream("prompt", in: fixture.chat, contextSize: 10) { _ in completion.fulfill() }
        try await Task.sleep(for: .milliseconds(130))
        manager.stopStreaming(in: fixture.chat)
        await fulfillment(of: [completion], timeout: 2)

        XCTAssertFalse(fixture.chat.waitingForResponse)
        XCTAssertEqual(fixture.chat.messagesArray.filter { !$0.own }.map(\.body), ["kept"])
    }

    func testCancellationBeforeFirstChunkPersistsNothingAndClearsWaitingState() async throws {
        let fixture = InMemoryChatFixture()
        let service = DeterministicStreamingService(chunks: ["late"], delay: .milliseconds(250))
        let manager = MessageManager(apiService: FixtureAPIService(), viewContext: fixture.persistence.container.viewContext, fetchStreamTools: false) { _, _, _, _, onChunk in
            try await service.run(onChunk: onChunk)
            return nil
        }
        let completion = expectation(description: "completion")
        manager.sendMessageStream("prompt", in: fixture.chat, contextSize: 10) { _ in completion.fulfill() }
        manager.stopStreaming(in: fixture.chat)
        await fulfillment(of: [completion], timeout: 2)

        XCTAssertFalse(fixture.chat.waitingForResponse)
        XCTAssertTrue(fixture.chat.messagesArray.isEmpty)
    }

    private func send(_ manager: MessageManager, _ message: String, in chat: ChatEntity) async throws {
        try await withCheckedThrowingContinuation { continuation in
            manager.sendMessageStream(message, in: chat, contextSize: 10) { result in
                continuation.resume(with: result)
            }
        }
    }
}

struct FixtureAPIService: APIService {
    let name = "Fixture"
    let baseURL = URL(string: "http://fixture.invalid")!
    let session = URLSession.shared
    let model = "fixture"
    func sendMessage(_: [[String: String]], tools: [[String: Any]]?, temperature: Float, completion: @escaping (Result<(String?, [ToolCall]?), APIError>) -> Void) { }
    func sendMessageStream(_: [[String: String]], tools: [[String: Any]]?, temperature: Float) async throws -> AsyncThrowingStream<(String?, [ToolCall]?), Error> { AsyncThrowingStream { $0.finish() } }
    func prepareRequest(requestMessages: [[String: String]], tools: [[String: Any]]?, model: String, temperature: Float, stream: Bool) throws -> URLRequest { URLRequest(url: baseURL) }
    func parseJSONResponse(data: Data) -> (String?, String?, [ToolCall]?)? { nil }
    func parseDeltaJSONResponse(data: Data?) -> (Bool, Error?, String?, String?, [ToolCall]?) { (false, nil, nil, nil, nil) }
}

func XCTAssertThrowsErrorAsync(_ expression: @escaping () async throws -> Void, file: StaticString = #filePath, line: UInt = #line) async {
    do { try await expression(); XCTFail("Expected error", file: file, line: line) }
    catch { }
}
