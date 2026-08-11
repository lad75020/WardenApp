import Foundation
import CoreData
import os

class APIServiceManager {
    enum EndpointValidationError: Error, Equatable {
        case invalidEndpoint
        case insecureCredentialTransport
    }

    enum LifecycleError: Error, Equatable {
        case persistenceFailed
        case credentialFailed
        case invalidService
    }

    enum LifecycleResult: Equatable {
        case saved
        case deleted(defaultCleared: Bool)
        case duplicated
        case defaultSet
    }

    private let viewContext: NSManagedObjectContext
    private let defaults: UserDefaults
    
    init(viewContext: NSManagedObjectContext, defaults: UserDefaults = .standard) {
        self.viewContext = viewContext
        self.defaults = defaults
    }

    /// Validates a user-entered endpoint before any save or network operation.
    /// Remote plaintext is allowed only when it carries no credential.
    static func validateEndpoint(_ rawValue: String, credential: String) -> Result<URL, EndpointValidationError> {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              let host = url.host,
              !host.isEmpty,
              scheme == "http" || scheme == "https"
        else {
            return .failure(.invalidEndpoint)
        }

        if !credential.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !url.allowsSensitiveTransport {
            return .failure(.insecureCredentialTransport)
        }
        return .success(url)
    }

    static func userSafeEndpointMessage(for error: EndpointValidationError) -> String {
        switch error {
        case .invalidEndpoint:
            return "Enter a valid HTTP or HTTPS service URL."
        case .insecureCredentialTransport:
            return "Use HTTPS for a remote service with an API token, or use a loopback HTTP URL for a local service."
        }
    }

    /// Maps failures to stable user-facing categories; never interpolate provider bodies or credentials.
    static func userSafeErrorMessage(for error: Error) -> String {
        if let endpointError = error as? EndpointValidationError {
            return userSafeEndpointMessage(for: endpointError)
        }
        if let apiError = error as? APIError {
            switch apiError {
            case .unauthorized:
                return "Authentication failed. Check the API token."
            case .rateLimited:
                return "The service is rate limited. Try again shortly."
            case .invalidResponse, .decodingFailed:
                return "The service returned an invalid response. Check the service URL."
            case .serverError:
                return "The service returned an error. Please try again later."
            case .requestFailed(let requestError):
                let nsError = requestError as NSError
                if nsError.code == NSURLErrorTimedOut {
                    return "The request timed out. Check the service and try again."
                }
                return "Could not reach the service. Check the service URL and network connection."
            case .noApiService:
                return "The service configuration is not valid for this request."
            case .unknown:
                return "The service request could not be completed."
            }
        }
        return "The service request could not be completed."
    }

    static func allowsStreaming(providerType: String, model: String) -> Bool {
        let provider = providerType.lowercased()
        return !provider.contains("image") && !model.lowercased().hasPrefix("gpt-image")
    }

    @discardableResult
    func saveAPIService(
        _ service: APIServiceEntity?,
        name: String,
        type: String,
        url: URL,
        model: String,
        contextSize: Int16,
        useStreamResponse: Bool,
        generateChatNames: Bool,
        imageUploadsAllowed: Bool,
        defaultPersona: PersonaEntity?,
        credential: String
    ) -> Result<APIServiceEntity, LifecycleError> {
        var result: Result<APIServiceEntity, LifecycleError> = .failure(.persistenceFailed)
        viewContext.performAndWait {
            let isNew = service == nil
            let target = service ?? APIServiceEntity(context: viewContext)
            if target.id == nil { target.id = UUID() }
            target.name = name
            target.type = type
            target.url = url
            target.model = model
            target.contextSize = contextSize
            target.useStreamResponse = Self.allowsStreaming(providerType: type, model: model) && useStreamResponse
            target.generateChatNames = generateChatNames
            target.imageUploadsAllowed = imageUploadsAllowed
            target.defaultPersona = defaultPersona
            if isNew { target.addedDate = Date() } else { target.editedDate = Date() }

            do {
                try viewContext.save()
            } catch {
                viewContext.rollback()
                result = .failure(.persistenceFailed)
                return
            }

            guard let identifier = target.id?.uuidString else {
                result = .failure(.invalidService)
                return
            }
            do {
                if credential.isEmpty {
                    try TokenManager.deleteToken(for: identifier)
                } else {
                    try TokenManager.setToken(credential, for: identifier)
                }
                result = .success(target)
            } catch {
                // Metadata is already durable and remains recoverable; no secret is logged.
                result = .failure(.credentialFailed)
            }
        }
        return result
    }

