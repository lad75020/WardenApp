import CoreData
import Foundation
import os

class DatabasePatcher {
    static func applyPatches(context: NSManagedObjectContext) {
        addDefaultPersonasIfNeeded(context: context)
        patchPersonaOrdering(context: context)
        patchImageUploadsForAPIServices(context: context)
        migratePersonaColorsToSymbols(context: context)
        migrateOllamaToChatEndpoint(context: context)
        //resetPersonaOrdering(context: context)
    }
    
    static func addDefaultPersonasIfNeeded(context: NSManagedObjectContext, force: Bool = false) {
        let defaults = UserDefaults.standard
        if force || !defaults.bool(forKey: AppConstants.defaultPersonasFlag) {
            for (index, persona) in AppConstants.PersonaPresets.allPersonas.enumerated() {
                let newPersona = PersonaEntity(context: context)
                newPersona.name = persona.name
                newPersona.color = persona.symbol
                newPersona.systemMessage = persona.message
                newPersona.addedDate = Date()
                newPersona.temperature = persona.temperature
                newPersona.id = UUID()
                newPersona.order = Int16(index)
            }
            
            do {
                try context.save()
                defaults.set(true, forKey: AppConstants.defaultPersonasFlag)
#if DEBUG
                WardenLog.coreData.debug("Default assistants added successfully")
#endif
            }
            catch {
                WardenLog.coreData.error("Failed to add default assistants")
            }
        }
    }
    
