import XCTest
@testable import Warden

@MainActor
final class LocalProviderTests: XCTestCase {
    private func localConfig(name: String, url: String = "http://127.0.0.1:11434/api/chat", model: String = "local") -> APIServiceConfig {
        APIServiceConfig(name: name, apiUrl: URL(string: url)!, apiKey: "", model: model)
    }

    func testLocalEndpointPolicyAllowsLoopbackAndPrivateLAN() {
        let allowed = [
            "http://localhost:11434/api/chat", "http://127.0.0.1:1234/v1",
            "http://10.0.0.5:11434", "http://172.16.5.8:1234",
            "http://192.168.1.10:1234", "http://[::1]:1234", "http://[fd00::1]:1234"
        ]
        allowed.forEach { XCTAssertTrue(LocalEndpointPolicy.allows(URL(string: $0)!)) }
    }

    func testLocalEndpointPolicyRejectsPublicAndNonHTTPURLs() {
        ["http://8.8.8.8:11434", "https://provider.example/v1", "file:///tmp/model"].forEach {
            XCTAssertFalse(LocalEndpointPolicy.allows(URL(string: $0)!))
        }
    }

    func testOllamaAndLMStudioRejectPublicEndpointsBeforeRequestDispatch() {
        let publicURL = "https://provider.example/v1/chat/completions"
        let ollama = OllamaHandler(config: localConfig(name: "ollama", url: publicURL), session: .shared, streamingSession: .shared)
        let lmStudio = LMStudioHandler(config: localConfig(name: "lmstudio", url: publicURL), session: .shared, streamingSession: .shared)

        XCTAssertThrowsError(try ollama.prepareRequest(requestMessages: [], tools: nil, model: "local", temperature: 0.2, stream: false))
        XCTAssertThrowsError(try lmStudio.prepareRequest(requestMessages: [], tools: nil, model: "local", temperature: 0.2, stream: false))
    }

    func testFactoryRoutesEachLocalProviderToItsLocalService() {
        XCTAssertTrue(APIServiceFactory.createAPIService(config: localConfig(name: "ollama", model: "llama3")) is OllamaHandler)
        XCTAssertTrue(APIServiceFactory.createAPIService(config: localConfig(name: "lmstudio")) is LMStudioHandler)
        XCTAssertTrue(APIServiceFactory.createAPIService(config: localConfig(name: "huggingface")) is HuggingFaceService)
        XCTAssertTrue(APIServiceFactory.createAPIService(config: localConfig(name: "coreml llm", model: "/tmp/model")) is CoreMLTextGenerationService)
        XCTAssertTrue(APIServiceFactory.createAPIService(config: localConfig(name: "mlx", model: "flux-dev")) is MLXHandler)
    }

    func testLocalStreamingDeltaDoesNotRepeatCumulativeText() {
        XCTAssertEqual(CoreMLTextGenerationService.streamingDelta(previous: "Hello", current: "Hello world"), " world")
        XCTAssertEqual(CoreMLTextGenerationService.streamingDelta(previous: "Hello", current: "Hello"), "")
        XCTAssertEqual(CoreMLTextGenerationService.streamingDelta(previous: "Hello", current: "Replaced"), "Replaced")
        XCTAssertEqual(HuggingFaceService.streamingDelta(previous: "Hello", current: "Hello world"), " world")
        XCTAssertEqual(HuggingFaceService.streamingDelta(previous: "Hello", current: "Hello"), "")
        XCTAssertEqual(HuggingFaceService.streamingDelta(previous: "Hello", current: "Replaced"), "Replaced")
    }

    func testCoreMLDirectoryValidationRejectsMissingOrNonDirectoryPath() {
        XCTAssertThrowsError(try CoreMLTextGenerationService.validateModelDirectory(at: URL(fileURLWithPath: "/tmp/does-not-exist")))
        XCTAssertThrowsError(try CoreMLTextGenerationService.validateModelDirectory(at: URL(fileURLWithPath: "/dev/null")))
    }

    func testHuggingFaceDirectoryValidationRejectsTraversalAndUnavailablePaths() {
        XCTAssertThrowsError(try HuggingFaceService.modelDirectoryURL(for: "../outside"))
        XCTAssertThrowsError(try HuggingFaceService.validateModelDirectory(at: URL(fileURLWithPath: "/tmp/does-not-exist")))
    }

    func testLocalMetadataFetcherRetainsProviderIdentityAndFreePricing() async throws {
        let metadata = try await LocalModelMetadataFetcher(provider: "ollama").fetchMetadata(for: "llama3", apiKey: "")
        XCTAssertEqual(metadata.provider, "ollama")
        XCTAssertEqual(metadata.modelId, "llama3")
        XCTAssertEqual(metadata.pricing?.inputPer1M, 0)
        XCTAssertEqual(metadata.pricing?.outputPer1M, 0)
    }

    func testEmptyLocalRefreshKeepsExistingMetadataWhileRemoteRefreshReplacesIt() {
        let existing = ["llama3": ModelMetadata.freeSelfHosted(modelId: "llama3", provider: "ollama", context: nil)]
        XCTAssertFalse(ModelMetadataCache.shouldReplaceCachedMetadata(provider: "ollama", existing: existing, refreshed: [:]))
        XCTAssertTrue(ModelMetadataCache.shouldReplaceCachedMetadata(provider: "ollama", existing: nil, refreshed: [:]))
        XCTAssertTrue(ModelMetadataCache.shouldReplaceCachedMetadata(provider: "chatgpt", existing: existing, refreshed: [:]))
    }
}
