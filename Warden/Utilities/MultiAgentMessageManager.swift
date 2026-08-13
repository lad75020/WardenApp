import CoreData
import Foundation

/// Manages simultaneous communication with multiple AI services
@MainActor
final class MultiAgentMessageManager: ObservableObject {
    private var viewContext: NSManagedObjectContext
    private var lastUpdateTime = Date()
    private let updateInterval = AppConstants.streamedResponseUpdateUIInterval
    private var activeTasks: [Task<Void, Never>] = []
    
    @Published var activeAgents: [AgentResponse] = []
    @Published var isProcessing = false
    
    init(viewContext: NSManagedObjectContext) {
        self.viewContext = viewContext
    }
    
    func stopStreaming() {
        // Cancel all active tasks
        activeTasks.forEach { $0.cancel() }
        activeTasks.removeAll()
        
        // Update state
        isProcessing = false
        
        // Mark incomplete agents as cancelled.
        Self.finalizeCancellation(of: &activeAgents, message: "Request cancelled by user")
    }
    
    /// Represents a response from a single agent/service
    struct AgentResponse: Identifiable {
        let id = UUID()
        let serviceName: String
        let serviceType: String
        let model: String
        var response: String = ""
        var isComplete: Bool = false
        var error: APIError?
        var timestamp: Date = Date()
        
        var displayName: String {
            return "\(serviceName) (\(model))"
        }

        mutating func markCompleted() {
            isComplete = true
            timestamp = Date()
        }

        mutating func markFailed(_ failure: APIError) {
            error = failure
            markCompleted()
        }
    }

    static func cappedServices<T>(_ services: [T]) -> [T] {
        Array(services.prefix(AppConstants.MultiAgent.maxConcurrentServices))
    }

    static func finalizeCancellation(of responses: inout [AgentResponse], message: String) {
        for index in responses.indices where !responses[index].isComplete {
            responses[index].markFailed(.unknown(message))
        }
    }
    
    /// Sends a message to multiple AI services simultaneously
    func sendMessageToMultipleServices(
        _ message: String,
        chat: ChatEntity,
        selectedServices: [APIServiceEntity],
        contextSize: Int,
        completion: @escaping (Result<[AgentResponse], Error>) -> Void
    ) {
        guard !selectedServices.isEmpty else {
            completion(.failure(APIError.noApiService("No services selected")))
            return
        }
        
        // Limit to the shared maximum number of services for optimal UX.
        let limitedServices = Self.cappedServices(selectedServices)
        
        isProcessing = true
        activeAgents = []
        activeTasks.removeAll() // Clear any previous tasks
        
        let requestMessages = chat.constructRequestMessages(forUserMessage: message, contextSize: contextSize)
        let temperature = (chat.persona?.temperature ?? AppConstants.defaultTemperatureForChat).roundedToOneDecimal()
        
        let dispatchGroup = DispatchGroup()
        
        // Create initial agent responses
        for service in limitedServices {
            let agentResponse = AgentResponse(
                serviceName: service.name ?? "Unknown",
                serviceType: service.type ?? "unknown",
                model: service.model ?? "unknown"
            )
            activeAgents.append(agentResponse)
        }
        
        // Send requests to all services concurrently
        for (index, service) in limitedServices.enumerated() {
            dispatchGroup.enter()
            
            guard let config = APIServiceManager.createAPIConfiguration(for: service) else {
                activeAgents[index].error = APIError.noApiService("Invalid configuration")
                activeAgents[index].isComplete = true
                dispatchGroup.leave()
                continue
            }
            
            let apiService = APIServiceFactory.createAPIService(config: config)
            
            // Use streaming if supported
            if service.useStreamResponse {
                sendStreamRequest(
                    apiService: apiService,
                    requestMessages: requestMessages,
                    temperature: temperature,
                    agentIndex: index,
                    dispatchGroup: dispatchGroup
                )
            } else {
                sendRegularRequest(
                    apiService: apiService,
                    requestMessages: requestMessages,
                    temperature: temperature,
                    agentIndex: index,
                    dispatchGroup: dispatchGroup
                )
            }
        }
        
        // Wait for all requests to complete
        dispatchGroup.notify(queue: .main) {
            self.isProcessing = false
            self.activeTasks.removeAll() // Clear completed tasks
            completion(.success(self.activeAgents))
        }
    }
    
    private func sendStreamRequest(
        apiService: APIService,
        requestMessages: [[String: String]],
        temperature: Float,
        agentIndex: Int,
        dispatchGroup: DispatchGroup
    ) {
        let task = Task {
            do {
                await MainActor.run {
                    if agentIndex < self.activeAgents.count {
                        self.activeAgents[agentIndex].response = ""
                        self.activeAgents[agentIndex].timestamp = Date()
                    }
                }

                _ = try await ChatService.shared.sendStream(
                    apiService: apiService,
                    messages: requestMessages,
                    temperature: temperature
                ) { chunk in
                    await MainActor.run {
                        if agentIndex < self.activeAgents.count {
                            self.activeAgents[agentIndex].response.append(contentsOf: chunk)
                            self.activeAgents[agentIndex].timestamp = Date()
                        }
                    }
                }
                
                // Only complete if not cancelled
                if !Task.isCancelled {
                    await MainActor.run {
                        if agentIndex < self.activeAgents.count {
                            self.activeAgents[agentIndex].markCompleted()
                        }
                    }
                }
                
                dispatchGroup.leave()
            } catch is CancellationError {
                await MainActor.run {
                    if agentIndex < self.activeAgents.count {
                        self.activeAgents[agentIndex].markFailed(.unknown("Request cancelled"))
                    }
                }
                dispatchGroup.leave()
            } catch {
                await MainActor.run {
                    if agentIndex < self.activeAgents.count {
                        self.activeAgents[agentIndex].markFailed(error as? APIError ?? APIError.unknown(error.localizedDescription))
                    }
                }
                dispatchGroup.leave()
            }
        }
        
        // Track the task for potential cancellation
        activeTasks.append(task)
    }
    
    private func sendRegularRequest(
        apiService: APIService,
        requestMessages: [[String: String]],
        temperature: Float,
        agentIndex: Int,
        dispatchGroup: DispatchGroup
    ) {
        ChatService.shared.sendMessage(
            apiService: apiService,
            messages: requestMessages,
            temperature: temperature
        ) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self, agentIndex < self.activeAgents.count else {
                    dispatchGroup.leave()
                    return
                }
                
                switch result {
                case .success(let (responseText, _)):
                    self.activeAgents[agentIndex].response = responseText ?? "No response"
                    self.activeAgents[agentIndex].markCompleted()
                    
                case .failure(let error):
                    self.activeAgents[agentIndex].markFailed(error as? APIError ?? APIError.unknown(error.localizedDescription))
                }
                
                dispatchGroup.leave()
            }
        }
    }
    
    
    }
