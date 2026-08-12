import Foundation
import SwiftUI
import MCP
import Logging

@MainActor
class MCPManager: ObservableObject {
    static let shared = MCPManager()
    
    @Published var configs: [MCPServerConfig] = []
    @Published var clients: [UUID: Client] = [:]
    @Published var serverStatuses: [UUID: ServerStatus] = [:]
    @Published var serverTools: [UUID: [Tool]] = [:]
    
    enum ServerStatus: Equatable {
        case connected(toolsCount: Int)
        case disconnected
        case error(String)
        case connecting
    }
    
    // Cache for tool to agent mapping
    private var toolOwner: [String: UUID] = [:]
    
    private let configsKey = "MCPServerConfigs"
    
    init() {
        loadConfigs()
    }
    
    // ... (load/save/add/update/delete/connect/disconnect methods remain same) ...
    
    func loadConfigs() {
        guard let data = UserDefaults.standard.data(forKey: configsKey),
              var decoded = try? JSONDecoder().decode([MCPServerConfig].self, from: data) else {
            return
        }

        var shouldRewriteStoredConfigs = false
        for index in decoded.indices {
            for (key, value) in decoded[index].environment {
                if let resolved = resolveEnvironmentSecretMarker(value, configID: decoded[index].id, environmentKey: key) {
                    decoded[index].environment[key] = resolved
                } else if isSensitiveEnvironmentKey(key), !value.isEmpty {
                    try? storeEnvironmentSecret(value, configID: decoded[index].id, environmentKey: key)
                    shouldRewriteStoredConfigs = true
                }
            }
        }

        self.configs = decoded
        if shouldRewriteStoredConfigs {
            saveConfigs()
        }
    }
    
    func saveConfigs() {
        let configsForStorage = configs.map(sanitizedConfigForStorage)
        if let encoded = try? JSONEncoder().encode(configsForStorage) {
            UserDefaults.standard.set(encoded, forKey: configsKey)
        }
    }
    
    func addConfig(_ config: MCPServerConfig) {
        configs.append(config)
        saveConfigs()
    }
    
    func updateConfig(_ config: MCPServerConfig) {
        if let index = configs.firstIndex(where: { $0.id == config.id }) {
            configs[index] = config
            saveConfigs()
            // Reconnect if needed
            Task {
                await disconnect(id: config.id)
                if config.enabled {
                    try? await connect(config: config)
                }
            }
        }
    }
    
    func deleteConfig(id: UUID) {
        if let config = configs.first(where: { $0.id == id }) {
            cleanupEnvironmentSecrets(for: config)
        }
        configs.removeAll { $0.id == id }
        saveConfigs()
        Task {
            await disconnect(id: id)
        }
    }
    
