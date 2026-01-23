import Combine
import Foundation
import SwiftUI
import os

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages: NSOrderedSet
    @Published var streamingAssistantText: String = ""
    private let chat: ChatEntity
    private let viewContext: NSManagedObjectContext

    private var _messageManager: MessageManager?
    var messageManager: MessageManager? {
        get {
            // Check if we've already failed to create a message manager
            guard !messageManagerCreationFailed else {
                #if DEBUG
                WardenLog.app.debug(
                    "Skipping message manager creation - previous attempt failed for chat \(self.chat.id.uuidString, privacy: .public)"
                )
                #endif
                return nil
            }
            
            if _messageManager == nil {
                _messageManager = createMessageManager()
                // Restore cached search results if available
                if let cachedSources = cachedSearchSources {
                    _messageManager?.lastSearchSources = cachedSources
                }
                if let cachedQuery = cachedSearchQuery {
                    _messageManager?.lastSearchQuery = cachedQuery
                }
                if let manager = _messageManager {
                    setupStreamingBindings(for: manager)
                } else {
                    streamingAssistantText = ""
                    messageManagerCancellables.removeAll()
                }
            }
            return _messageManager
        }
        set {
            _messageManager = newValue
        }
    }
    
    // Track if we've already failed to create a message manager to prevent loops
    private var messageManagerCreationFailed = false
    
    // Cache search results at ChatViewModel level to persist across message manager recreation
    private var cachedSearchSources: [SearchSource]?
    private var cachedSearchQuery: String?

    private var cancellables = Set<AnyCancellable>()
    private var messageManagerCancellables = Set<AnyCancellable>()

    init(chat: ChatEntity, viewContext: NSManagedObjectContext) {
        self.chat = chat
        self.messages = chat.messages
        self.viewContext = viewContext
        
        // Subscribe to search results changes to cache them
        setupSearchResultsCaching()
        
        // Load selected MCP agents
        loadSelectedMCPAgents()
    }
    
    @Published var selectedMCPAgents: Set<UUID> = [] {
        didSet {
            saveSelectedMCPAgents()
        }
    }
    
    private func loadSelectedMCPAgents() {
        let key = "SelectedMCPAgents_\(chat.id.uuidString)"
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode(Set<UUID>.self, from: data) {
            self.selectedMCPAgents = decoded
        }
    }
    
    private func saveSelectedMCPAgents() {
        let key = "SelectedMCPAgents_\(chat.id.uuidString)"
        if let encoded = try? JSONEncoder().encode(selectedMCPAgents) {
            UserDefaults.standard.set(encoded, forKey: key)
        }
    }
    
    private func setupSearchResultsCaching() {
        // Observe changes to search results and cache them
        messageManager?.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                if let sources = self?.messageManager?.lastSearchSources {
                    self?.cachedSearchSources = sources
                }
                if let query = self?.messageManager?.lastSearchQuery {
                    self?.cachedSearchQuery = query
                }
            }
            .store(in: &cancellables)
    }
    
    private func setupStreamingBindings(for manager: MessageManager) {
        messageManagerCancellables.removeAll()
        
        manager.$streamingAssistantText
            .receive(on: DispatchQueue.main)
            .sink { [weak self] text in
                self?.streamingAssistantText = text
            }
            .store(in: &messageManagerCancellables)
    }

    func sendMessage(_ message: String, contextSize: Int, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let messageManager = self.messageManager else {
            completion(.failure(APIError.noApiService("No valid API service configuration")))
            return
        }
        
        messageManager.sendMessage(message, in: chat, contextSize: contextSize) { [weak self] result in
            Task { @MainActor in
                switch result {
                case .success:
                    completion(.success(()))
                    self?.reloadMessages()
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        }
    }

    @MainActor
    func sendMessageStream(_ message: String, contextSize: Int, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let messageManager = self.messageManager else {
            completion(.failure(APIError.noApiService("No valid API service configuration")))
            return
        }
        
        messageManager.sendMessageStream(message, in: chat, contextSize: contextSize) { [weak self] result in
            Task { @MainActor in
                switch result {
                case .success:
                    self?.chat.objectWillChange.send()
                    completion(.success(()))
                    self?.reloadMessages()
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        }
    }
    
    @MainActor
    func sendMessageStreamWithSearch(_ message: String, contextSize: Int, useWebSearch: Bool = false, completion: @escaping (Result<Void, Error>) -> Void) async {
        guard let messageManager = self.messageManager else {
            completion(.failure(APIError.noApiService("No valid API service configuration")))
            return
        }
        
        await messageManager.sendMessageStreamWithSearch(message, in: chat, contextSize: contextSize, useWebSearch: useWebSearch) { [weak self] result in
            Task { @MainActor in
                switch result {
                case .success:
                    self?.chat.objectWillChange.send()
                    completion(.success(()))
                    self?.reloadMessages()
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        }
    }
    
    @MainActor
    func sendMessageWithSearch(_ message: String, contextSize: Int, useWebSearch: Bool = false, completion: @escaping (Result<Void, Error>) -> Void) async {
        guard let messageManager = self.messageManager else {
            completion(.failure(APIError.noApiService("No valid API service configuration")))
            return
        }
        
        await messageManager.sendMessageWithSearch(
            message,
            in: chat,
            contextSize: contextSize,
            useWebSearch: useWebSearch,
            completion: { result in
                Task { @MainActor in
                    completion(result)
                    if case .success = result {
                        self.reloadMessages()
                    }
                }
            }
        )
    }
    
    func isSearchCommand(_ message: String) -> Bool {
        return messageManager?.isSearchCommand(message).isSearch ?? false
    }

    func generateChatNameIfNeeded() {
        messageManager?.generateChatNameIfNeeded(chat: chat)
    }

    func reloadMessages() {
        messages = chat.messages
    }

    var sortedMessages: [MessageEntity] {
        return self.chat.messagesArray
    }

    private func createMessageManager() -> MessageManager? {
        guard let config = self.loadCurrentAPIConfig() else {
            #if DEBUG
            WardenLog.app.debug(
                "No valid API configuration found for chat \(self.chat.id.uuidString, privacy: .public)"
            )
            #endif
            
            // Mark as failed to prevent future attempts
            messageManagerCreationFailed = true
            
            // Show error to user
            showInvalidChatAlert()
            
            return nil
        }
        
        #if DEBUG
        WardenLog.app.debug(
            "Creating new MessageManager with URL: \(config.apiUrl.absoluteString, privacy: .public) and model: \(config.model, privacy: .public)"
        )
        #endif
        
        return MessageManager(
            apiService: APIServiceFactory.createAPIService(config: config),
            viewContext: self.viewContext
        )
    }

    func recreateMessageManager() {
        #if DEBUG
        WardenLog.app.debug("Recreating MessageManager for chat \(self.chat.id.uuidString, privacy: .public)")
        #endif
        
        // Clear the failure flag to allow retry
        messageManagerCreationFailed = false
        _messageManager = createMessageManager()
        
        if let manager = _messageManager {
            setupStreamingBindings(for: manager)
        } else {
            streamingAssistantText = ""
            messageManagerCancellables.removeAll()
        }
    }

    var canSendMessage: Bool {
        // Check if we have a valid API service and can create a message manager
        guard chat.apiService != nil else {
            return false
        }
        
        // Try to ensure we have a valid message manager
        return messageManager != nil && !messageManagerCreationFailed
    }

    private func loadCurrentAPIConfig() -> APIServiceConfiguration? {
        guard let apiService = chat.apiService else {
            #if DEBUG
            WardenLog.app.debug(
                "Missing required API service configuration for chat \(self.chat.id.uuidString, privacy: .public)"
            )
            #endif
            return nil
        }

        let modelOverride = chat.gptModel.isEmpty ? nil : chat.gptModel
        return APIServiceManager.createAPIConfiguration(for: apiService, modelOverride: modelOverride)
    }

    func regenerateChatName() {
        messageManager?.generateChatNameIfNeeded(chat: chat, force: true)
    }
    
    func stopStreaming() {
        messageManager?.stopStreaming()
    }
    
    // MARK: - Invalid Chat Handling
    
    private func showInvalidChatAlert() {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Invalid Chat Configuration"
            alert.informativeText = "This chat has an invalid API configuration and cannot be used. Please delete this chat or configure a valid API service."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
    
    /// Check if this chat has a valid configuration
    var hasValidConfiguration: Bool {
        return loadCurrentAPIConfig() != nil && !messageManagerCreationFailed
    }
    
    /// Function to safely delete this chat if it's invalid
    func deleteInvalidChat() {
        viewContext.delete(chat)
        do {
            try viewContext.save()
            #if DEBUG
            WardenLog.app.info("Deleted invalid chat \(self.chat.id.uuidString, privacy: .public)")
            #endif
        } catch {
            #if DEBUG
            WardenLog.app.error("Failed to delete invalid chat: \(error.localizedDescription, privacy: .public)")
            #endif
        }
    }
}
