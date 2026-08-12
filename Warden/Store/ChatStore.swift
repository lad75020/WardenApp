import CoreData
import Foundation
import SwiftUI
import os

let migrationKey = "com.example.chatApp.migrationFromJSONCompleted"

/// A derived, non-persisted state for a chat's current service relationship.
/// It deliberately contains no service credentials or chat content.
enum ChatServiceAvailability: Equatable {
    case available
    case missingService
    case invalidService

    var isAvailable: Bool {
        self == .available
    }

    var recoverySummary: String {
        switch self {
        case .available:
            return "Service available"
        case .missingService:
            return "This chat is unavailable because its service is no longer configured."
        case .invalidService:
            return "This chat is unavailable because its service configuration needs attention."
        }
    }
}

enum ChatRecoveryError: LocalizedError {
    case chatIsAlreadyAvailable
    case serviceIsNotAValidRepairCandidate
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .chatIsAlreadyAvailable:
            return "This chat is already available."
        case .serviceIsNotAValidRepairCandidate:
            return "The selected service is no longer available for repair."
        case .saveFailed:
            return "The repair could not be saved. Your chat history is unchanged."
        }
    }
}

@MainActor
final class ChatStore: ObservableObject {
    let persistenceController: PersistenceController
    let viewContext: NSManagedObjectContext
    private let persistenceSave: (NSManagedObjectContext) throws -> Void

    init(
        persistenceController: PersistenceController,
        persistenceSave: @escaping (NSManagedObjectContext) throws -> Void = { try $0.save() }
    ) {
        self.persistenceController = persistenceController
        self.viewContext = persistenceController.container.viewContext
        self.persistenceSave = persistenceSave

        migrateFromJSONIfNeeded()
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(contextDidSave(_:)),
            name: .NSManagedObjectContextDidSave,
            object: viewContext
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Helper Methods
    
    /// Configure optimized fetch request with batch loading and fault handling
    private func configureOptimizedFetchRequest<T: NSFetchRequestResult>(
        _ request: NSFetchRequest<T>,
        batchSize: Int = 50
    ) {
        request.fetchBatchSize = batchSize
        request.returnsObjectsAsFaults = true
    }
    
    /// Fetch entities with common optimizations
    private func fetchEntities<T: NSFetchRequestResult>(
        entityName: String,
        predicate: NSPredicate? = nil,
        sortDescriptors: [NSSortDescriptor] = [],
        limit: Int? = nil,
        offset: Int? = nil
    ) -> [T] {
        let fetchRequest = NSFetchRequest<T>(entityName: entityName)
        fetchRequest.predicate = predicate
        fetchRequest.sortDescriptors = sortDescriptors.isEmpty ? nil : sortDescriptors
        if let limit = limit { fetchRequest.fetchLimit = limit }
        if let offset = offset { fetchRequest.fetchOffset = offset }
        configureOptimizedFetchRequest(fetchRequest)
        
        do {
            return try viewContext.fetch(fetchRequest)
        } catch {
            WardenLog.coreData.error(
                "Error fetching \(entityName, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            return []
        }
    }
    
    /// Count entities without loading
    private func countEntities(
        entityName: String,
        predicate: NSPredicate? = nil
    ) -> Int {
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: entityName)
        fetchRequest.predicate = predicate
        fetchRequest.resultType = .countResultType
        
        do {
            return try viewContext.count(for: fetchRequest)
        } catch {
            WardenLog.coreData.error(
                "Error counting \(entityName, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            return 0
        }
    }
    
    /// Show error alert to user
    private func showAlert(title: String, message: String) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = message
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }

    func saveInCoreData() {
        viewContext.performSaveWithRetry(attempts: 3)
    }

    func loadFromCoreData() async -> Result<[ChatBackup], Error> {
        let fetchRequest = NSFetchRequest<ChatEntity>(entityName: "ChatEntity")
        fetchRequest.sortDescriptors = [
            NSSortDescriptor(keyPath: \ChatEntity.updatedDate, ascending: false),
            NSSortDescriptor(keyPath: \ChatEntity.createdDate, ascending: false)
        ]

        do {
            let chatEntities = try viewContext.fetch(fetchRequest)

            // Availability is derived. Loading must never delete retained history.
            let sortedChats = chatEntities.sorted {
                if $0.updatedDate != $1.updatedDate {
                    return $0.updatedDate > $1.updatedDate
                }
                if $0.createdDate != $1.createdDate {
                    return $0.createdDate > $1.createdDate
                }
                return $0.id.uuidString < $1.id.uuidString
            }
            return .success(sortedChats.map(ChatBackup.init))
        } catch {
            return .failure(error)
        }
    }

    // MARK: - Retained chat recovery

    func availability(for chat: ChatEntity) -> ChatServiceAvailability {
        guard let service = chat.apiService else {
            return .missingService
        }
        return APIServiceManager.createAPIConfiguration(for: service) == nil ? .invalidService : .available
    }

    func validRepairCandidates() -> [APIServiceEntity] {
        let request = NSFetchRequest<APIServiceEntity>(entityName: "APIServiceEntity")
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \APIServiceEntity.addedDate, ascending: false),
            NSSortDescriptor(keyPath: \APIServiceEntity.name, ascending: true)
        ]