    func connect(config: MCPServerConfig) async throws {
        guard config.enabled else { return }
        
        await MainActor.run {
            serverStatuses[config.id] = .connecting
        }
        
        let client = Client(name: "Warden", version: "1.0")
        
        do {
            switch config.transportType {
            case .stdio:
                guard let command = config.command else {
                    throw NSError(domain: "MCPManager", code: 400, userInfo: [NSLocalizedDescriptionKey: "Missing command for Stdio transport"])
                }
                
                let transport = ProcessStdioTransport(command: command, arguments: config.arguments, environment: resolvedEnvironment(for: config))
                _ = try await client.connect(transport: transport)
                
            case .sse:
                guard let url = config.url else {
                    throw NSError(domain: "MCPManager", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
                }
                let transport = HTTPClientTransport(endpoint: url, streaming: true)
                _ = try await client.connect(transport: transport)
            }
            
            clients[config.id] = client
            
            // Fetch tools to verify connection and get count
            let (tools, _) = try await client.listTools()
            
            // Update tool owner cache
            for tool in tools {
                toolOwner[tool.name] = config.id
            }
            
            await MainActor.run {
                serverStatuses[config.id] = .connected(toolsCount: tools.count)
                serverTools[config.id] = tools
            }
        } catch {
            await MainActor.run {
                serverStatuses[config.id] = .error(error.localizedDescription)
            }
            throw error
        }
    }
    
    func disconnect(id: UUID) async {
        if let client = clients[id] {
            // Client doesn't have close(), just remove from dict
            clients.removeValue(forKey: id)
            // Remove tools for this client from cache
            toolOwner = toolOwner.filter { $0.value != id }
            
            await MainActor.run {
                serverStatuses[id] = .disconnected
                serverTools.removeValue(forKey: id)
            }
        }
    }
    
    func restartAll() async {
        for config in configs where config.enabled {
            try? await connect(config: config)
        }
    }
    
    func getToolsForServer(id: UUID) async -> [Tool] {
        // Return cached tools if available
        if let tools = serverTools[id] {
            return tools
        }
        
        // Otherwise try to fetch from client
        guard let client = clients[id] else {
            return []
        }
        
        do {
            let (tools, _) = try await client.listTools()
            await MainActor.run {
                serverTools[id] = tools
            }
            return tools
        } catch {
            WardenLog.app.error(
                "Error fetching tools for server \(id.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            return []
        }
    }
    
    // MARK: - Tool Handling
    
    func getTools(for agentIDs: Set<UUID>) async -> [Tool] {
        var allTools: [Tool] = []
        
        for id in agentIDs {
            guard let client = clients[id] else {
                // Try to connect if not connected?
                // For now assume connected.
                continue
            }
            
            do {
                let (tools, _) = try await client.listTools()
                for tool in tools {
                    allTools.append(tool)
                    toolOwner[tool.name] = id
                }
            } catch {
                WardenLog.app.error(
                    "Error fetching tools for agent \(id.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
            }
        }
        
        return allTools
    }
    
    func callTool(name: String, arguments: [String: Any]) async throws -> [[String: Any]] {
        guard let agentID = toolOwner[name], let client = clients[agentID] else {
            throw NSError(domain: "MCPManager", code: 404, userInfo: [NSLocalizedDescriptionKey: "Tool not found or agent not connected"])
        }
        
        // Convert [String: Any] to [String: Value]
        var valueArgs: [String: Value] = [:]
        for (key, value) in arguments {
            if let strVal = value as? String {
                valueArgs[key] = try .init(strVal)
            } else if let intVal = value as? Int {
                valueArgs[key] = try .init(Double(intVal))
            } else if let doubleVal = value as? Double {
                valueArgs[key] = try .init(doubleVal)
            } else if let boolVal = value as? Bool {
                valueArgs[key] = try .init(boolVal)
            }
            // Add more type conversions as needed
        }
        
        let (content, _) = try await client.callTool(name: name, arguments: valueArgs)
        
        // Convert content to JSON-compatible format
        var result: [[String: Any]] = []
        for item in content {
            switch item {
            case .text(text: let text, annotations: _, _meta: _):
                result.append(["type": "text", "text": text])
            case .image(data: _, mimeType: let mimeType, annotations: _, _meta: _):
                result.append(["type": "image", "mimeType": mimeType])
            case .audio(data: _, mimeType: let mimeType, annotations: _, _meta: _):
                result.append(["type": "audio", "mimeType": mimeType])
            case .resource(resource: let resource, annotations: _, _meta: _):
                var dict: [String: Any] = ["type": "resource", "uri": resource.uri]
                if let mimeType = resource.mimeType {
                    dict["mimeType"] = mimeType
                }
                if let text = resource.text {
                    dict["text"] = text
                }
                result.append(dict)
            case .resourceLink(uri: let uri, name: let name, title: let title, description: let description, mimeType: let mimeType, annotations: _):
                var dict: [String: Any] = ["type": "resource_link", "uri": uri, "name": name]
                if let title { dict["title"] = title }
                if let description { dict["description"] = description }
                if let mimeType { dict["mimeType"] = mimeType }
                result.append(dict)
            }
        }
        
        return result
    }
    
    private func isSensitiveEnvironmentKey(_ key: String) -> Bool {
        Self.isSensitiveEnvironmentKeyValue(key)
    }

    private func environmentSecretIdentifier(configID: UUID, environmentKey: String) -> String {
        "mcp_\(configID.uuidString)_\(environmentKey)"
    }

    private func environmentSecretMarker(configID: UUID, environmentKey: String) -> String {
        Self.environmentSecretMarkerValue(configID: configID, environmentKey: environmentKey)
    }

    /// Pure marker builder exposed for deterministic tests (no side effects).
    static nonisolated func environmentSecretMarkerValue(configID: UUID, environmentKey: String) -> String {
        "keychain://mcp-env/\(configID.uuidString)/\(environmentKey)"
    }

    /// Pure sensitive-key classifier exposed for deterministic tests.
    static nonisolated func isSensitiveEnvironmentKeyValue(_ key: String) -> Bool {
        let lowercased = key.lowercased()
        return ["token", "key", "secret", "password", "passwd", "auth", "bearer", "credential"].contains { lowercased.contains($0) }
    }

    private func storeEnvironmentSecret(_ value: String, configID: UUID, environmentKey: String) throws {
        try TokenManager.setToken(value, for: "mcp_env", identifier: environmentSecretIdentifier(configID: configID, environmentKey: environmentKey))
    }

    private func resolveEnvironmentSecretMarker(_ value: String, configID: UUID, environmentKey: String) -> String? {
        guard value.hasPrefix("keychain://mcp-env/") else { return nil }
        return try? TokenManager.getToken(for: "mcp_env", identifier: environmentSecretIdentifier(configID: configID, environmentKey: environmentKey))
    }

    private func sanitizedConfigForStorage(_ config: MCPServerConfig) -> MCPServerConfig {
        var sanitized = config
        for (key, value) in config.environment where isSensitiveEnvironmentKey(key) && !value.isEmpty {
            if value.hasPrefix("keychain://mcp-env/") {
                continue
            }
            do {
                try storeEnvironmentSecret(value, configID: config.id, environmentKey: key)
                sanitized.environment[key] = environmentSecretMarker(configID: config.id, environmentKey: key)
            } catch {
                WardenLog.app.error("Failed to store MCP environment secret for \(key, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        return sanitized
    }

    private func resolvedEnvironment(for config: MCPServerConfig) -> [String: String] {
        var environment = config.environment
        for (key, value) in config.environment {
            if let resolved = resolveEnvironmentSecretMarker(value, configID: config.id, environmentKey: key) {
                environment[key] = resolved
            }
        }
        return environment
    }

    private func cleanupEnvironmentSecrets(for config: MCPServerConfig) {
        for key in config.environment.keys where isSensitiveEnvironmentKey(key) {
            try? TokenManager.deleteToken(for: "mcp_env", identifier: environmentSecretIdentifier(configID: config.id, environmentKey: key))
        }
    }

    func testConnection(config: MCPServerConfig) async throws -> Int {
        let client = Client(name: "Warden-Test", version: "1.0")
        var stdioTransport: ProcessStdioTransport?
        defer {
            if let stdioTransport {
                Task { await stdioTransport.disconnect() }
            }
        }
        
        switch config.transportType {
        case .stdio:
            guard let command = config.command else {
                throw NSError(domain: "MCPManager", code: 400, userInfo: [NSLocalizedDescriptionKey: "Missing command for Stdio transport"])
            }
            let transport = ProcessStdioTransport(command: command, arguments: config.arguments, environment: resolvedEnvironment(for: config))
            stdioTransport = transport
            _ = try await client.connect(transport: transport)
            
        case .sse:
            guard let url = config.url else {
                throw NSError(domain: "MCPManager", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
            }
            let transport = HTTPClientTransport(endpoint: url, streaming: true)
            _ = try await client.connect(transport: transport)
        }
        
        let (tools, _) = try await client.listTools()
        return tools.count
    }
}

// Custom Transport implementation for Process-based Stdio
actor ProcessStdioTransport: Transport {
    public nonisolated let logger: Logger
    
    private let command: String
    private let arguments: [String]
    private let environment: [String: String]
    
    private var process: Process?
    private var inputPipe: Pipe?
    private var outputPipe: Pipe?
    private var stderrPipe: Pipe?
    private var isConnected = false
    
    private var receiveStream: AsyncThrowingStream<Data, Error>?
    private var receiveContinuation: AsyncThrowingStream<Data, Error>.Continuation?
    
    init(command: String, arguments: [String], environment: [String: String], logger: Logger? = nil) {
        self.command = command
        self.arguments = arguments
        self.environment = environment
        self.logger = logger ?? Logger(label: "mcp.transport.process")
    }
    
    public func connect() async throws {
        guard !isConnected else { return }
        
        let process = Process()
        
        // Use /usr/bin/env to resolve commands in PATH (like npx, node, python)
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [command] + arguments
        
        var env = ProcessInfo.processInfo.environment
        
        // Add common paths for node/npm/npx that may not be in GUI app's PATH
        let currentPath = env["PATH"] ?? "/usr/bin:/bin"
        let additionalPaths = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "\(NSHomeDirectory())/.local/bin",
            "/opt/local/bin"
        ]
        env["PATH"] = (additionalPaths + [currentPath]).joined(separator: ":")
        
        for (key, value) in environment {
            env[key] = value
        }
        process.environment = env
        
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = stderrPipe
        
        self.process = process
        self.inputPipe = inputPipe
        self.outputPipe = outputPipe
        self.stderrPipe = stderrPipe
        
        var continuation: AsyncThrowingStream<Data, Error>.Continuation!
        self.receiveStream = AsyncThrowingStream { continuation = $0 }
        self.receiveContinuation = continuation
        
        // Log stderr for debugging
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty, let str = String(data: data, encoding: .utf8) {
                #if DEBUG
                WardenLog.app.debug("[MCP] stderr received: \(str.count, privacy: .public) char(s)")
                #endif
            }
        }
        
        try process.run()
        isConnected = true
        
        // Start reading stdout in background using readabilityHandler
        startReadLoop(handle: outputPipe.fileHandleForReading, continuation: continuation)
    }
    
    private nonisolated func startReadLoop(handle: FileHandle, continuation: AsyncThrowingStream<Data, Error>.Continuation) {
        // Use a class to hold mutable state across closure invocations
        class BufferHolder {
            var data = Data()
        }
        let bufferHolder = BufferHolder()
        
        handle.readabilityHandler = { fileHandle in
            let data = fileHandle.availableData
            
            if data.isEmpty {
                handle.readabilityHandler = nil
                continuation.finish()
                return
            }
            
            bufferHolder.data.append(data)
            
            while let newlineIndex = bufferHolder.data.firstIndex(of: UInt8(ascii: "\n")) {
                let messageData = bufferHolder.data[..<newlineIndex]
                bufferHolder.data = bufferHolder.data[(newlineIndex + 1)...]
                if !messageData.isEmpty {
                    continuation.yield(Data(messageData))
                }
            }
        }
    }
    
    public func disconnect() async {
        guard isConnected else { return }
        isConnected = false
        
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe?.fileHandleForReading.readabilityHandler = nil
        receiveContinuation?.finish()
        process?.terminate()
        process = nil
        inputPipe = nil
        outputPipe = nil
        stderrPipe = nil
    }
    
    public func send(_ data: Data) async throws {
        guard let inputPipe = inputPipe, isConnected else {
            throw NSError(domain: "ProcessStdioTransport", code: 1, userInfo: [NSLocalizedDescriptionKey: "Not connected"])
        }
        
        guard let process = process, process.isRunning else {
            throw NSError(domain: "ProcessStdioTransport", code: 2, userInfo: [NSLocalizedDescriptionKey: "Process is not running"])
        }
        
        var messageData = data
        messageData.append(UInt8(ascii: "\n"))
        
        do {
            try inputPipe.fileHandleForWriting.write(contentsOf: messageData)
        } catch {
            isConnected = false
            throw NSError(domain: "ProcessStdioTransport", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to write to process: \(error.localizedDescription)"])
        }
    }
    
    public func receive() -> AsyncThrowingStream<Data, Error> {
        return receiveStream ?? AsyncThrowingStream { $0.finish() }
    }
}
