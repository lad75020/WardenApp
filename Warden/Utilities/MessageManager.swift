import CoreData
import Foundation
import MCP
import os

@MainActor
final class MessageManager: ObservableObject {
    typealias MessageDispatcher = @MainActor (
        APIService,
        [[String: String]],
        [[String: Any]]?,
        Float,
        @escaping (Result<(String?, [ToolCall]?), Error>) -> Void
    ) -> Void

    typealias StreamDispatcher = @MainActor (
        APIService,
        [[String: String]],
        [[String: Any]]?,
        Float,
        @escaping @MainActor (String) async -> Void
    ) async throws -> [ToolCall]?

    struct RetryIntent {
        let userTurn: MessageEntity
        let assistantTarget: MessageEntity?
    }

    private var apiService: APIService
    private var viewContext: NSManagedObjectContext
    private let messageDispatcher: MessageDispatcher
    private let streamDispatcher: StreamDispatcher
    private let fetchStreamTools: Bool
    private let streamingTaskController = StreamingTaskController.shared
    private let streamingSessions = ChatStreamingSessionRegistry.shared
    private let tavilyService: TavilySearchService
    private let streamUpdateInterval = AppConstants.streamedResponseUpdateUIInterval
    
    // Debounce saving to Core Data
    private var saveDebounceWorkItem: DispatchWorkItem?
    
    // Published property for search status updates
    @Published var searchStatus: SearchStatus?

    /// Search precedes the provider-owned stream, so it needs its own request identity.
    /// Stop invalidates this identity to reject late Tavily progress, results, and errors.
    private var activeSearchRequestIDs: [UUID: UUID] = [:]
    
    // Published property for tool call status
    @Published var toolCallStatus: WardenToolCallStatus?
    @Published var activeToolCalls: [WardenToolCallStatus] = []
    
    // Map of message IDs to their completed tool calls (for persistence within session)
    @Published var messageToolCalls: [Int64: [WardenToolCallStatus]] = [:]
    
    // In-progress assistant response (kept in-memory; persisted on completion)
    @Published var streamingAssistantText: String = ""

    init(
        apiService: APIService,
        viewContext: NSManagedObjectContext,
        fetchStreamTools: Bool = true,
        tavilyService: TavilySearchService = TavilySearchService(),
        messageDispatcher: @escaping MessageDispatcher = { apiService, messages, tools, temperature, completion in
            ChatService.shared.sendMessage(
                apiService: apiService,
                messages: messages,
                tools: tools,
                temperature: temperature
            ) { result in
                completion(result.mapError { $0 as Error })
            }
        },
        streamDispatcher: @escaping StreamDispatcher = { apiService, messages, tools, temperature, onChunk in
            try await ChatService.shared.sendStream(
                apiService: apiService,
                messages: messages,
                tools: tools,
                temperature: temperature,
                onChunk: onChunk
            )
        }
    ) {
        self.apiService = apiService
        self.viewContext = viewContext
        self.fetchStreamTools = fetchStreamTools
        self.tavilyService = tavilyService
        self.messageDispatcher = messageDispatcher
        self.streamDispatcher = streamDispatcher
    }

    func update(apiService: APIService, viewContext: NSManagedObjectContext) {
        self.apiService = apiService
        self.viewContext = viewContext
    }
    
    func isSearchCommand(_ message: String) -> (isSearch: Bool, query: String?) {
        return tavilyService.isSearchCommand(message)
    }
    
    func stopStreaming(in chat: ChatEntity) {
        cancelSearchRequest(in: chat)
        let session = streamingSessions.session(for: chat.id)
        if let requestID = session.requestID {
            _ = session.cancel(requestID: requestID)
            Task { await streamingTaskController.cancel(conversationID: chat.id, requestID: requestID) }
        }
        chat.waitingForResponse = false
        
        // Force save if pending
        if let workItem = saveDebounceWorkItem {
            workItem.perform()
            saveDebounceWorkItem?.cancel()
            saveDebounceWorkItem = nil
        }
    }

    func invalidateStreaming(in chat: ChatEntity) {
        cancelSearchRequest(in: chat)
        streamingSessions.invalidate(conversationID: chat.id)
        Task { await streamingTaskController.invalidate(conversationID: chat.id) }
        chat.waitingForResponse = false
    }
    