    static func patchPersonaOrdering(context: NSManagedObjectContext) {
        let fetchRequest = NSFetchRequest<PersonaEntity>(entityName: "PersonaEntity")
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \PersonaEntity.addedDate, ascending: true)]
        
        do {
            let personas = try context.fetch(fetchRequest)
            var needsSave = false
            
            for (index, persona) in personas.enumerated() {
                if persona.order == 0 && index != 0 {
                    persona.order = Int16(index)
                    needsSave = true
                }
            }
            
            if needsSave {
                try context.save()
#if DEBUG
                WardenLog.coreData.debug("Successfully patched persona ordering")
#endif
            }
        }
        catch {
            WardenLog.coreData.error("Failed to patch persona ordering")
        }
    }
    
    static func resetPersonaOrdering(context: NSManagedObjectContext) {
        let fetchRequest = NSFetchRequest<PersonaEntity>(entityName: "PersonaEntity")
        
        do {
            let personas = try context.fetch(fetchRequest)
            for persona in personas {
                persona.order = 0
            }
            try context.save()
#if DEBUG
            WardenLog.coreData.debug("Successfully reset all persona ordering")
#endif
            
            // Re-apply the ordering patch
            patchPersonaOrdering(context: context)
        }
        catch {
            WardenLog.coreData.error("Failed to reset persona ordering")
        }
    }
    
    static func patchImageUploadsForAPIServices(context: NSManagedObjectContext) {
        let fetchRequest = NSFetchRequest<APIServiceEntity>(entityName: "APIServiceEntity")
        
        do {
            let apiServices = try context.fetch(fetchRequest)
            var needsSave = false
            
            for service in apiServices {
                if let type = service.type,
                   let config = AppConstants.defaultApiConfigurations[type],
                   service.imageUploadsAllowed == false {
                    service.imageUploadsAllowed = config.imageUploadsSupported ?? false
                    needsSave = true
#if DEBUG
                    WardenLog.coreData.debug("Enabled image upload setting for a service")
#endif
                }
            }
            
            if needsSave {
                try context.save()
#if DEBUG
                WardenLog.coreData.debug("Successfully patched image uploads for API services")
#endif
            }
        }
        catch {
            WardenLog.coreData.error("Failed to patch image upload settings")
        }
    }
    
    /// Migrate existing Ollama services from /api/generate to /api/chat endpoint
    static func migrateOllamaToChatEndpoint(context: NSManagedObjectContext) {
        let defaults = UserDefaults.standard
        let migrationKey = "OllamaChatEndpointMigration"
        
        if defaults.bool(forKey: migrationKey) {
            return
        }
        
        let fetchRequest = NSFetchRequest<APIServiceEntity>(entityName: "APIServiceEntity")
        fetchRequest.predicate = NSPredicate(format: "type == %@", "ollama")
        
        do {
            let ollamaServices = try context.fetch(fetchRequest)
            var needsSave = false
            
            for service in ollamaServices {
                if let urlString = service.url?.absoluteString, urlString.contains("/api/generate") {
                    // Replace /api/generate with /api/chat
                    let newUrlString = urlString.replacingOccurrences(of: "/api/generate", with: "/api/chat")
                    if let newUrl = URL(string: newUrlString) {
                        service.url = newUrl
                        needsSave = true
#if DEBUG
                        WardenLog.coreData.debug("Migrated Ollama service endpoint")
#endif
                    }
                }
            }
            
            if needsSave {
                try context.save()
#if DEBUG
                WardenLog.coreData.debug("Successfully migrated Ollama services to /api/chat endpoint")
#endif
            }
            
            defaults.set(true, forKey: migrationKey)
        } catch {
            WardenLog.coreData.error("Failed to migrate Ollama service endpoints")
        }
    }
    
    static func migrateExistingConfiguration(context: NSManagedObjectContext) {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: "APIServiceMigrationCompleted") {
            return
        }
        
        let apiUrl = defaults.string(forKey: "apiUrl") ?? AppConstants.apiUrlChatCompletions
        let gptModel = defaults.string(forKey: "gptModel") ?? AppConstants.chatGptDefaultModel
        let useStream = defaults.bool(forKey: "useStream")
        let useChatGptForNames = defaults.bool(forKey: "useChatGptForNames")
        
        var type = "chatgpt"
        var name = "Chat GPT"
        var chatContext = defaults.double(forKey: "chatContext")
        
        if apiUrl.contains(":11434/api/chat") {
            type = "ollama"
            name = "Ollama"
        }
        
        if chatContext < 5 {
            chatContext = AppConstants.chatGptContextSize
        }
        
        guard let url = URL(string: apiUrl) else {
            WardenLog.coreData.error("Migrated API configuration has an invalid URL")
            defaults.set(true, forKey: "APIServiceMigrationCompleted")
            return
        }
        
        let serviceRequest = NSFetchRequest<APIServiceEntity>(entityName: "APIServiceEntity")
        serviceRequest.predicate = NSPredicate(
            format: "name == %@ AND type == %@ AND url == %@ AND model == %@",
            name, type, url as CVarArg, gptModel
        )

        let apiService: APIServiceEntity
        do {
            if let existingService = try context.fetch(serviceRequest).first {
                apiService = existingService
            } else {
                apiService = APIServiceEntity(context: context)
                apiService.id = UUID()
                apiService.name = name
                apiService.type = type
                apiService.url = url
                apiService.model = gptModel
                apiService.contextSize = chatContext.toInt16() ?? 15
                apiService.useStreamResponse = useStream
                apiService.generateChatNames = useChatGptForNames
                apiService.tokenIdentifier = UUID().uuidString
                try context.save()
            }
        } catch {
            context.rollback()
            WardenLog.coreData.error("Failed to prepare migrated API configuration")
            return
        }
        
        if let token = defaults.string(forKey: "gptToken") {
            if token != "", let apiServiceId = apiService.id {
                try? TokenManager.setToken(token, for: apiServiceId.uuidString)
                defaults.set("", forKey: "gptToken")
#if DEBUG
                WardenLog.app.debug("Migrated legacy token to Keychain")
#endif
            }
        }
        
        // Set Default Assistant as the default for default API service
        let personaFetchRequest = NSFetchRequest<PersonaEntity>(entityName: "PersonaEntity")
        personaFetchRequest.predicate = NSPredicate(format: "name == %@", "Default Assistant")
        
        do {
            let defaultPersonas = try context.fetch(personaFetchRequest)
            if let defaultPersona = defaultPersonas.first {
#if DEBUG
                WardenLog.coreData.debug(
                    "Found default assistant persona: \(defaultPersona.name ?? "", privacy: .public)"
                )
#endif
                apiService.defaultPersona = defaultPersona
                try context.save()
#if DEBUG
                WardenLog.coreData.debug("Successfully set default assistant for API service")
#endif
            }
            else {
#if DEBUG
                WardenLog.coreData.debug("Default Assistant persona not found")
#endif
            }
        }
        catch {
            WardenLog.coreData.error("Failed to set migrated default assistant")
        }
        
        defaults.set(apiService.objectID.uriRepresentation().absoluteString, forKey: "defaultApiService")
        
        // Migration completed
        defaults.set(true, forKey: "APIServiceMigrationCompleted")
    }
    
    static func migratePersonaColorsToSymbols(context: NSManagedObjectContext) {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: "PersonaSymbolMigrationCompleted") {
            return
        }
        
        let fetchRequest = NSFetchRequest<PersonaEntity>(entityName: "PersonaEntity")
        
        do {
            let personas = try context.fetch(fetchRequest)
            var needsSave = false
            
            // Color to symbol mapping for existing personas
            let colorToSymbolMap: [String: String] = [
                "#FF4444": "person.circle",
                "#FF8800": "pencil.and.outline",
                "#FFCC00": "lightbulb",
                "#33CC33": "book.circle",
                "#3399FF": "chart.line.uptrend.xyaxis",
                "#6633FF": "brain.head.profile",
                "#CC33FF": "arrow.down.circle",
                "#FF3399": "laptopcomputer",
                "#AA6600": "target",
                "#007AFF": "person.circle", // Default color
                "#FF0000": "person.circle"  // Preview color
            ]
            
            for persona in personas {
                if let color = persona.color, color.hasPrefix("#") {
                    // This is a hex color, convert to symbol
                    let symbol = colorToSymbolMap[color] ?? "person.circle"
                    persona.color = symbol
                    needsSave = true
#if DEBUG
                    WardenLog.coreData.debug("Migrated a persona color setting")
#endif
                }
            }
            
            if needsSave {
                try context.save()
#if DEBUG
                WardenLog.coreData.debug("Successfully migrated persona colors to symbols")
#endif
            }
            
            defaults.set(true, forKey: "PersonaSymbolMigrationCompleted")
        }
        catch {
            WardenLog.coreData.error("Failed to migrate persona color settings")
        }
    }
}
