import XCTest
@testable import Warden

final class APIServiceConfigurationTests: XCTestCase {
    func testCredentialBearingRemoteHTTPIsRejected() {
        let credential = String(repeating: "x", count: 24)
        let result = APIServiceManager.validateEndpoint(
            "http://provider.example/v1",
            credential: credential
        )

        XCTAssertEqual(result, .failure(.insecureCredentialTransport))
    }

    func testTokenlessRemoteHTTPAndCredentialBearingLoopbackAreAccepted() {
        XCTAssertEqual(
            APIServiceManager.validateEndpoint("http://provider.example/v1", credential: ""),
            .success(URL(string: "http://provider.example/v1")!)
        )

        let credential = String(repeating: "x", count: 24)
        XCTAssertEqual(
            APIServiceManager.validateEndpoint("http://127.0.0.1:11434/v1", credential: credential),
            .success(URL(string: "http://127.0.0.1:11434/v1")!)
        )
    }

    func testMalformedOrUnsupportedEndpointsAreRejectedBeforeNetworkWork() {
        XCTAssertEqual(
            APIServiceManager.validateEndpoint("not a URL", credential: ""),
            .failure(.invalidEndpoint)
        )
        XCTAssertEqual(
            APIServiceManager.validateEndpoint("ftp://provider.example/v1", credential: ""),
            .failure(.invalidEndpoint)
        )
    }

    func testUserSafeErrorNeverIncludesSensitiveText() {
        let sensitiveText = String(repeating: "s", count: 28)
        let error = APIError.serverError("response " + sensitiveText)
        XCTAssertEqual(
            APIServiceManager.userSafeErrorMessage(for: error),
            "The service returned an error. Please try again later."
        )
        XCTAssertFalse(
            APIServiceManager.userSafeErrorMessage(for: error).contains(sensitiveText)
        )
    }

    func testImageGenerationStreamingIsDisabled() {
        XCTAssertFalse(APIServiceManager.allowsStreaming(providerType: "ChatGPT Image", model: "gpt-image-1"))
        XCTAssertFalse(APIServiceManager.allowsStreaming(providerType: "chatgpt", model: "gpt-image-1"))
        XCTAssertTrue(APIServiceManager.allowsStreaming(providerType: "chatgpt", model: "gpt-4o"))
    }
}