    @discardableResult
    func duplicateAPIService(_ service: APIServiceEntity) -> Result<APIServiceEntity, LifecycleError> {
        var result: Result<APIServiceEntity, LifecycleError> = .failure(.persistenceFailed)
        viewContext.performAndWait {
            let copy = APIServiceEntity(context: viewContext)
            copy.id = UUID()
            copy.name = (service.name ?? "Untitled Service") + " Copy"
            copy.type = service.type
            copy.url = service.url
            copy.model = service.model
            copy.contextSize = service.contextSize
            copy.useStreamResponse = service.useStreamResponse
            copy.generateChatNames = service.generateChatNames
            copy.imageUploadsAllowed = service.imageUploadsAllowed
            copy.defaultPersona = service.defaultPersona
            copy.addedDate = Date()
            do {
                try viewContext.save()
                if let sourceID = service.id?.uuidString,
                   let copyID = copy.id?.uuidString,
                   let token = try TokenManager.getToken(for: sourceID) {
                    try TokenManager.setToken(token, for: copyID)
                }
                result = .success(copy)
            } catch {
                // Do not delete or overwrite the source service/token on a failed copy.
                result = .failure(.credentialFailed)
            }
        }
        return result
    }

    @discardableResult
    func deleteAPIServiceTransactionally(_ service: APIServiceEntity) -> Result<LifecycleResult, LifecycleError> {
        var result: Result<LifecycleResult, LifecycleError> = .failure(.persistenceFailed)
        viewContext.performAndWait {
            guard let identifier = service.id?.uuidString else {
                result = .failure(.invalidService)
                return
            }
            let uri = service.objectID.uriRepresentation().absoluteString
            viewContext.delete(service)
            do {
                try viewContext.save()
            } catch {
                viewContext.rollback()
                result = .failure(.persistenceFailed)
                return
            }
            let wasDefault = defaults.string(forKey: "defaultApiService") == uri
            if wasDefault { defaults.removeObject(forKey: "defaultApiService") }
            do {
                try TokenManager.deleteToken(for: identifier)
                result = .success(.deleted(defaultCleared: wasDefault))
            } catch {
                result = .failure(.credentialFailed)
            }
        }
        return result
    }

    @discardableResult
    func setDefaultAPIService(_ service: APIServiceEntity) -> Result<LifecycleResult, LifecycleError> {
        guard !service.objectID.isTemporaryID else { return .failure(.invalidService) }
        defaults.set(service.objectID.uriRepresentation().absoluteString, forKey: "defaultApiService")
        return .success(.defaultSet)
    }
    
    func createAPIService(name: String, type: String, url: URL, model: String, contextSize: Int16, useStreamResponse: Bool, generateChatNames: Bool) -> APIServiceEntity {
        var apiService: APIServiceEntity!
        viewContext.performAndWait {
            apiService = APIServiceEntity(context: viewContext)
            apiService.id = UUID()
            apiService.name = name
            apiService.type = type
            apiService.url = url
            apiService.model = model
            apiService.contextSize = contextSize
            apiService.useStreamResponse = useStreamResponse
            apiService.generateChatNames = generateChatNames
            apiService.tokenIdentifier = UUID().uuidString
            
            do {
                try viewContext.save()
            } catch {
                WardenLog.coreData.error("Error saving API service: \(error.localizedDescription, privacy: .public)")
            }
        }
        return apiService
    }
    
