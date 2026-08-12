import XCTest
@testable import Warden

@MainActor
final class MessageManagerSearchTests: XCTestCase {
    private func fixtureSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SearchManagerURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    func testSearchFailureDoesNotInvokeProviderAndClearsWaitingState() async {
        let fixture = InMemoryChatFixture()
        let service = TavilySearchService(session: fixtureSession(), apiKeyProvider: { nil })
        var providerWasCalled = false
        let manager = MessageManager(
            apiService: FixtureAPIService(),
            viewContext: fixture.persistence.container.viewContext,
            fetchStreamTools: false,
            tavilyService: service
        ) { _, _, _, _, _ in
            providerWasCalled = true
            return nil
        }

        let result = await sendSearch(manager, "raw private prompt", in: fixture.chat)

        XCTAssertTrue(providerWasCalled == false)
        XCTAssertFalse(fixture.chat.waitingForResponse)
        guard case .failure(let error) = result else { return XCTFail("Expected search failure") }
        XCTAssertTrue(error is TavilyError)
    }

    func testInvalidSearchResponseDoesNotInvokeProviderOrPersistAssistant() async {
        SearchManagerURLProtocol.response = (200, "not JSON")
        defer { SearchManagerURLProtocol.reset() }

        let fixture = InMemoryChatFixture()
        let service = TavilySearchService(session: fixtureSession(), apiKeyProvider: { "fixture-key" })
        var providerWasCalled = false
        let manager = MessageManager(
            apiService: FixtureAPIService(),
            viewContext: fixture.persistence.container.viewContext,
            fetchStreamTools: false,
            tavilyService: service
        ) { _, _, _, _, _ in
            providerWasCalled = true
            return nil
        }

        let result = await sendSearch(manager, "raw private prompt", in: fixture.chat)

        XCTAssertFalse(providerWasCalled)
        XCTAssertFalse(fixture.chat.waitingForResponse)
        XCTAssertTrue(fixture.chat.messagesArray.isEmpty)
        guard case .failure(let error) = result else { return XCTFail("Expected invalid-response search failure") }
        XCTAssertTrue(error is TavilyError)
    }

    func testCancellingSearchPreventsProviderPersistenceAndStaleStatus() async throws {
        SearchManagerURLProtocol.response = (200, """
        {"query":"raw prompt","results":[{"title":"Source","url":"https://example.com","content":"fixture","score":0.9}]}
        """)
        SearchManagerURLProtocol.delay = 0.15
        let searchStarted = expectation(description: "search request started")
        SearchManagerURLProtocol.onRequestStart = { searchStarted.fulfill() }
        defer { SearchManagerURLProtocol.reset() }

        let fixture = InMemoryChatFixture()
        let service = TavilySearchService(session: fixtureSession(), apiKeyProvider: { "fixture-key" })
        var providerWasCalled = false
        let manager = MessageManager(
            apiService: FixtureAPIService(),
            viewContext: fixture.persistence.container.viewContext,
            fetchStreamTools: false,
            tavilyService: service
        ) { _, _, _, _, _ in
            providerWasCalled = true
            return nil
        }
        let completion = expectation(description: "cancelled search must not complete")
        completion.isInverted = true

        Task { @MainActor in
            await manager.sendMessageStreamWithSearch(
                "raw prompt",
                in: fixture.chat,
                contextSize: 10,
                useWebSearch: true
            ) { _ in
                completion.fulfill()
            }
        }
        await fulfillment(of: [searchStarted], timeout: 1)
        manager.stopStreaming(in: fixture.chat)

        XCTAssertNil(manager.searchStatus)
        await fulfillment(of: [completion], timeout: 0.5)
        XCTAssertFalse(providerWasCalled)
        XCTAssertFalse(fixture.chat.waitingForResponse)
        XCTAssertTrue(fixture.chat.messagesArray.isEmpty)
        XCTAssertTrue(fixture.chat.requestMessages.isEmpty)
        XCTAssertNil(manager.searchStatus)
    }

    func testSearchUsesRawPromptAndAttachesMetadataOnlyToItsAssistantResponse() async {
        SearchManagerURLProtocol.response = (200, """
        {"query":"raw prompt","results":[{"title":"Source","url":"https://example.com","content":"fixture","score":0.9}]}
        """)
        defer { SearchManagerURLProtocol.response = nil }

        let fixture = InMemoryChatFixture()
        let service = TavilySearchService(session: fixtureSession(), apiKeyProvider: { "fixture-key" })
        var providerMessages: [[String: String]] = []
        let manager = MessageManager(
            apiService: FixtureAPIService(),
            viewContext: fixture.persistence.container.viewContext,
            fetchStreamTools: false,
            tavilyService: service
        ) { _, messages, _, _, onChunk in
            providerMessages = messages
            await onChunk("answer [1]")
            return nil
        }

        let result = await sendSearch(manager, "payload with presentation tag", rawQuery: "raw prompt", in: fixture.chat)

        guard case .success = result else { return XCTFail("Expected successful search send") }
        XCTAssertTrue(providerMessages.contains { $0["content"]?.contains("User asked: raw prompt") == true })
        XCTAssertFalse(providerMessages.contains { $0["content"]?.contains("payload with presentation tag") == true })
        guard let assistant = fixture.chat.messagesArray.first(where: { !$0.own }) else {
            return XCTFail("Expected an assistant response")
        }
        XCTAssertEqual(assistant.searchMetadata?.query, "raw prompt")
        XCTAssertEqual(assistant.searchMetadata?.sources.map(\.url), ["https://example.com"])
    }

