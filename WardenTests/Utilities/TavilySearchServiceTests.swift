import Foundation
import XCTest
@testable import Warden

final class TavilySearchServiceTests: XCTestCase {
    private func fixtureSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FixtureURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    func testOnlyAbsoluteHTTPSURLsAreActionable() {
        XCTAssertEqual(SearchSourceURL.actionableURL(from: "https://example.com/path")?.host, "example.com")
        XCTAssertNil(SearchSourceURL.actionableURL(from: "http://example.com"))
        XCTAssertNil(SearchSourceURL.actionableURL(from: "mailto:person@example.com"))
        XCTAssertNil(SearchSourceURL.actionableURL(from: "https:///missing-host"))
        XCTAssertNil(SearchSourceURL.actionableURL(from: "not a url"))
    }

    func testCitationConversionUsesOnlyStandaloneActionableSourceURLs() {
        let service = TavilySearchService(session: fixtureSession(), apiKeyProvider: { "fixture-key" })
        let text = "é [1] then x[1] and [2] and [3]."
        let converted = service.convertCitationsToLinks(
            text,
            urls: ["https://example.com/source", "http://unsafe.example", "https://example.org/third"]
        )

        XCTAssertEqual(converted, "é [1](https://example.com/source) then x[1] and [2] and [3](https://example.org/third).")
    }

    func testSearchPreservesRawURLSlotsForCitationAlignment() async throws {
        FixtureURLProtocol.response = (
            200,
            """
            {"query":"fixture","results":[
              {"title":"HTTP","url":"http://unsafe.example","content":"a","score":0.1},
              {"title":"Malformed","url":"not a url","content":"b","score":0.2},
              {"title":"HTTPS","url":"https://safe.example/source","content":"c","score":0.3}
            ]}
            """
        )
        defer { FixtureURLProtocol.response = nil }

        let service = TavilySearchService(session: fixtureSession(), apiKeyProvider: { "fixture-key" })
        let search = try await service.performSearch(query: "fixture") { _ in }

        XCTAssertEqual(search.urls, ["http://unsafe.example", "not a url", "https://safe.example/source"])
        XCTAssertEqual(
            service.convertCitationsToLinks("[1] [2] [3]", urls: search.urls),
            "[1] [2] [3](https://safe.example/source)"
        )
    }

    func testTransportErrorsNeverExposeUnderlyingMessage() {
        let error = TavilyError.networkError(NSError(
            domain: "fixture",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "query=private&api_key=secret"]
        ))

        XCTAssertFalse(error.localizedDescription.contains("private"))
        XCTAssertFalse(error.localizedDescription.contains("secret"))
    }
}

private final class FixtureURLProtocol: URLProtocol {
    static var response: (statusCode: Int, body: String)?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let response = Self.response else {
            fatalError("Network must not be contacted by this fixture")
        }
        let http = HTTPURLResponse(url: request.url!, statusCode: response.statusCode, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(response.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { }
}
