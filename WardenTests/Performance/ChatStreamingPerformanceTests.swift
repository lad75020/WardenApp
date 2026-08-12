import XCTest
@testable import Warden

@MainActor
final class ChatStreamingPerformanceTests: XCTestCase {
    func testTenThousandCharactersAreCoalescedAndFinishPromptly() async throws {
        let fixture = InMemoryChatFixture()
        let chunks = Array(repeating: String(repeating: "x", count: 100), count: 100)
        let service = DeterministicStreamingService(chunks: chunks)
        let manager = MessageManager(apiService: FixtureAPIService(), viewContext: fixture.persistence.container.viewContext, fetchStreamTools: false) { _, _, _, _, onChunk in
            try await service.run(onChunk: onChunk)
            return nil
        }
        let started = ContinuousClock.now

        try await withCheckedThrowingContinuation { continuation in
            manager.sendMessageStream("performance", in: fixture.chat, contextSize: 10) { result in
                continuation.resume(with: result)
            }
        }

        XCTAssertEqual(fixture.chat.messagesArray.last?.body.count, 10_000)
        XCTAssertFalse(fixture.chat.waitingForResponse)
        XCTAssertLessThan(started.duration(to: .now), .seconds(1))
    }
}
