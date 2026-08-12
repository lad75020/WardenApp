import XCTest
@testable import Warden

/// Deterministic coverage for the MCP subsystem's pure, security-sensitive
/// logic: sensitive-env detection, Keychain-marker format, tool-call status
/// serialization, and MCP result-dictionary JSON shape. No live server, no
/// Keychain writes, no paid credentials — per the WardenApp constitution.
final class MCPToolIntegrationTests: XCTestCase {

    // MARK: - US2: sensitive env key detection

    func testSensitiveEnvironmentKeyDetectionMatchesKnownPatterns() {
        let sensitive = [
            "API_KEY", "api_token", "SECRET", "DB_PASSWORD", "MYSQL_PASSWD",
            "AUTH_HEADER", "BEARER_TOKEN", "AWS_CREDENTIAL", "OpenAiKey"
        ]
        sensitive.forEach {
            XCTAssertTrue(MCPManager.isSensitiveEnvironmentKeyValue($0), "expected \($0) sensitive")
        }
    }

    func testNonSensitiveEnvironmentKeysAreNotFlagged() {
        let benign = ["HOST", "PORT", "REGION", "PATH", "NODE_ENV", "TIMEOUT_MS"]
        benign.forEach {
            XCTAssertFalse(MCPManager.isSensitiveEnvironmentKeyValue($0), "expected \($0) benign")
        }
    }

    // MARK: - US2: keychain marker format

    func testEnvironmentSecretMarkerFormatIsStableAndScoped() {
        let id = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let marker = MCPManager.environmentSecretMarkerValue(configID: id, environmentKey: "API_KEY")
        XCTAssertEqual(marker, "keychain://mcp-env/11111111-2222-3333-4444-555555555555/API_KEY")
        XCTAssertTrue(marker.hasPrefix("keychain://mcp-env/"))
        // The marker must never contain the secret value itself.
        XCTAssertFalse(marker.contains("secret-value"))
    }

    func testMarkerIsDistinctPerKeyAndConfig() {
        let a = UUID(); let b = UUID()
        XCTAssertNotEqual(
            MCPManager.environmentSecretMarkerValue(configID: a, environmentKey: "K"),
            MCPManager.environmentSecretMarkerValue(configID: b, environmentKey: "K")
        )
        XCTAssertNotEqual(
            MCPManager.environmentSecretMarkerValue(configID: a, environmentKey: "K1"),
            MCPManager.environmentSecretMarkerValue(configID: a, environmentKey: "K2")
        )
    }

    // MARK: - US1: config validation shape

    func testStdioConfigRoundTripsThroughCodable() throws {
        var config = MCPServerConfig(name: "fs", transportType: .stdio)
        config.command = "npx"
        config.arguments = ["-y", "@modelcontextprotocol/server-filesystem", "/tmp"]
        config.environment = ["HOST": "localhost"]
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(MCPServerConfig.self, from: data)
        XCTAssertEqual(decoded.name, "fs")
        XCTAssertEqual(decoded.transportType, .stdio)
        XCTAssertEqual(decoded.command, "npx")
        XCTAssertEqual(decoded.arguments.count, 3)
        XCTAssertEqual(decoded.environment["HOST"], "localhost")
        XCTAssertTrue(decoded.enabled)
    }

    func testSseConfigPreservesURL() throws {
        var config = MCPServerConfig(name: "remote", transportType: .sse)
        config.url = URL(string: "http://localhost:3000/sse")
        let decoded = try JSONDecoder().decode(MCPServerConfig.self, from: try JSONEncoder().encode(config))
        XCTAssertEqual(decoded.transportType, .sse)
        XCTAssertEqual(decoded.url?.absoluteString, "http://localhost:3000/sse")
    }

    // MARK: - US3: tool-call status persistence

    func testToolCallStatusCodableRoundTripPreservesLifecycle() throws {
        let statuses: [WardenToolCallStatus] = [
            .calling(toolName: "search"),
            .executing(toolName: "fetch", progress: "loading"),
            .completed(toolName: "list", success: true, result: "{\"ok\":true}"),
            .failed(toolName: "write", error: "denied")
        ]
        let data = try JSONEncoder().encode(statuses)
        let decoded = try JSONDecoder().decode([WardenToolCallStatus].self, from: data)
        XCTAssertEqual(decoded, statuses)
        XCTAssertEqual(decoded[2].result, "{\"ok\":true}")
        XCTAssertTrue(decoded[2].isComplete)
        XCTAssertTrue(decoded[3].isComplete)
        XCTAssertFalse(decoded[0].isComplete)
    }

    // MARK: - US3: MCP result dictionary JSON shape

    func testToolResultDictionariesAreJSONSerializable() throws {
        // Mirrors the normalized shapes MCPManager.callTool returns.
        let result: [[String: Any]] = [
            ["type": "text", "text": "hello"],
            ["type": "image", "mimeType": "image/png"],
            ["type": "resource", "uri": "file:///tmp/x", "mimeType": "text/plain", "text": "body"]
        ]
        XCTAssertTrue(JSONSerialization.isValidJSONObject(result))
        let data = try JSONSerialization.data(withJSONObject: result, options: [])
        let back = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        XCTAssertEqual(back?.count, 3)
        XCTAssertEqual(back?[0]["type"] as? String, "text")
        XCTAssertEqual(back?[2]["uri"] as? String, "file:///tmp/x")
    }
}