    func updateAPIService(_ apiService: APIServiceEntity, name: String, type: String, url: URL, model: String, contextSize: Int16, useStreamResponse: Bool, generateChatNames: Bool) {
        viewContext.performAndWait {
            apiService.name = name
            apiService.type = type
            apiService.url = url
            apiService.model = model
            apiService.contextSize = contextSize
            apiService.useStreamResponse = useStreamResponse
            apiService.generateChatNames = generateChatNames
            
            do {
                try viewContext.save()
            } catch {
                WardenLog.coreData.error("Error updating API service: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
    
    func deleteAPIService(_ apiService: APIServiceEntity) {
        viewContext.performAndWait {
            viewContext.delete(apiService)
            
            do {
                try viewContext.save()
            } catch {
                WardenLog.coreData.error("Error deleting API service: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
    
    func getAllAPIServices() -> [APIServiceEntity] {
        let fetchRequest: NSFetchRequest<APIServiceEntity> = APIServiceEntity.fetchRequest()
        
        do {
            return try viewContext.fetch(fetchRequest)
        } catch {
            WardenLog.coreData.error("Error fetching API services: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }
    
    func getAPIService(withID id: UUID) -> APIServiceEntity? {
        let fetchRequest: NSFetchRequest<APIServiceEntity> = APIServiceEntity.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        
        do {
            let results = try viewContext.fetch(fetchRequest)
            return results.first
        } catch {
            WardenLog.coreData.error("Error fetching API service: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
    
    // MARK: - AI Summarization Support
    
    /// Generates a summary using the user's preferred AI service
    /// - Parameters:
    ///   - prompt: The prompt for summarization
    ///   - maxTokens: Maximum tokens in response (currently not used by all handlers)
    ///   - temperature: Temperature for AI generation
    /// - Returns: Generated summary text
    func generateSummary(prompt: String, maxTokens: Int = 800, temperature: Float = 0.3) async throws -> String {
        // Get the user's preferred API service from UserDefaults
        let currentAPIServiceName = UserDefaults.standard.string(forKey: "currentAPIService") ?? "ChatGPT"
        
        // Try to find a matching API service entity
        let apiService = findAPIServiceForSummarization(preferredType: currentAPIServiceName)
        
        guard let service = apiService else {
            throw APIError.noApiService("No suitable API service available for summarization")
        }
        
        // Create API configuration
        guard let config = APIServiceManager.createAPIConfiguration(for: service) else {
            throw APIError.noApiService("Failed to create API configuration for summarization")
        }
        
        // Create API service instance using factory
        let apiServiceInstance = APIServiceFactory.createAPIService(config: config)
        
        // Prepare messages for summarization request
        let requestMessages = prepareSummarizationMessages(prompt: prompt, model: service.model ?? "")
        
        #if DEBUG
        WardenLog.app.debug("Generating summary using service: \(service.name ?? "Unknown", privacy: .public)")
        WardenLog.app.debug("Summary model: \(service.model ?? "Unknown", privacy: .public)")
        #endif
        
        // Use async/await with continuation to bridge callback-based API
        return try await withCheckedThrowingContinuation { continuation in
	            apiServiceInstance.sendMessage(requestMessages, tools: nil, temperature: temperature) { result in
	                switch result {
	                case .success(let (messageContent, _)):
	                    guard let messageContent = messageContent else {
	                         continuation.resume(throwing: APIError.invalidResponse)
	                         return
                    }
                    let cleanedResponse = self.cleanSummarizationResponse(messageContent)
                    continuation.resume(returning: cleanedResponse)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    /// Finds the best available API service for summarization
    private func findAPIServiceForSummarization(preferredType: String) -> APIServiceEntity? {
        let allServices = getAllAPIServices()
        
        // First, try to find the user's preferred service type
        if let preferredService = allServices.first(where: { 
            $0.type?.lowercased() == preferredType.lowercased() 
        }) {
            return preferredService
        }
        
        // Fallback to any available service (prioritize reliable ones for summarization)
        let priorityOrder = ["chatgpt", "claude", "gemini", "deepseek", "perplexity"]
        
        for serviceType in priorityOrder {
            if let service = allServices.first(where: { 
                $0.type?.lowercased() == serviceType 
            }) {
                return service
            }
        }
        
        // Last resort: return any available service
        return allServices.first
    }
    
    /// Creates API configuration for the given service
    static func createAPIConfiguration(for service: APIServiceEntity, modelOverride: String? = nil) -> APIServiceConfiguration? {
        guard let apiServiceUrl = service.url,
              let serviceType = service.type else {
            return nil
        }
        
        // Get API key from secure storage
        var apiKey = ""
        do {
            apiKey = try TokenManager.getToken(for: service.id?.uuidString ?? "") ?? ""
        } catch {
            WardenLog.app.error("Error extracting token: \(error.localizedDescription, privacy: .public)")
            apiKey = ""
        }
        
        // Ensure we have a valid API key (except for local services like Ollama/LMStudio which might not need one)
        // But generally we want to return the config and let the handler decide
        
        return APIServiceConfig(
            name: serviceType,
            apiUrl: apiServiceUrl,
            apiKey: apiKey,
            model: modelOverride ?? service.model ?? getDefaultModelForService(serviceType)
        )
    }
    
    /// Handles streaming response from API service with standardized error handling and cancellation support
    /// - Parameters:
    ///   - apiService: The API service instance to use
    ///   - messages: The messages to send
    ///   - tools: Optional list of tools to include in the request
    ///   - temperature: The temperature setting
    ///   - onChunk: Closure called with each new chunk (buffered by update interval)
    /// - Returns: Any tool calls emitted during streaming
    static func handleStream(
        apiService: APIService,
        messages: [[String: String]],
        tools: [[String: Any]]? = nil,
        temperature: Float,
        onChunk: @MainActor @escaping (String) async -> Void
    ) async throws -> [ToolCall]? {
        // Images/generations endpoint does not support streaming; enforce non-stream usage
        let isImageGeneration = apiService.name.lowercased().contains("image") || apiService.model.lowercased().hasPrefix("gpt-image")
        if isImageGeneration {
            throw APIError.invalidResponse
        }
        
        let stream = try await apiService.sendMessageStream(messages, tools: tools, temperature: temperature)
        var pendingChunkParts: [String] = []
        var pendingChunkCharacterCount = 0
        let updateInterval = AppConstants.streamedResponseUpdateUIInterval
        var lastFlushTime = Date()
        var allToolCalls: [ToolCall]? = nil
        
        #if DEBUG
        let streamSignpostID = OSSignpostID(log: WardenSignpost.streaming)
        os_signpost(.begin, log: WardenSignpost.streaming, name: "Stream", signpostID: streamSignpostID)
        
        let ttftSignpostID = OSSignpostID(log: WardenSignpost.streaming)
        os_signpost(.begin, log: WardenSignpost.streaming, name: "TTFT", signpostID: ttftSignpostID)
        var didEndTTFT = false
        
        var flushCount = 0
        var flushedCharacterCount = 0
        #endif

        func drainPendingChunkBuffer() -> String {
            var result = String()
            result.reserveCapacity(pendingChunkCharacterCount)
            for part in pendingChunkParts {
                result.append(contentsOf: part)
            }
            pendingChunkParts.removeAll(keepingCapacity: true)
            pendingChunkCharacterCount = 0
            return result
        }

        func flushPendingChunkBuffer() async {
            guard !pendingChunkParts.isEmpty else { return }
            let chunkToSend = drainPendingChunkBuffer()
            
            #if DEBUG
            if !didEndTTFT {
                didEndTTFT = true
                os_signpost(.end, log: WardenSignpost.streaming, name: "TTFT", signpostID: ttftSignpostID)
            }
            flushCount += 1
            flushedCharacterCount += chunkToSend.count
            os_signpost(
                .event,
                log: WardenSignpost.streaming,
                name: "ChunkFlush",
                signpostID: streamSignpostID,
                "flush=%{public}d chars=%{public}d total=%{public}d",
                flushCount,
                chunkToSend.count,
                flushedCharacterCount
            )
            #endif
            await onChunk(chunkToSend)
        }
        
        for try await (chunk, toolCalls) in stream {
            try Task.checkCancellation()
            
            if let chunk = chunk, !chunk.isEmpty {
                let shouldFlushImmediately = chunk.contains("<image-uuid>") || chunk.contains("<file-uuid>")

                if shouldFlushImmediately, !pendingChunkParts.isEmpty {
                    await flushPendingChunkBuffer()
                    lastFlushTime = Date()
                }

                pendingChunkParts.append(chunk)
                pendingChunkCharacterCount += chunk.count

                let now = Date()
                if shouldFlushImmediately || now.timeIntervalSince(lastFlushTime) >= updateInterval {
                    await flushPendingChunkBuffer()
                    lastFlushTime = now
                }
            }
            
            if let calls = toolCalls {
                if allToolCalls == nil {
                    allToolCalls = []
                }
                allToolCalls?.append(contentsOf: calls)
            }
        }

        await flushPendingChunkBuffer()
        
        #if DEBUG
        if !didEndTTFT {
            didEndTTFT = true
            os_signpost(.end, log: WardenSignpost.streaming, name: "TTFT", signpostID: ttftSignpostID)
        }
        os_signpost(.end, log: WardenSignpost.streaming, name: "Stream", signpostID: streamSignpostID)
        #endif
        
        return allToolCalls
    }
    
    /// Prepares messages specifically formatted for summarization requests
    private func prepareSummarizationMessages(prompt: String, model: String) -> [[String: String]] {
        var messages: [[String: String]] = []
        
        // For reasoning models (o1, o3), we need to handle system message differently
        if AppConstants.openAiReasoningModels.contains(model) {
            // Reasoning models don't support system role, so we embed instructions in user message
            let combinedPrompt = """
            You are an AI assistant specialized in creating concise and insightful project summaries. Your task is to analyze project data and generate comprehensive summaries that highlight key themes, progress, and insights.
            
            Please provide a clear, well-structured summary for the following project:
            
            \(prompt)
            
            Focus on:
            - Key themes and topics
            - Project progress and insights
            - Notable patterns or achievements
            - Areas of focus or expertise demonstrated
            
            Keep the summary informative but concise (under 500 words).
            """
            
            messages.append([
                "role": "user",
                "content": combinedPrompt
            ])
        } else {
            // Standard models support system role
            messages.append([
                "role": "system",
                "content": """
                You are an AI assistant specialized in creating concise and insightful project summaries. 
                Your task is to analyze project data and generate comprehensive summaries that highlight 
                key themes, progress, and insights. Focus on extracting meaningful patterns and providing 
                actionable insights. Keep summaries informative but concise (under 500 words).
                """
            ])
            
            messages.append([
                "role": "user",
                "content": prompt
            ])
        }
        
        return messages
    }
    
    /// Gets default model for a service type
    static func getDefaultModelForService(_ serviceType: String) -> String {
        switch serviceType.lowercased() {
        case "chatgpt":
            return AppConstants.chatGptDefaultModel
        case "chatgpt image":
            return "gpt-image-1"
        case "claude":
            return "claude-3-5-sonnet-20241022"
        case "gemini":
            return "gemini-1.5-pro"
        case "deepseek":
            return "deepseek-chat"
        case "perplexity":
            return "llama-3.1-sonar-small-128k-online"
        default:
            return AppConstants.chatGptDefaultModel
        }
    }
    
    /// Cleans and formats the AI response for better presentation
    private func cleanSummarizationResponse(_ response: String) -> String {
        var cleaned = response.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Remove any markdown formatting that might be problematic
        cleaned = cleaned.replacingOccurrences(of: "```", with: "")
        
        // Ensure the response isn't too long
        if cleaned.count > 1000 {
            // Truncate at the last complete sentence within limit
            let truncated = String(cleaned.prefix(950))
            if let lastPeriod = truncated.lastIndex(of: ".") {
                cleaned = String(truncated[...lastPeriod])
            } else {
                cleaned = truncated + "..."
            }
        }
        
        return cleaned
    }
}