        do {
            return try viewContext.fetch(request).filter {
                APIServiceManager.createAPIConfiguration(for: $0) != nil
            }.sorted { ($0.id?.uuidString ?? "") < ($1.id?.uuidString ?? "") }
        } catch {
            // Fetch errors are intentionally not surfaced with raw Core Data details.
            return []
        }
    }

    /// Explicitly remaps an unavailable chat. No chat content or relationships other than
    /// `apiService` are changed by this operation.
    func repairUnavailableChat(_ chat: ChatEntity, with service: APIServiceEntity) throws {
        guard !availability(for: chat).isAvailable else {
            throw ChatRecoveryError.chatIsAlreadyAvailable
        }
        guard validRepairCandidates().contains(where: { $0.objectID == service.objectID }) else {
            throw ChatRecoveryError.serviceIsNotAValidRepairCandidate
        }

        let previousService = chat.apiService
        chat.apiService = service
        do {
            try viewContext.save()
        } catch {
            chat.apiService = previousService
            viewContext.rollback()
            throw ChatRecoveryError.saveFailed
        }
    }

    /// Deletes a retained unavailable chat only after a user-facing confirmation.
    /// Callers must clear any selected-chat reference before invoking this method.
    func deleteUnavailableChat(_ chat: ChatEntity) throws {
        guard !availability(for: chat).isAvailable else {
            throw ChatRecoveryError.chatIsAlreadyAvailable
        }

        UserDefaults.standard.removeObject(forKey: TavilyConfig.disclosureAcknowledgedKey(for: chat.id))
        viewContext.delete(chat)
        do {
            try viewContext.save()
        } catch {
            viewContext.rollback()
            throw ChatRecoveryError.saveFailed
        }
    }

    func saveToCoreData(chats: [ChatBackup]) async -> Result<Int, Error> {
        do {
            let defaultApiService = getDefaultAPIService()
            var importedIDs = Set<UUID>()
            var importedCount = 0

            for oldChat in chats {
                // A legacy export can contain the same chat more than once. Keep
                // the first record deterministically and never duplicate it.
                guard importedIDs.insert(oldChat.id).inserted else { continue }
                let existingChats: [ChatEntity] = fetchEntities(
                    entityName: "ChatEntity",
                    predicate: NSPredicate(format: "id == %@", oldChat.id as CVarArg)
                )

                guard existingChats.isEmpty else { continue }

                let chatEntity = ChatEntity(context: viewContext)
                chatEntity.id = oldChat.id
                chatEntity.newChat = oldChat.newChat
                chatEntity.temperature = oldChat.temperature ?? 0.0
                chatEntity.top_p = oldChat.top_p ?? 0.0
                chatEntity.behavior = oldChat.behavior
                chatEntity.newMessage = oldChat.newMessage ?? ""
                chatEntity.createdDate = Date()
                chatEntity.updatedDate = Date()
                chatEntity.requestMessages = oldChat.requestMessages
                chatEntity.gptModel = oldChat.gptModel ?? AppConstants.chatGptDefaultModel
                chatEntity.name = oldChat.name ?? ""

                attachAPIService(to: chatEntity, from: oldChat, default: defaultApiService)
                attachPersona(to: chatEntity, name: oldChat.personaName)
                addMessages(to: chatEntity, from: oldChat.messages)
                importedCount += 1
            }

            if viewContext.hasChanges {
                try persistenceSave(viewContext)
            }
            return .success(importedCount)
        } catch {
            // A failed import must not leave partially inserted legacy records in
            // the caller's context. The source JSON and migration flag are retained.
            viewContext.rollback()
            return .failure(error)
        }
    }
    
    private func getDefaultAPIService() -> APIServiceEntity? {
        guard let defaultServiceIDString = UserDefaults.standard.string(forKey: "defaultApiService"),
              let url = URL(string: defaultServiceIDString),
              let objectID = self.viewContext.persistentStoreCoordinator?.managedObjectID(forURIRepresentation: url)
        else { return nil }
        
        return try? self.viewContext.existingObject(with: objectID) as? APIServiceEntity
    }
    
    private func attachAPIService(to chat: ChatEntity, from oldChat: ChatBackup, default defaultService: APIServiceEntity?) {
        guard let apiServiceName = oldChat.apiServiceName, let apiServiceType = oldChat.apiServiceType else {
            chat.apiService = defaultService
            return
        }
        
        let services: [APIServiceEntity] = fetchEntities(
            entityName: "APIServiceEntity",
            predicate: NSPredicate(format: "name == %@ AND type == %@", apiServiceName, apiServiceType),
            limit: 1
        )
        
        // A legacy record that names a service must remain unavailable when that exact
        // service no longer exists. Falling back would silently change provider context.
        chat.apiService = services.first
    }
    
    private func attachPersona(to chat: ChatEntity, name: String?) {
        guard let personaName = name else { return }
        
        let personas: [PersonaEntity] = fetchEntities(
            entityName: "PersonaEntity",
            predicate: NSPredicate(format: "name == %@", personaName),
            limit: 1
        )
        
        chat.persona = personas.first
    }
    
    private func addMessages(to chat: ChatEntity, from messages: [MessageBackup]) {
        for oldMessage in messages {
            let messageEntity = MessageEntity(context: self.viewContext)
            messageEntity.id = Int64(oldMessage.id)
            messageEntity.name = oldMessage.name
            messageEntity.body = oldMessage.body
            messageEntity.timestamp = oldMessage.timestamp
            messageEntity.own = oldMessage.own
            messageEntity.waitingForResponse = oldMessage.waitingForResponse ?? false
            messageEntity.chat = chat
            chat.addToMessages(messageEntity)
        }
    }

    func deleteAllChats() {
        deleteEntities(ChatEntity.self, predicate: nil)
    }

    func deleteSelectedChats(_ chatIDs: Set<UUID>) {
        guard !chatIDs.isEmpty else { return }
        deleteEntities(ChatEntity.self, predicate: NSPredicate(format: "id IN %@", chatIDs))
    }

    func deleteAllPersonas() {
        deleteEntities(PersonaEntity.self)
    }

    func deleteAllAPIServices() {
        viewContext.perform {
            let services: [APIServiceEntity] = self.fetchEntities(entityName: "APIServiceEntity")
            for service in services {
                if let tokenId = service.tokenIdentifier {
                    try? TokenManager.deleteToken(for: tokenId)
                }
                self.viewContext.delete(service)
            }
            self.saveContext()
        }
    }
    
    private func deleteEntities<T: NSManagedObject>(
        _ type: T.Type,
        predicate: NSPredicate? = nil,
        onDelete: ((T) -> Void)? = nil
    ) {
        viewContext.perform {
            let fetchRequest = NSFetchRequest<T>(entityName: T.entity().name ?? "")
            fetchRequest.predicate = predicate
            
            do {
                let entities: [T] = try self.viewContext.fetch(fetchRequest)
                for entity in entities {
                    onDelete?(entity)
                    if let chat = entity as? ChatEntity {
                        UserDefaults.standard.removeObject(forKey: TavilyConfig.disclosureAcknowledgedKey(for: chat.id))
                    }
                    self.viewContext.delete(entity)
                }
                self.saveContext()
            } catch {
                WardenLog.coreData.error("Error deleting \(String(describing: T.self), privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }
    
    private func saveContext() {
        DispatchQueue.main.async {
            do {
                try self.viewContext.save()
            } catch {
                WardenLog.coreData.error("Error saving context: \(error.localizedDescription, privacy: .public)")
                self.viewContext.rollback()
            }
        }
    }

    private static func fileURL() throws -> URL {
        try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ).appendingPathComponent("chats.data")
    }

    private func migrateFromJSONIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: migrationKey) else { return }

        Task { [weak self] in
            do {
                let fileURL = try ChatStore.fileURL()
                let data = try await Task.detached(priority: .utility) {
                    try Data(contentsOf: fileURL)
                }.value
                let oldChats = try await Task.detached(priority: .utility) {
                    try JSONDecoder().decode([ChatBackup].self, from: data)
                }.value

                guard let self else { return }
                let result = await saveToCoreData(chats: oldChats)
                if case .failure(let error) = result {
                    WardenLog.coreData.error("Legacy chat migration save failed")
                    self.showAlert(title: "Migration Error",
                                   message: "Your existing chats could not be migrated. They have not been removed.")
                    return
                }

                #if DEBUG
                WardenLog.coreData.debug("Migration from JSON successful")
                #endif
                UserDefaults.standard.set(true, forKey: migrationKey)
                try? FileManager.default.removeItem(at: fileURL)
            } catch {
                if (error as NSError).code == NSFileReadNoSuchFileError {
                    UserDefaults.standard.set(true, forKey: migrationKey)
                } else {
                    WardenLog.coreData.error("Legacy chat migration could not be completed")
                }
            }
        }
    }

    // MARK: - Project Management Methods
    
    func createProject(name: String, description: String? = nil, colorCode: String = "#007AFF", customInstructions: String? = nil) -> ProjectEntity {
        let project = ProjectEntity(context: viewContext)
        project.id = UUID()
        project.name = name
        project.projectDescription = description
        project.colorCode = colorCode
        project.customInstructions = customInstructions
        project.createdAt = Date()
        project.updatedAt = Date()
        project.isArchived = false
        project.sortOrder = getNextProjectSortOrder()
        
        saveInCoreData()
        return project
    }
    
    func updateProject(_ project: ProjectEntity, name: String? = nil, description: String? = nil, colorCode: String? = nil, customInstructions: String? = nil) {
        if let name = name {
            project.name = name
        }
        if let description = description {
            project.projectDescription = description
        }
        if let colorCode = colorCode {
            project.colorCode = colorCode
        }
        if let customInstructions = customInstructions {
            project.customInstructions = customInstructions
        }
        project.updatedAt = Date()
        
        saveInCoreData()
    }
    
    func deleteProject(_ project: ProjectEntity) {
        // Remove project relationship from all chats in this project
        if let chats = project.chats?.allObjects as? [ChatEntity] {
            for chat in chats {
                chat.project = nil
            }
        }
        
        viewContext.delete(project)
        saveInCoreData()
    }
    
    func moveChatsToProject(_ project: ProjectEntity?, chats: [ChatEntity]) {
        for chat in chats {
            chat.project = project
            chat.updatedDate = Date()
        }
        
        if let project = project {
            project.updatedAt = Date()
        }
        
        saveInCoreData()
    }
    
    func removeChatFromProject(_ chat: ChatEntity) {
        let oldProject = chat.project
        chat.project = nil
        chat.updatedDate = Date()
        
        if let project = oldProject {
            project.updatedAt = Date()
        }
        
        saveInCoreData()
    }
    
    // Regenerate titles for all chats in a project
    func regenerateChatTitlesInProject(_ project: ProjectEntity) {
        guard let chats = project.chats?.allObjects as? [ChatEntity], !chats.isEmpty else { return }
        
        // Find a suitable API service for title generation
        let apiServiceFetch = NSFetchRequest<APIServiceEntity>(entityName: "APIServiceEntity")
        apiServiceFetch.fetchLimit = 1
        
        do {
            guard let apiServiceEntity = try viewContext.fetch(apiServiceFetch).first else {
                WardenLog.app.error("No API service available for title regeneration")
                showError(message: "No API service configured. Please add an API service in Settings.")
                return
            }
            
            // Verify the API configuration is valid before proceeding
            guard let apiConfig = APIServiceManager.createAPIConfiguration(for: apiServiceEntity) else {
                WardenLog.app.error("Failed to create API configuration for title regeneration")
                showError(message: "Failed to create API configuration. Please check your API service settings (URL, API Key).")
                return
            }
            
            // Create API service from config
            let apiService = APIServiceFactory.createAPIService(config: apiConfig)
            
            // Create a message manager for title generation
            let messageManager = MessageManager(
                apiService: apiService,
                viewContext: viewContext
            )
            
            // Regenerate titles for each chat
            var successCount = 0
            for chat in chats {
                if !chat.messagesArray.isEmpty {
                    messageManager.generateChatNameIfNeeded(chat: chat, force: true)
                    successCount += 1
                }
            }
            #if DEBUG
            WardenLog.app.debug("Started title regeneration for \(successCount, privacy: .public) chat(s)")
            #endif
            
        } catch {
            WardenLog.app.error(
                "Error fetching API service for title regeneration: \(error.localizedDescription, privacy: .public)"
            )
            showError(message: "Failed to regenerate titles: \(error.localizedDescription)")
        }
    }
    
    // Helper method to show errors to user
    private func showError(message: String) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Title Regeneration Failed"
            alert.informativeText = message
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
    
    // MARK: - Project Management Queries
    
    private let defaultProjectSortDescriptors = [
        NSSortDescriptor(keyPath: \ProjectEntity.isArchived, ascending: true),
        NSSortDescriptor(keyPath: \ProjectEntity.sortOrder, ascending: true),
        NSSortDescriptor(keyPath: \ProjectEntity.createdAt, ascending: false)
    ]
    
    func getAllProjects() -> [ProjectEntity] {
        fetchEntities(
            entityName: "ProjectEntity",
            sortDescriptors: defaultProjectSortDescriptors
        )
    }
    
    func getActiveProjects() -> [ProjectEntity] {
        fetchEntities(
            entityName: "ProjectEntity",
            predicate: NSPredicate(format: "isArchived == %@", NSNumber(value: false)),
            sortDescriptors: Array(defaultProjectSortDescriptors.dropFirst())
        )
    }
    
    func getProjectsPaginated(limit: Int = 50, offset: Int = 0, includeArchived: Bool = false) -> [ProjectEntity] {
        let predicate = includeArchived ? nil : NSPredicate(format: "isArchived == %@", NSNumber(value: false))
        return fetchEntities(
            entityName: "ProjectEntity",
            predicate: predicate,
            sortDescriptors: defaultProjectSortDescriptors,
            limit: limit,
            offset: offset
        )
    }
    
    // MARK: - Chat Query Methods
    
    private let defaultChatSortDescriptors = [
        NSSortDescriptor(keyPath: \ChatEntity.isPinned, ascending: false),
        NSSortDescriptor(keyPath: \ChatEntity.updatedDate, ascending: false)
    ]
    
    func getChatsInProject(_ project: ProjectEntity) -> [ChatEntity] {
        fetchEntities(
            entityName: "ChatEntity",
            predicate: NSPredicate(format: "project == %@", project),
            sortDescriptors: defaultChatSortDescriptors
        )
    }
    
    func getChatsWithoutProject() -> [ChatEntity] {
        fetchEntities(
            entityName: "ChatEntity",
            predicate: NSPredicate(format: "project == nil"),
            sortDescriptors: defaultChatSortDescriptors
        )
    }
    
    func getAllChats() -> [ChatEntity] {
        fetchEntities(entityName: "ChatEntity", sortDescriptors: defaultChatSortDescriptors)
    }
    
    func getChatsPaginated(limit: Int = 50, offset: Int = 0, projectId: UUID? = nil) -> [ChatEntity] {
        let predicate = projectId.map { NSPredicate(format: "project.id == %@", $0 as CVarArg) }
        return fetchEntities(
            entityName: "ChatEntity",
            predicate: predicate,
            sortDescriptors: defaultChatSortDescriptors,
            limit: limit,
            offset: offset
        )
    }
    
    func countChats(projectId: UUID? = nil) -> Int {
        let predicate = projectId.map { NSPredicate(format: "project.id == %@", $0 as CVarArg) }
        return countEntities(entityName: "ChatEntity", predicate: predicate)
    }
    
    func setProjectArchived(_ project: ProjectEntity, archived: Bool) {
        project.isArchived = archived
        project.updatedAt = Date()
        saveInCoreData()
    }
    
    private func getNextProjectSortOrder() -> Int32 {
        let fetchRequest = ProjectEntity.fetchRequest()
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \ProjectEntity.sortOrder, ascending: false)]
        fetchRequest.fetchLimit = 1
        
        do {
            let projects = try viewContext.fetch(fetchRequest)
            if let lastProject = projects.first {
                return lastProject.sortOrder + 1
            }
        } catch {
            WardenLog.coreData.error("Error getting next sort order: \(error.localizedDescription, privacy: .public)")
        }
        
        return 0
    }

    @objc private func contextDidSave(_ notification: Notification) {
        // No longer needed after Spotlight removal
    }
    
    // MARK: - Performance Optimization Methods
    
    // MARK: - Performance Optimization Methods
    
    /// Efficiently counts chats grouped by project using a dictionary result type
    /// avoiding full relationship faults.
    func getChatCountsByProject() -> [UUID: Int] {
        let fetchRequest = NSFetchRequest<NSDictionary>(entityName: "ChatEntity")
        fetchRequest.resultType = .dictionaryResultType
        
        let countExpression = NSExpressionDescription()
        countExpression.name = "count"
        countExpression.expression = NSExpression(forFunction: "count:", arguments: [NSExpression(forKeyPath: "id")])
        countExpression.expressionResultType = .integer32AttributeType
        
        // Group by project.id
        fetchRequest.propertiesToFetch = ["project.id", countExpression]
        fetchRequest.propertiesToGroupBy = ["project.id"]
        
        do {
            let results = try viewContext.fetch(fetchRequest)
            var counts: [UUID: Int] = [:]
            
            for result in results {
                if let projectId = result["project.id"] as? UUID,
                   let count = result["count"] as? Int {
                    counts[projectId] = count
                }
            }
            return counts
        } catch {
            WardenLog.coreData.error("Error fetching chat counts: \(error.localizedDescription)")
            return [:]
        }
    }
    
    func countMessages(in project: ProjectEntity) -> Int {
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "MessageEntity")
        fetchRequest.predicate = NSPredicate(format: "chat.project == %@", project)
        fetchRequest.resultType = .countResultType
        
        do {
            return try viewContext.count(for: fetchRequest)
        } catch {
            WardenLog.coreData.error("Error counting messages in project: \(error.localizedDescription)")
            return 0
        }
    }
    
    func optimizeMemoryUsage() {
        Task.detached(priority: .background) {
            await MainActor.run {
                self.viewContext.refreshAllObjects()
            }
        }
    }
    
    func getPerformanceStats() -> (chatCount: Int, projectCount: Int, registeredObjects: Int) {
        (chatCount: countChats(), projectCount: getAllProjects().count, registeredObjects: viewContext.registeredObjects.count)
    }
    
    // MARK: - Chat Operations
    
    func createChat(in project: ProjectEntity? = nil) -> ChatEntity {
        let newChat = ChatEntity(context: viewContext)
        newChat.id = UUID()
        newChat.newChat = true
        newChat.createdDate = Date()
        newChat.updatedDate = Date()
        newChat.newMessage = ""
        newChat.name = "New Chat"
        
        // Set default values logic
        newChat.temperature = Double(AppConstants.defaultTemperatureForChat)
        newChat.top_p = 1.0
        newChat.behavior = "default"
        newChat.systemMessage = AppConstants.chatGptSystemMessage
        
        // Set Default API Service and Model
        if let defaultService = getDefaultAPIService() {
            newChat.apiService = defaultService
            if let svcModel = defaultService.model, !svcModel.isEmpty {
                newChat.gptModel = svcModel
            } else {
                newChat.gptModel = AppConstants.chatGptDefaultModel
            }
        } else {
            // Fallback if no service is found
            newChat.gptModel = AppConstants.chatGptDefaultModel
        }
        
        // Assign to project if provided
        if let project = project {
            newChat.project = project
            project.updatedAt = Date()
            
            // Apply custom instructions if available
            if let instructions = project.customInstructions, !instructions.isEmpty {
                newChat.systemMessage = instructions
            }
        }
        
        saveInCoreData()
        return newChat
    }
    
    func regenerateChatName(chat: ChatEntity) {
        guard let apiService = chat.apiService else { return }
        
        guard let apiConfig = APIServiceManager.createAPIConfiguration(for: apiService, modelOverride: chat.gptModel.isEmpty ? nil : chat.gptModel) else {
            return
        }
        
        let messageManager = MessageManager(
            apiService: APIServiceFactory.createAPIService(config: apiConfig),
            viewContext: viewContext
        )
        
        messageManager.generateChatNameIfNeeded(chat: chat, force: true)
    }
    
    // MARK: - Legacy compatibility

    /// Kept for source compatibility. Invalid service relationships are now retained and
    /// surfaced through `availability(for:)`; cleanup is deliberately non-destructive.
    func cleanupInvalidChats() {
        // No-op by design. Deletion is available only through deleteUnavailableChat(_:).
    }
}

// MARK: - Extensions for Performance

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
