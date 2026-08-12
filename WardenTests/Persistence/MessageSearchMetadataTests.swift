import XCTest
@testable import Warden

@MainActor
final class MessageSearchMetadataTests: XCTestCase {
    func testAbsentAndMalformedMetadataDecodeAsNil() {
        let fixture = InMemoryChatFixture()
        let message = fixture.addMessage("assistant", own: false)

        XCTAssertNil(message.searchMetadata)
        message.searchMetadataJson = "not-json"
        XCTAssertNil(message.searchMetadata)
    }

    func testLegacyMetadataJSONDecodesAndMessageOwnedMetadataPersists() throws {
        let fixture = InMemoryChatFixture()
        let message = fixture.addMessage("assistant", own: false)
        let legacy = """
        {"query":"legacy query","sources":[{"title":"Source","url":"https://example.com","score":0.8}],"searchTime":0,"resultCount":1}
        """

        message.searchMetadataJson = legacy
        XCTAssertEqual(message.searchMetadata?.query, "legacy query")
        XCTAssertEqual(message.searchMetadata?.sources.count, 1)

        let metadata = MessageSearchMetadata(
            query: "new query",
            sources: [SearchSource(title: "New", url: "https://new.example", score: 1, publishedDate: nil)],
            searchTime: Date(timeIntervalSince1970: 1),
            resultCount: 1
        )
        message.searchMetadata = metadata
        try fixture.persistence.container.viewContext.save()

        XCTAssertEqual(message.searchMetadata?.query, "new query")
        XCTAssertFalse(message.searchMetadataJson?.isEmpty ?? true)
    }

    func testMetadataIsDeletedWithItsConversation() throws {
        let fixture = InMemoryChatFixture()
        let message = fixture.addMessage("assistant", own: false)
        message.searchMetadata = MessageSearchMetadata(query: "query", sources: [], searchTime: Date(), resultCount: 0)
        let context = fixture.persistence.container.viewContext
        try context.save()

        context.delete(fixture.chat)
        try context.save()

        XCTAssertEqual(message.isDeleted, true)
    }
}