    private func debounceSave() {
        saveDebounceWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.viewContext.performSaveWithRetry(attempts: 1)
        }
        saveDebounceWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: workItem)
    }
    
    // MARK: - Tavily Search Support
    
    func executeSearch(_ query: String, in chat: ChatEntity, requestID: UUID) async throws -> WebSearchAttempt {
        let (context, urls, sources) = try await tavilyService.performSearch(query: query) { [weak self] status in
            guard let self, self.isCurrentSearchRequest(requestID, in: chat) else { return }
            self.searchStatus = status
        }
        _ = urls
        return WebSearchAttempt(query: query, formattedContext: context, sources: sources)
    }

    private func beginSearchRequest(in chat: ChatEntity) -> UUID {
        let requestID = UUID()
        activeSearchRequestIDs[chat.id] = requestID
        return requestID
    }

    private func isCurrentSearchRequest(_ requestID: UUID, in chat: ChatEntity) -> Bool {
        activeSearchRequestIDs[chat.id] == requestID
    }

    private func finishSearchRequest(_ requestID: UUID, in chat: ChatEntity) {
        guard isCurrentSearchRequest(requestID, in: chat) else { return }
        activeSearchRequestIDs.removeValue(forKey: chat.id)
    }

    private func cancelSearchRequest(in chat: ChatEntity) {
        activeSearchRequestIDs.removeValue(forKey: chat.id)
        searchStatus = nil
    }
    
    @MainActor
    func sendMessageStreamWithSearch(
        _ message: String,
        in chat: ChatEntity,
        contextSize: Int,
        useWebSearch: Bool = false,
        rawSearchQuery: String? = nil,
        completion: @escaping (Result<Void, Error>) -> Void
    ) async {
        #if DEBUG
        WardenLog.app.debug("[WebSearch] sendMessageStreamWithSearch called")
        #endif
        
        var finalMessage = message
         
         // Check if web search is enabled (either by toggle or by command)
        let searchCheck = tavilyService.isSearchCommand(message)
        let shouldSearch = useWebSearch || searchCheck.isSearch
        
        if shouldSearch {
            let searchRequestID = beginSearchRequest(in: chat)
            let query: String
            if searchCheck.isSearch, let commandQuery = searchCheck.query {
                query = commandQuery
            } else {
                query = rawSearchQuery ?? message
            }
            
            chat.waitingForResponse = true
            
            do {
                let attempt = try await executeSearch(query, in: chat, requestID: searchRequestID)
                guard isCurrentSearchRequest(searchRequestID, in: chat), !Task.isCancelled else { return }
                finishSearchRequest(searchRequestID, in: chat)
                
                finalMessage = """
                User asked: \(query)
                
                \(attempt.formattedContext)
                
                Based on the search results above, please provide a comprehensive answer to the user's question. Include relevant citations using the source numbers [1], [2], etc.
                """
                
                // Pass URLs through to sendMessageStream
                sendMessageStream(finalMessage, in: chat, contextSize: contextSize, searchAttempt: attempt) { [weak self] result in
                    // Auto-rename chat if needed after successful search response
                    if case .success = result {
                        self?.generateChatNameIfNeeded(chat: chat)
                    }
                    completion(result)
                }
                return
            } catch {
                guard isCurrentSearchRequest(searchRequestID, in: chat), !Task.isCancelled else { return }
                finishSearchRequest(searchRequestID, in: chat)
                guard !(error is CancellationError) else {
                    chat.waitingForResponse = false
                    return
                }
                WardenLog.app.error("[WebSearch] Search failed (category only)")
                chat.waitingForResponse = false
                
                // Update status: failed
                await MainActor.run {
                    searchStatus = .failed(error)
                }
                
                completion(.failure(error))
                return
            }
        }
        
        sendMessageStream(finalMessage, in: chat, contextSize: contextSize) { result in
            completion(result)
        }
    }

    @MainActor
    func sendMessageWithSearch(
        _ message: String,
        in chat: ChatEntity,
        contextSize: Int,
        useWebSearch: Bool = false,
        rawSearchQuery: String? = nil,
        completion: @escaping (Result<Void, Error>) -> Void
    ) async {
        #if DEBUG
        WardenLog.app.debug("[WebSearch] sendMessageWithSearch called (non-stream)")
        #endif
        
        var finalMessage = message
         
         // Check if web search is enabled (either by toggle or by command)
        let searchCheck = tavilyService.isSearchCommand(message)
        let shouldSearch = useWebSearch || searchCheck.isSearch
        
        if shouldSearch {
            let searchRequestID = beginSearchRequest(in: chat)
            let query: String
            if searchCheck.isSearch, let commandQuery = searchCheck.query {
                query = commandQuery
            } else {
                query = rawSearchQuery ?? message
            }
            
            chat.waitingForResponse = true
            
            do {
                let attempt = try await executeSearch(query, in: chat, requestID: searchRequestID)
                guard isCurrentSearchRequest(searchRequestID, in: chat), !Task.isCancelled else { return }
                finishSearchRequest(searchRequestID, in: chat)
                
                finalMessage = """
                User asked: \(query)
                
                \(attempt.formattedContext)
                
                Based on the search results above, please provide a comprehensive answer to the user's question. Include relevant citations using the source numbers [1], [2], etc.
                """
                
                // Pass URLs through to sendMessage
                sendMessage(finalMessage, in: chat, contextSize: contextSize, searchAttempt: attempt) { [weak self] result in
                    // Auto-rename chat if needed after successful search response
                    if case .success = result {
                        self?.generateChatNameIfNeeded(chat: chat)
                    }
                    completion(result)
                }
                return
            } catch {
                guard isCurrentSearchRequest(searchRequestID, in: chat), !Task.isCancelled else { return }
                finishSearchRequest(searchRequestID, in: chat)
                guard !(error is CancellationError) else {
                    chat.waitingForResponse = false
                    return
                }
                WardenLog.app.error("[WebSearch] Search failed (non-stream, category only)")
                chat.waitingForResponse = false
                
                // Update status: failed
                await MainActor.run {
                    searchStatus = .failed(error)
                }
                
                completion(.failure(error))
                return
            }
        }
        
        sendMessage(finalMessage, in: chat, contextSize: contextSize) { result in
            completion(result)
        }
    }
    
    // MARK: - MCP Tool Conversion Helpers
    
    /// Converts MCP Value type to a dictionary for OpenAI tool schema format
    private func convertValueToDict(_ value: Value) -> Any {
        // Value has a description property that outputs JSON-like format
        // We need to parse it as a dictionary
        if let jsonData = value.description.data(using: .utf8),
           let dict = try? JSONSerialization.jsonObject(with: jsonData) {
            return dict
        }
        // Fallback: return empty object
        return [:]
    }
    
    func sendMessage(
        _ message: String,
        in chat: ChatEntity,
        contextSize: Int,
        searchUrls: [String]? = nil,
        searchAttempt: WebSearchAttempt? = nil,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let forceSinglePrompt = UserDefaults.standard.bool(forKey: "imageGenMode_\(chat.id.uuidString)")
        let isImageGeneration = forceSinglePrompt
            || (apiService.model.localizedCaseInsensitiveContains("image"))
            || apiService.name.localizedCaseInsensitiveContains("image")
        let requestMessages: [[String: String]]
        if isImageGeneration {
            // Image generation models expect only the current prompt
            requestMessages = [["role": "user", "content": message]]
            #if DEBUG
            WardenLog.app.debug("Image generation mode active (single-prompt). Model=\(self.apiService.model, privacy: .public) Service=\(self.apiService.name, privacy: .public)")
            #endif
        } else {
            let built = prepareRequestMessages(userMessage: message, chat: chat, contextSize: contextSize)
            if isVisionModelName(apiService.model) && containsImageInputs(in: built) {
                requestMessages = [["role": "user", "content": message]]
                #if DEBUG
                WardenLog.app.debug("Vision model single-prompt mode active. Model=\(self.apiService.model, privacy: .public)")
                #endif
            } else {
                requestMessages = containsImageInputs(in: built) ? built : sanitizeRequestMessagesForText(built)
            }
        }
        chat.waitingForResponse = true
        let temperature = (chat.persona?.temperature ?? AppConstants.defaultTemperatureForChat).roundedToOneDecimal()
        
        // Fetch tools from selected MCP agents
        Task { @MainActor in
            let viewModel = ChatViewModel(chat: chat, viewContext: self.viewContext)
            let selectedAgents = viewModel.selectedMCPAgents
            
            #if DEBUG
            WardenLog.app.debug("[MCP] Fetching tools for \(selectedAgents.count, privacy: .public) selected agent(s)")
            #endif
            let tools = await MCPManager.shared.getTools(for: selectedAgents)
            #if DEBUG
            WardenLog.app.debug("[MCP] Found \(tools.count, privacy: .public) tool(s)")
            #endif
            
            let toolDefinitions = self.toolDefinitions(from: tools)
            
            #if DEBUG
            WardenLog.app.debug("[MCP] Sending \(toolDefinitions.count, privacy: .public) tool definition(s) to API")
            if !toolDefinitions.isEmpty {
                WardenLog.app.debug("[MCP] Tool names: \(tools.map { $0.name }.joined(separator: ", "), privacy: .public)")
            }
            #endif
            
            self.messageDispatcher(
                self.apiService,
                requestMessages,
                toolDefinitions.isEmpty ? nil : toolDefinitions,
                temperature
            ) { [weak self] result in
                guard let self = self else { return }
                
                DispatchQueue.main.async {
                    switch result {
                    case .success(let (messageBody, toolCalls)):
                        chat.waitingForResponse = false
                        
                        if let messageBody = messageBody {
                            self.addMessageToChat(chat: chat, message: messageBody, searchUrls: searchAttempt?.actionableURLs ?? searchUrls, searchMetadata: searchAttempt?.metadata)
                            self.addNewMessageToRequestMessages(chat: chat, content: messageBody, role: RequestMessageRole.assistant.rawValue)
                        }
                        
                        if let toolCalls = toolCalls, !toolCalls.isEmpty {
                            // Handle tool calls
                            Task {
                                await self.handleToolCalls(toolCalls, in: chat, contextSize: contextSize, completion: completion)
                            }
                            return
                        }
                        
                        self.debounceSave()
                        // Auto-rename chat if needed
                        self.generateChatNameIfNeeded(chat: chat)
                        completion(.success(()))
                        
                    case .failure(let error):
                        completion(.failure(error))
                    }
                }
            }
        }
    }

    func retryMessage(
        userTurn: MessageEntity,
        assistantTarget: MessageEntity?,
        in chat: ChatEntity,
        contextSize: Int,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let intent = RetryIntent(userTurn: userTurn, assistantTarget: assistantTarget)
        let requestMessages = prepareRetryRequestMessages(intent: intent, chat: chat, contextSize: contextSize)
        let temperature = (chat.persona?.temperature ?? AppConstants.defaultTemperatureForChat).roundedToOneDecimal()
        chat.waitingForResponse = true

        Task { @MainActor in
            let viewModel = ChatViewModel(chat: chat, viewContext: self.viewContext)
            let selectedAgents = viewModel.selectedMCPAgents
            let tools = await MCPManager.shared.getTools(for: selectedAgents)
            let toolDefinitions = self.toolDefinitions(from: tools)

            ChatService.shared.sendMessage(
                apiService: self.apiService,
                messages: requestMessages,
                tools: toolDefinitions.isEmpty ? nil : toolDefinitions,
                temperature: temperature
            ) { [weak self] result in
                DispatchQueue.main.async {
                    guard let self else {
                        chat.waitingForResponse = false
                        completion(.failure(APIError.invalidResponse))
                        return
                    }

                switch result {
                    case .success(let (messageBody, toolCalls)):
                        if let messageBody,
                           !messageBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            self.persistStreamedAssistant(messageBody, in: chat, retryTarget: assistantTarget, searchUrls: nil)
                        }

                        if let toolCalls, !toolCalls.isEmpty {
                            chat.waitingForResponse = false
                            Task {
                                await self.handleToolCalls(
                                    toolCalls,
                                    in: chat,
                                    contextSize: contextSize,
                                    retryTarget: assistantTarget,
                                    completion: completion
                                )
                            }
                            return
                        }

                        guard let messageBody,
                              !messageBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                            chat.waitingForResponse = false
                            completion(.failure(APIError.invalidResponse))
                            return
                        }

                        chat.waitingForResponse = false
                        self.debounceSave()
                        self.generateChatNameIfNeeded(chat: chat)
                        completion(.success(()))

                    case .failure(let error):
                        chat.waitingForResponse = false
                        completion(.failure(error))
                    }
                }
            }
        }
    }

    @MainActor
    func sendMessageStream(
        _ message: String,
        in chat: ChatEntity,
        contextSize: Int,
        searchUrls: [String]? = nil,
        searchAttempt: WebSearchAttempt? = nil,
        retryTarget: MessageEntity? = nil,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let retryIntent = retryTarget.map { RetryIntent(userTurn: resolveRetryUserTurn(message, in: chat), assistantTarget: $0) }
        sendMessageStream(
            message,
            in: chat,
            contextSize: contextSize,
            searchUrls: searchAttempt?.actionableURLs ?? searchUrls,
            searchMetadata: searchAttempt?.metadata,
            retryIntent: retryIntent,
            completion: completion
        )
    }

    func retryMessageStream(
        userTurn: MessageEntity,
        assistantTarget: MessageEntity?,
        in chat: ChatEntity,
        contextSize: Int,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        sendMessageStream(
            userTurn.body,
            in: chat,
            contextSize: contextSize,
            searchUrls: nil,
            retryIntent: RetryIntent(userTurn: userTurn, assistantTarget: assistantTarget),
            completion: completion
        )
    }

    private func sendMessageStream(
        _ message: String,
        in chat: ChatEntity,
        contextSize: Int,
        searchUrls: [String]?,
        searchMetadata: MessageSearchMetadata? = nil,
        retryIntent: RetryIntent?,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        // A stream is owned by its initiating conversation, never by the visible view.
        stopStreaming(in: chat)
        
        let forceSinglePrompt = UserDefaults.standard.bool(forKey: "imageGenMode_\(chat.id.uuidString)")
        let isImageGeneration = forceSinglePrompt
            || (apiService.model.localizedCaseInsensitiveContains("image"))
            || apiService.name.localizedCaseInsensitiveContains("image")
        let requestMessages: [[String: String]]
        if isImageGeneration {
            // Image generation models expect only the current prompt
            requestMessages = [["role": "user", "content": message]]
            #if DEBUG
            WardenLog.app.debug("Image generation mode active (single-prompt). Model=\(self.apiService.model, privacy: .public) Service=\(self.apiService.name, privacy: .public)")
            #endif
        } else {
            let built = retryIntent == nil
                ? prepareRequestMessages(userMessage: message, chat: chat, contextSize: contextSize)
                : prepareRetryRequestMessages(intent: retryIntent!, chat: chat, contextSize: contextSize)
            if isVisionModelName(apiService.model) && containsImageInputs(in: built) {
                requestMessages = [["role": "user", "content": message]]
                #if DEBUG
                WardenLog.app.debug("Vision model single-prompt mode active. Model=\(self.apiService.model, privacy: .public)")
                #endif
            } else {
                requestMessages = containsImageInputs(in: built) ? built : sanitizeRequestMessagesForText(built)
            }
        }
        
        // For image generation models, avoid streaming entirely and use non-streaming send
        if isImageGeneration {
            sendMessage(message, in: chat, contextSize: contextSize, searchUrls: searchUrls, searchAttempt: nil, completion: completion)
            return
        }
        
        let temperature = (chat.persona?.temperature ?? AppConstants.defaultTemperatureForChat).roundedToOneDecimal()

        let streamTaskID = UUID()
        let session = streamingSessions.session(for: chat.id)
        session.begin(requestID: streamTaskID)
        chat.waitingForResponse = true
        let streamTask = Task { @MainActor in
            var chunkCount = 0
            let streamStart = Date()
            var deferImageResponse = false
            var lastUpdateTime = Date.distantPast
            var chunkBufferParts: [String] = []
            var chunkBufferCharacterCount = 0
            var deferredResponseParts: [String] = []
            var deferredResponseCharacterCount = 0
            var attachmentMarkerDetector = AttachmentMarkerDetector()
            let updateInterval = self.streamUpdateInterval
            
            // Ensure per-stream buffers start empty
            chunkBufferParts.removeAll(keepingCapacity: true)
            chunkBufferCharacterCount = 0
            deferredResponseParts.removeAll(keepingCapacity: true)
            deferredResponseCharacterCount = 0
            
            defer {
                Task {
                    await self.streamingTaskController.clearIfCurrent(
                        conversationID: chat.id,
                        requestID: streamTaskID
                    )
                }
            }

            @MainActor
            func flushChunkBuffer(force: Bool = false) {
                if Task.isCancelled && !force {
                    return
                }
                guard !chunkBufferParts.isEmpty else { return }

                func drainChunkBuffer() -> String {
                    var result = String()
                    result.reserveCapacity(chunkBufferCharacterCount)
                    for part in chunkBufferParts {
                        result.append(contentsOf: part)
                    }
                    chunkBufferParts.removeAll(keepingCapacity: true)
                    chunkBufferCharacterCount = 0
                    return result
                }
                
                let now = Date()
                guard force || now.timeIntervalSince(lastUpdateTime) >= updateInterval else { return }

                let chunkToApply = drainChunkBuffer()
                if !chunkToApply.isEmpty {
                    chat.waitingForResponse = true
                    session.publishPending(requestID: streamTaskID, force: force)
                    lastUpdateTime = now
                }
            }

            @MainActor
            func drainDeferredResponse() -> String {
                guard !deferredResponseParts.isEmpty else { return "" }
                var result = String()
                result.reserveCapacity(deferredResponseCharacterCount)
                for part in deferredResponseParts {
                    result.append(contentsOf: part)
                }
                deferredResponseParts.removeAll(keepingCapacity: true)
                deferredResponseCharacterCount = 0
                return result
            }

            @MainActor
            func appendDeferredResponse(_ chunk: String) {
                deferredResponseParts.append(chunk)
                deferredResponseCharacterCount += chunk.count
            }
            
            // Fetch tools
            let tools: [Tool]
            if fetchStreamTools {
                let viewModel = ChatViewModel(chat: chat, viewContext: self.viewContext)
                let selectedAgents = viewModel.selectedMCPAgents
                #if DEBUG
                WardenLog.app.debug("[MCP] Fetching tools for \(selectedAgents.count, privacy: .public) selected agent(s) (stream)")
                #endif
                tools = await MCPManager.shared.getTools(for: selectedAgents)
            } else {
                tools = []
            }
            #if DEBUG
            WardenLog.app.debug("[MCP] Found \(tools.count, privacy: .public) tool(s) (stream)")
            #endif
            
            let toolDefinitions = self.toolDefinitions(from: tools)

            // Fetching MCP capabilities can suspend. A Stop, replacement, or deletion while
            // suspended must prevent any provider dispatch for this request.
            guard !Task.isCancelled,
                  session.isCurrent(requestID: streamTaskID),
                  await self.streamingTaskController.shouldDispatch(
                    conversationID: chat.id,
                    requestID: streamTaskID
                  ) else {
                chat.waitingForResponse = false
                session.finish(requestID: streamTaskID)
                completion(.failure(CancellationError()))
                return
            }
            
            #if DEBUG
            WardenLog.app.debug("[MCP] Sending \(toolDefinitions.count, privacy: .public) tool definition(s) to API (stream)")
            if !toolDefinitions.isEmpty {
                WardenLog.app.debug("[MCP] Tool names: \(tools.map { $0.name }.joined(separator: ", "), privacy: .public)")
            }
            #endif
            
            do {
                chat.waitingForResponse = true
                
                let toolCalls = try await self.streamDispatcher(
                    self.apiService,
                    requestMessages,
                    toolDefinitions.isEmpty ? nil : toolDefinitions,
                    temperature
                ) { chunk in
                    chunkCount += 1
                    guard !chunk.isEmpty else { return }
                    guard session.append(chunk, requestID: streamTaskID) else { return }
                    let containsDeferredAttachmentTag = attachmentMarkerDetector.consume(chunk)
                    if containsDeferredAttachmentTag, !deferImageResponse {
                        flushChunkBuffer(force: true)
                        if let currentText = session.finalText(requestID: streamTaskID), !currentText.isEmpty {
                            deferredResponseParts = [currentText]
                            deferredResponseCharacterCount = currentText.count
                        }
                        deferImageResponse = true
                        chunkBufferParts.removeAll(keepingCapacity: true)
                        chunkBufferCharacterCount = 0
                        // The session snapshot already contains this boundary chunk.
                        return
                    }
                    if deferImageResponse {
                        appendDeferredResponse(chunk)
                        return
                    }
                    chunkBufferParts.append(chunk)
                    chunkBufferCharacterCount += chunk.count
                    flushChunkBuffer()
                }
                let elapsed = Date().timeIntervalSince(streamStart)
                #if DEBUG
                WardenLog.streaming.debug(
                    "Stream finished: \(chunkCount, privacy: .public) chunk(s) in \(String(format: "%.2f", elapsed), privacy: .public)s"
                )
                #endif
                flushChunkBuffer(force: true)

                if Task.isCancelled || session.phase == .cancelling {
                    throw CancellationError()
                }

                guard session.claimFinalization(requestID: streamTaskID) else { return }
                let finalResponse = deferImageResponse ? drainDeferredResponse() : (session.finalText(requestID: streamTaskID) ?? "")
                // Handle tool calls if any
                if let toolCalls = toolCalls, !toolCalls.isEmpty {
                    if !finalResponse.isEmpty {
                        self.persistStreamedAssistant(
                            finalResponse,
                            in: chat,
                            retryTarget: retryIntent?.assistantTarget,
                            searchUrls: searchUrls,
                            searchMetadata: searchMetadata
                        )
                    }
                    try Task.checkCancellation()
                    await self.handleToolCalls(
                        toolCalls,
                        in: chat,
                        contextSize: contextSize,
                        retryTarget: retryIntent?.assistantTarget,
                        streamRequestID: streamTaskID,
                        completion: completion
                    )
                    return
                }

                guard !finalResponse.isEmpty else {
                    chat.waitingForResponse = false
                    session.finish(requestID: streamTaskID, errorDescription: "Empty response")
                    completion(.failure(APIError.invalidResponse))
                    return
                }
                // Persist only the latest assistant response once.
                self.persistStreamedAssistant(
                    finalResponse,
                    in: chat,
                    retryTarget: retryIntent?.assistantTarget,
                    searchUrls: searchUrls,
                    searchMetadata: searchMetadata
                )
                
                await MainActor.run {
                    self.generateChatNameIfNeeded(chat: chat)
                    chat.waitingForResponse = false
                    session.finish(requestID: streamTaskID)
                }
                completion(.success(()))
            }
            catch is CancellationError {
                let elapsed = Date().timeIntervalSince(streamStart)
                #if DEBUG
                WardenLog.streaming.debug(
                    "Streaming cancelled: \(chunkCount, privacy: .public) chunk(s), \(String(format: "%.2f", elapsed), privacy: .public)s elapsed"
                )
                #endif
                
                // Save partial response even when cancelled via exception
                flushChunkBuffer(force: true)
                guard session.claimFinalization(requestID: streamTaskID) else { return }
                let partialResponse = deferImageResponse ? drainDeferredResponse() : (session.finalText(requestID: streamTaskID) ?? "")
                // Persist partial response only once on cancellation
                await MainActor.run {
                    if !partialResponse.isEmpty {
                        self.persistStreamedAssistant(
                            partialResponse,
                            in: chat,
                            retryTarget: retryIntent?.assistantTarget,
                            searchUrls: searchUrls,
                            searchMetadata: searchMetadata
                        )
                        #if DEBUG
                        WardenLog.streaming.debug("Partial response saved after cancellation")
                        #endif
                    }
                    
                    chat.waitingForResponse = false
                    session.finish(requestID: streamTaskID)
                }
                completion(.failure(CancellationError()))
            }
            catch {
                guard session.claimFinalization(requestID: streamTaskID) else { return }
                WardenLog.streaming.error("Streaming failed; request ended")
                await MainActor.run {
                    chat.waitingForResponse = false
                    session.finish(requestID: streamTaskID, errorDescription: "Response failed")
                }
                completion(.failure(error))
            }
        }
        
        Task {
            await streamingTaskController.replace(
                conversationID: chat.id,
                requestID: streamTaskID,
                task: streamTask
            )
        }
    }
    
    // MARK: - Tool Execution
    
    private func handleToolCalls(
        _ toolCalls: [ToolCall],
        in chat: ChatEntity,
        contextSize: Int,
        retryTarget: MessageEntity? = nil,
        streamRequestID: UUID? = nil,
        completion: @escaping (Result<Void, Error>) -> Void
    ) async {
        #if DEBUG
        WardenLog.app.debug("Handling \(toolCalls.count, privacy: .public) tool call(s)")
        #endif
        
        // Serialize tool calls to JSON string for Core Data storage
        let toolCallsDict = toolCalls.map { toolCall -> [String: Any] in
            return [
                "id": toolCall.id,
                "type": toolCall.type,
                "function": [
                    "name": toolCall.function.name,
                    "arguments": toolCall.function.arguments
                ]
            ]
        }
        
        if let toolCallsData = try? JSONSerialization.data(withJSONObject: toolCallsDict, options: []),
           let toolCallsJsonString = String(data: toolCallsData, encoding: .utf8) {
            // Append assistant message with tool calls
            chat.requestMessages.append(
                RequestMessage(role: .assistant, toolCallsJson: toolCallsJsonString).dictionary
            )
        }
        
        // Execute each tool call
        for toolCall in toolCalls {
            if Task.isCancelled {
                await MainActor.run {
                    self.toolCallStatus = nil
                }
                await MainActor.run {
                    completion(.failure(CancellationError()))
                }
                return
            }
            let callId = toolCall.id
            let functionName = toolCall.function.name
            let arguments = toolCall.function.arguments
            
            #if DEBUG
            WardenLog.app.debug("Executing tool: \(functionName, privacy: .public)")
            #endif
            
            // Update UI with tool call status
            await MainActor.run {
                self.toolCallStatus = .calling(toolName: functionName)
                self.activeToolCalls.append(.calling(toolName: functionName))
            }
            
            var resultString = ""
            var success = true
            do {
                await MainActor.run {
                    self.toolCallStatus = .executing(toolName: functionName, progress: nil)
                    if let index = self.activeToolCalls.firstIndex(where: { $0.toolName == functionName }) {
                        self.activeToolCalls[index] = .executing(toolName: functionName, progress: nil)
                    }
                }
                
                if let argsData = arguments.data(using: .utf8),
                   let argsDict = try? JSONSerialization.jsonObject(with: argsData, options: []) as? [String: Any] {
                    let contentArray = try await MCPManager.shared.callTool(name: functionName, arguments: argsDict)
                    
                    // contentArray is already in JSON-compatible format [[String: Any]]
                    if let resultData = try? JSONSerialization.data(withJSONObject: contentArray, options: []),
                       let resultJson = String(data: resultData, encoding: .utf8) {
                        resultString = resultJson
                    } else {
                        resultString = "{\"result\": \"success\"}"
                    }
                } else {
                    resultString = "{\"error\": \"Invalid arguments JSON\"}"
                    success = false
                }
            } catch {
                resultString = "{\"error\": \"\(error.localizedDescription)\"}"
                success = false
                WardenLog.app.error("Tool execution failed (tool name omitted)")
                await MainActor.run {
                    self.toolCallStatus = .failed(toolName: functionName, error: error.localizedDescription)
                    if let index = self.activeToolCalls.firstIndex(where: { $0.toolName == functionName }) {
                        self.activeToolCalls[index] = .failed(toolName: functionName, error: error.localizedDescription)
                    }
                }
            }
            
            if success {
                await MainActor.run {
                    self.toolCallStatus = .completed(toolName: functionName, success: true, result: resultString)
                    if let index = self.activeToolCalls.firstIndex(where: { $0.toolName == functionName }) {
                        self.activeToolCalls[index] = .completed(toolName: functionName, success: true, result: resultString)
                    }
                }
            }
            
            #if DEBUG
            WardenLog.app.debug(
                "Tool result (\(functionName, privacy: .public)): \(resultString.count, privacy: .public) char(s)"
            )
            #endif
            
            // Append tool result message
            chat.requestMessages.append(
                RequestMessage(
                    role: .tool,
                    content: resultString,
                    name: functionName,
                    toolCallId: callId
                ).dictionary
            )
        }
        
        // Clear tool call status after all tools complete
        await MainActor.run {
            // Keep activeToolCalls for display, clear current status
            self.toolCallStatus = nil
        }
        
        // Now send the conversation again to get the final response
        let requestMessages = Array(chat.requestMessages.suffix(contextSize))
        let temperature = (chat.persona?.temperature ?? AppConstants.defaultTemperatureForChat).roundedToOneDecimal()
        
        ChatService.shared.sendMessage(
            apiService: self.apiService,
            messages: requestMessages,
            tools: nil, // Don't provide tools again to avoid loops
            temperature: temperature
        ) { [weak self] result in
            // Ensure all UI updates happen on main thread
            DispatchQueue.main.async {
                guard let self else {
                    chat.waitingForResponse = false
                    completion(.failure(APIError.invalidResponse))
                    return
                }
                if let streamRequestID,
                   !self.streamingSessions.session(for: chat.id).acceptsContinuation(requestID: streamRequestID) {
                    chat.waitingForResponse = false
                    return
                }
                switch result {
                case .success(let (fullMessage, toolCalls)):
                    guard let messageText = fullMessage,
                          !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        chat.waitingForResponse = false
                        completion(.failure(APIError.invalidResponse))
                        return
                    }
                    if let retryTarget {
                        self.persistStreamedAssistant(messageText, in: chat, retryTarget: retryTarget, searchUrls: nil)
                    } else {
                        // Store the tool calls with this message for persistence
                        let toolCallsToStore = self.activeToolCalls
                        self.addMessageToChat(chat: chat, message: messageText, searchUrls: nil, toolCalls: toolCallsToStore)
                        self.addNewMessageToRequestMessages(chat: chat, content: messageText, role: RequestMessageRole.assistant.rawValue)
                    }
                    chat.waitingForResponse = false
                    self.debounceSave()
                    self.generateChatNameIfNeeded(chat: chat)
                    
                    // Clear active tool calls for next message (they're now stored with the message)
                    self.activeToolCalls.removeAll()
                    if let streamRequestID {
                        self.streamingSessions.session(for: chat.id).finish(requestID: streamRequestID)
                    }
                    
                    completion(.success(()))
                    
                case .failure(let error):
                    // Keep tool calls visible on error for debugging
                    chat.waitingForResponse = false
                    if let streamRequestID {
                        self.streamingSessions.session(for: chat.id).finish(
                            requestID: streamRequestID,
                            errorDescription: "Tool continuation failed"
                        )
                    }
                    completion(.failure(error))
                }
            }
        }
    }

    func generateChatNameIfNeeded(chat: ChatEntity, force: Bool = false) {
        guard force || chat.name == "" || chat.name == "New Chat", chat.messages.count > 1 else {
            #if DEBUG
                WardenLog.app.debug("Chat name not needed (requires at least 2 messages), skipping generation")
            #endif
            return
        }
        
        // Only generate names if explicitly enabled on the API service
        guard chat.apiService?.generateChatNames ?? false else {
            #if DEBUG
                WardenLog.app.debug("Chat name generation not enabled for this API service, skipping")
            #endif
            return
        }
        
        // Skip chat name generation for image-generation models or image-only responses to avoid re-sending huge payloads/base64
        if let service = chat.apiService {
            let isImageService =
                (service.model?.localizedCaseInsensitiveContains("image") ?? false) ||
                (service.name?.localizedCaseInsensitiveContains("image") ?? false)
            if isImageService {
                #if DEBUG
                    WardenLog.app.debug("Chat name generation skipped for image-generation service")
                #endif
                return
            }
        }
        // Also skip if the latest assistant message appears to be an image-only payload
        if let messages = chat.messages as? Set<MessageEntity>,
           let lastAssistant = messages.filter({ $0.own == false }).sorted(by: { ($0.id) < ($1.id) }).last,
           lastAssistant.body.contains("<image-url>") {
            #if DEBUG
                WardenLog.app.debug("Chat name generation skipped due to image response in last assistant message")
            #endif
            return
        }

        let requestMessages = prepareRequestMessages(
            userMessage: AppConstants.chatGptGenerateChatInstruction,
            chat: chat,
            contextSize: 3
        )
        
        // Use a timeout-based approach to prevent hanging
        let deadline = Date(timeIntervalSinceNow: 30.0) // 30 second timeout
        
	        self.apiService.sendMessage(
	            requestMessages,
	            tools: nil,
	            temperature: AppConstants.defaultTemperatureForChatNameGeneration
	        ) {
	            [weak self] result in
	            guard let self = self else { return }
            
            // Skip if deadline has passed
            guard Date() < deadline else {
                #if DEBUG
                WardenLog.app.debug("Chat name generation timeout, skipping")
                #endif
                return
            }

            switch result {
            case .success(let (messageText, _)):
                guard let messageText = messageText else { return }
                let chatName = self.sanitizeChatName(messageText)
                guard !chatName.isEmpty else {
                    #if DEBUG
                    WardenLog.app.debug("Generated chat name was empty after sanitization, skipping")
                    #endif
                    return
                }
                
                Task { @MainActor in
                    chat.name = chatName
                    chat.updatedDate = Date()
                    self.debounceSave()
                    #if DEBUG
                    WardenLog.app.debug("Chat name generated: \(chatName, privacy: .public)")
                    #endif
                }
                
            case .failure(let error):
                // Silently skip - chat name generation is optional
                #if DEBUG
                    WardenLog.app.debug(
                        "Chat name generation skipped: \(error.localizedDescription, privacy: .public)"
                    )
                #endif
            }
        }
    }

    private func sanitizeChatName(_ rawName: String) -> String {
        if let range = rawName.range(of: "**(.+?)**", options: .regularExpression) {
            return String(rawName[range]).trimmingCharacters(in: CharacterSet(charactersIn: "*"))
        }

        let lines = rawName.components(separatedBy: .newlines)
        if let lastNonEmptyLine = lines.last(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            return lastNonEmptyLine.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return rawName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func testAPI(model: String, completion: @escaping (Result<Void, Error>) -> Void) {
        var requestMessages: [[String: String]] = []
        var temperature = AppConstants.defaultPersonaTemperature

        if !AppConstants.openAiReasoningModels.contains(model) {
            requestMessages.append(RequestMessage(role: .system, content: "You are a test assistant.").dictionary)
        }
        else {
            temperature = 1
        }

        requestMessages.append(
            RequestMessage(role: .user, content: "This is a test message.").dictionary
        )

	        self.apiService.sendMessage(requestMessages, tools: nil, temperature: temperature) { result in
	            switch result {
	            case .success(_):
	                completion(.success(()))

            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    private func prepareRequestMessages(userMessage: String, chat: ChatEntity, contextSize: Int) -> [[String: String]] {
        return chat.constructRequestMessages(forUserMessage: userMessage, contextSize: contextSize)
    }

    private func toolDefinitions(from tools: [Tool]) -> [[String: Any]] {
        tools.map { tool in
            [
                "type": "function",
                "function": [
                    "name": tool.name,
                    "description": tool.description ?? "",
                    "parameters": convertValueToDict(tool.inputSchema)
                ] as [String: Any]
            ]
        }
    }

    private func resolveRetryUserTurn(_ message: String, in chat: ChatEntity) -> MessageEntity {
        chat.messagesArray.last(where: { $0.own && $0.body == message })
            ?? chat.messagesArray.last(where: \.own)
            ?? MessageEntity(context: viewContext)
    }

    private func prepareRetryRequestMessages(intent: RetryIntent, chat: ChatEntity, contextSize: Int) -> [[String: String]] {
        guard intent.userTurn.chat == chat,
              let userIndex = chat.messagesArray.firstIndex(where: { $0 === intent.userTurn }) else {
            return prepareRequestMessages(userMessage: intent.userTurn.body, chat: chat, contextSize: contextSize)
        }
        let originalMessages = chat.messages
        let prefix = Array(chat.messagesArray.prefix(through: userIndex))
        let boundedPrefix = contextSize > 0 ? Array(prefix.suffix(contextSize)) : []
        chat.messages = NSOrderedSet(array: boundedPrefix)
        defer { chat.messages = originalMessages }
        return chat.constructRequestMessages(forUserMessage: nil, contextSize: contextSize)
    }

    private func persistStreamedAssistant(
        _ content: String,
        in chat: ChatEntity,
        retryTarget: MessageEntity?,
        searchUrls: [String]?,
        searchMetadata: MessageSearchMetadata? = nil
    ) {
        guard !content.isEmpty else { return }
        if let retryTarget, retryTarget.managedObjectContext != nil {
            let finalContent: String
            if let searchUrls, !searchUrls.isEmpty {
                finalContent = tavilyService.convertCitationsToLinks(content, urls: searchUrls)
            } else {
                finalContent = content
            }
            retryTarget.body = finalContent
            retryTarget.timestamp = Date()
            chat.requestMessages = chat.messagesArray.map {
                RequestMessage(role: $0.own ? .user : .assistant, content: $0.body).dictionary
            }
            chat.updatedDate = Date()
            chat.objectWillChange.send()
            debounceSave()
        } else {
            addMessageToChat(chat: chat, message: content, searchUrls: searchUrls, searchMetadata: searchMetadata)
            addNewMessageToRequestMessages(chat: chat, content: content, role: RequestMessageRole.assistant.rawValue)
        }
    }
    
    private func containsImageInputs(in messages: [[String: String]]) -> Bool {
        for message in messages {
            guard let role = message["role"], role == "user", let content = message["content"] else { continue }
            if content.contains("<image-uuid>") || content.contains("<file-uuid>") || content.contains("data:image/") {
                return true
            }
        }
        return false
    }

    private func isVisionModelName(_ model: String) -> Bool {
        let name = model.lowercased()
        return name.contains("vision") || name.contains("vl") || name.contains("pixtral") || name.contains("llava")
    }

    private func sanitizeRequestMessagesForText(_ messages: [[String: String]]) -> [[String: String]] {
        // Redact image tags and large base64 blobs so they don't leak into text-only prompts
        let base64LikePattern = "[A-Za-z0-9+/=]{512,}"
        let regex = try? NSRegularExpression(pattern: base64LikePattern, options: [])
        return messages.compactMap { msg in
            var sanitized = msg
            guard var content = msg["content"] else { return msg }
            // Remove obvious image markers
            if content.contains("<image-url>") || content.contains("<image-uuid>") || content.contains("data:image/") {
                content = content.replacingOccurrences(of: "<image-url>", with: "[image omitted]")
                content = content.replacingOccurrences(of: "<image-uuid>", with: "[image omitted]")
                // Redact data URL header quickly
                if let range = content.range(of: "data:image/") {
                    content.replaceSubrange(range.lowerBound..<content.endIndex, with: "[image data omitted]")
                }
            }
            // Redact long base64-like sequences
            if let regex = regex {
                let ns = content as NSString
                let range = NSRange(location: 0, length: ns.length)
                var result = content
                var offset = 0
                regex.enumerateMatches(in: content, options: [], range: range) { match, _, _ in
                    guard let match = match else { return }
                    let r = NSRange(location: match.range.location + offset, length: match.range.length)
                    if let swiftRange = Range(r, in: result) {
                        result.replaceSubrange(swiftRange, with: "[base64 omitted]")
                        offset += "[base64 omitted]".count - match.range.length
                    }
                }
                content = result
            }
            // If after redaction it's effectively empty or only an omission marker, keep the marker
            if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                content = "[omitted image response]"
            }
            sanitized["content"] = content
            return sanitized
        }
    }

    private func addMessageToChat(chat: ChatEntity, message: String, searchUrls: [String]? = nil, searchMetadata: MessageSearchMetadata? = nil, toolCalls: [WardenToolCallStatus]? = nil, isStreaming: Bool = false) {
        assert(Thread.isMainThread, "addMessageToChat must be called on main thread")
        #if DEBUG
        WardenLog.app.debug("AI response received: \(message.count, privacy: .public) char(s)")
        #endif
        
        // Convert citations to clickable links if we have search URLs
        let finalMessage: String
        if let urls = searchUrls, !urls.isEmpty {
            finalMessage = tavilyService.convertCitationsToLinks(message, urls: urls)
        } else {
            finalMessage = message
        }
        
        #if DEBUG
        if finalMessage.contains("<image-url>") {
            WardenLog.app.debug("Appending message with <image-url> tag (length: \(finalMessage.count, privacy: .public))")
        }
        #endif
        
        #if DEBUG
        WardenLog.app.debug("AI response after conversion: \(finalMessage.count, privacy: .public) char(s)")
        #endif
        
        let newMessage = MessageEntity(context: self.viewContext)
        newMessage.id = Int64(chat.messages.count + 1)
        newMessage.body = finalMessage
        newMessage.timestamp = Date()
        newMessage.own = false
        newMessage.waitingForResponse = isStreaming
        newMessage.chat = chat
        
        // Snapshot provider metadata for this message
        if !(newMessage.isMultiAgentResponse ?? false), let service = chat.apiService {
            newMessage.agentServiceName = service.name
            newMessage.agentServiceType = service.type
            newMessage.agentModel = chat.gptModel ?? service.model
        }
        
        // Store tool calls associated with this message
        if let toolCalls = toolCalls, !toolCalls.isEmpty {
            messageToolCalls[newMessage.id] = toolCalls
            newMessage.toolCalls = toolCalls
        }
        
        // Store search metadata if we have search results
        if let searchMetadata {
            newMessage.searchMetadata = searchMetadata
            #if DEBUG
            WardenLog.app.debug("Saved search metadata: \(searchMetadata.resultCount, privacy: .public) source(s)")
            #endif
        }
        
        #if DEBUG
        WardenLog.app.debug("Persisting assistant message. isStreaming=\(isStreaming, privacy: .public) bodyLength=\(finalMessage.count, privacy: .public)")
        #endif

        chat.updatedDate = Date()
        chat.addToMessages(newMessage)
        if isStreaming {
            chat.waitingForResponse = true
        }
        chat.objectWillChange.send()
    }
    
    private func addNewMessageToRequestMessages(chat: ChatEntity, content: String, role: String) {
        let roleEnum = RequestMessageRole(rawValue: role) ?? .assistant
        chat.requestMessages.append(RequestMessage(role: roleEnum, content: content).dictionary)
        self.debounceSave()
    }

    private func updateLastMessage(
        chat: ChatEntity,
        lastMessage: MessageEntity,
        accumulatedResponse: String,
        searchUrls: [String]? = nil,
        appendCitations: Bool = false,
        save: Bool = false,
        isFinalUpdate: Bool = false
    ) {
        assert(Thread.isMainThread, "updateLastMessage must be called on main thread")
        #if DEBUG
        WardenLog.streaming.debug("Streaming update: \(accumulatedResponse.count, privacy: .public) char(s) accumulated")
        #endif
        
        // Only convert citations at the final update, not during intermediate streaming updates
        let finalMessage: String
        if appendCitations, let urls = searchUrls, !urls.isEmpty {
            finalMessage = tavilyService.convertCitationsToLinks(accumulatedResponse, urls: urls)
        } else {
            finalMessage = accumulatedResponse
        }
        
        lastMessage.body = finalMessage
        lastMessage.timestamp = Date()
        if isFinalUpdate {
            chat.waitingForResponse = false
            lastMessage.waitingForResponse = false
        }

        chat.objectWillChange.send()

        if save {
            self.debounceSave()
        }
    }

}