    func testNonStreamingSearchAttachesMetadataOnlyToMatchingAssistantResponse() async {
        SearchManagerURLProtocol.response = (200, """
        {"query":"raw prompt","results":[{"title":"Source","url":"https://example.com","content":"fixture","score":0.9}]}
        """)
        defer { SearchManagerURLProtocol.reset() }

        let fixture = InMemoryChatFixture()
        let service = TavilySearchService(session: fixtureSession(), apiKeyProvider: { "fixture-key" })
        var providerMessages: [[String: String]] = []
        let manager = MessageManager(
            apiService: FixtureAPIService(),
            viewContext: fixture.persistence.container.viewContext,
            fetchStreamTools: false,
            tavilyService: service,
            messageDispatcher: { _, messages, _, _, completion in
                providerMessages = messages
                completion(.success(("answer [1]", nil)))
            }
        )

        let result = await sendNonStreamingSearch(manager, "decorated payload", rawQuery: "raw prompt", in: fixture.chat)

        guard case .success = result else { return XCTFail("Expected successful non-streaming search send") }
        XCTAssertTrue(providerMessages.contains { $0["content"]?.contains("User asked: raw prompt") == true })
        guard let assistant = fixture.chat.messagesArray.first(where: { !$0.own }) else {
            return XCTFail("Expected an assistant response")
        }
        XCTAssertEqual(assistant.searchMetadata?.query, "raw prompt")
        XCTAssertEqual(assistant.searchMetadata?.sources.map(\.url), ["https://example.com"])
    }

    func testSearchMetadataDoesNotLeakToFollowingPlainRequest() async {
        SearchManagerURLProtocol.response = (200, """
        {"query":"raw prompt","results":[{"title":"Source","url":"https://example.com","content":"fixture","score":0.9}]}
        """)
        defer { SearchManagerURLProtocol.reset() }

        let fixture = InMemoryChatFixture()
        let service = TavilySearchService(session: fixtureSession(), apiKeyProvider: { "fixture-key" })
        let manager = MessageManager(
            apiService: FixtureAPIService(),
            viewContext: fixture.persistence.container.viewContext,
            fetchStreamTools: false,
            tavilyService: service
        ) { _, messages, _, _, onChunk in
            await onChunk(messages.contains { $0["content"]?.contains("User asked: raw prompt") == true } ? "search answer [1]" : "plain answer")
            return nil
        }

        let searchResult = await sendSearch(manager, "decorated payload", rawQuery: "raw prompt", in: fixture.chat)
        guard case .success = searchResult else { return XCTFail("Expected successful search send") }
        try await sendStream(manager, "plain follow-up", in: fixture.chat)

        let assistants = fixture.chat.messagesArray.filter { !$0.own }
        XCTAssertEqual(assistants.count, 2)
        XCTAssertEqual(assistants[0].searchMetadata?.query, "raw prompt")
        XCTAssertNil(assistants[1].searchMetadata)
    }

    private func sendNonStreamingSearch(_ manager: MessageManager, _ message: String, rawQuery: String? = nil, in chat: ChatEntity) async -> Result<Void, Error> {
        await withCheckedContinuation { continuation in
            Task { @MainActor in
                await manager.sendMessageWithSearch(
                    message,
                    in: chat,
                    contextSize: 10,
                    useWebSearch: true,
                    rawSearchQuery: rawQuery
                ) { result in
                    continuation.resume(returning: result)
                }
            }
        }
    }

    private func sendSearch(_ manager: MessageManager, _ message: String, rawQuery: String? = nil, in chat: ChatEntity) async -> Result<Void, Error> {
        await withCheckedContinuation { continuation in
            Task { @MainActor in
                await manager.sendMessageStreamWithSearch(
                    message,
                    in: chat,
                    contextSize: 10,
                    useWebSearch: true,
                    rawSearchQuery: rawQuery
                ) { result in
                    continuation.resume(returning: result)
                }
            }
        }
    }

    private func sendStream(_ manager: MessageManager, _ message: String, in chat: ChatEntity) async throws {
        try await withCheckedThrowingContinuation { continuation in
            manager.sendMessageStream(message, in: chat, contextSize: 10) { result in
                continuation.resume(with: result)
            }
        }
    }
}

private final class SearchManagerURLProtocol: URLProtocol {
    static var response: (statusCode: Int, body: String)?
    static var delay: TimeInterval = 0
    static var onRequestStart: (() -> Void)?

    static func reset() {
        response = nil
        delay = 0
        onRequestStart = nil
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let response = Self.response else { return }
        Self.onRequestStart?()
        let respond = { [weak self] in
            guard let self else { return }
            let http = HTTPURLResponse(url: self.request.url!, statusCode: response.statusCode, httpVersion: nil, headerFields: nil)!
            self.client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
            self.client?.urlProtocol(self, didLoad: Data(response.body.utf8))
            self.client?.urlProtocolDidFinishLoading(self)
        }
        if Self.delay > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.delay, execute: respond)
        } else {
            respond()
        }
    }

    override func stopLoading() { }
}
