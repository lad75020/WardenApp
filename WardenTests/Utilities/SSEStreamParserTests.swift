import XCTest
@testable import Warden

final class SSEStreamParserTests: XCTestCase {
    func testBufferedWithCompatibilityFlushFlushesOnCompleteJSONWithoutBlankLine() async throws {
        let data = "data: {\"a\":1}\n".data(using: .utf8)!
        var events: [String] = []

        try await SSEStreamParser.parse(data: data, deliveryMode: .bufferedWithCompatibilityFlush) { payload in
            events.append(payload)
        }

        XCTAssertEqual(events, ["{\"a\":1}"])
    }

    func testBufferedWithCompatibilityFlushFlushesOnFinalUnterminatedLine() async throws {
        let data = "data: {\"a\":1}".data(using: .utf8)!
        var events: [String] = []

        try await SSEStreamParser.parse(data: data, deliveryMode: .bufferedWithCompatibilityFlush) { payload in
            events.append(payload)
        }

        XCTAssertEqual(events, ["{\"a\":1}"])
    }

    func testIgnoresCommentsAndNonDataFields() async throws {
        let data = """
        : keepalive
        event: message
        data: hello

        """.data(using: .utf8)!
        var events: [String] = []

        try await SSEStreamParser.parse(data: data, deliveryMode: .bufferedEvents) { payload in
            events.append(payload)
        }

        XCTAssertEqual(events, ["hello"])
    }

    func testFragmentedCRLFMultilineAndMalformedNeighborKeepEventOrder() async throws {
        let chunks = [
            Data("data: first\r".utf8),
            Data("\ndata: second\r\n\r\ndata: {bad}\r\n\r\ndata: final".utf8),
            Data("\r\n\r\n".utf8)
        ]
        var events: [String] = []

        try await SSEStreamParser.parse(chunks: chunks, deliveryMode: .bufferedEvents) { payload in
            events.append(payload)
        }

        XCTAssertEqual(events, ["first\nsecond", "{bad}", "final"])
    }
}

final class MLXHandlerModelTypeTests: XCTestCase {
    func testQwen3VLConfigIsDetectedAsVisionModel() throws {
        let directory = try makeTemporaryModelDirectory(config: #"{"model_type":"qwen3_vl"}"#)
        defer { try? FileManager.default.removeItem(at: directory) }

        XCTAssertEqual(MLXHandler.mlxModelType(at: directory), "qwen3_vl")
        XCTAssertTrue(MLXHandler.isMLXVisionModel(at: directory))
    }

    func testNonVisionConfigIsNotDetectedAsVisionModel() throws {
        let directory = try makeTemporaryModelDirectory(config: #"{"model_type":"llama"}"#)
        defer { try? FileManager.default.removeItem(at: directory) }

        XCTAssertEqual(MLXHandler.mlxModelType(at: directory), "llama")
        XCTAssertFalse(MLXHandler.isMLXVisionModel(at: directory))
    }

    func testQwen3VLLoadDirectoryExcludesNestedSafetensors() throws {
        let directory = try makeTemporaryModelDirectory(config: #"{"model_type":"qwen3_vl"}"#)
        defer { try? FileManager.default.removeItem(at: directory) }

        let rootWeights = directory.appendingPathComponent("model.safetensors")
        try Data("root".utf8).write(to: rootWeights)
        let extras = directory.appendingPathComponent("extras", isDirectory: true)
        try FileManager.default.createDirectory(at: extras, withIntermediateDirectories: true)
        let auxiliaryWeights = extras.appendingPathComponent("custom_heads.safetensors")
        try Data("auxiliary".utf8).write(to: auxiliaryWeights)

        let loadDirectory = try MLXHandler.prepareMLXLoadDirectory(for: directory, modelType: "qwen3_vl")
        defer { try? FileManager.default.removeItem(at: loadDirectory) }

        XCTAssertNotEqual(loadDirectory.standardizedFileURL.path, directory.standardizedFileURL.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: loadDirectory.appendingPathComponent("config.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: loadDirectory.appendingPathComponent("model.safetensors").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: loadDirectory.appendingPathComponent("extras/custom_heads.safetensors").path))
    }

    func testNonVisionLoadDirectoryKeepsOriginalDirectory() throws {
        let directory = try makeTemporaryModelDirectory(config: #"{"model_type":"llama"}"#)
        defer { try? FileManager.default.removeItem(at: directory) }

        let extras = directory.appendingPathComponent("extras", isDirectory: true)
        try FileManager.default.createDirectory(at: extras, withIntermediateDirectories: true)
        try Data("auxiliary".utf8).write(to: extras.appendingPathComponent("custom_heads.safetensors"))

        let loadDirectory = try MLXHandler.prepareMLXLoadDirectory(for: directory, modelType: "llama")

        XCTAssertEqual(loadDirectory.standardizedFileURL.path, directory.standardizedFileURL.path)
    }

    private func makeTemporaryModelDirectory(config: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("warden_mlx_model_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try XCTUnwrap(config.data(using: .utf8))
        try data.write(to: directory.appendingPathComponent("config.json"))
        return directory
    }
}
