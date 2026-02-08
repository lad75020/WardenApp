import Foundation
import CoreData

/// Global manager for caching AI models across all providers
/// Fetches models once per app start to improve performance and reduce API calls
@MainActor
final class ModelCacheManager: ObservableObject {
    static let shared = ModelCacheManager()
    
    @Published private(set) var cachedModels: [String: [AIModel]] = [:]
    @Published private(set) var loadingStates: [String: Bool] = [:]
    @Published private(set) var fetchErrors: [String: String] = [:]
    
    private var lastFetchedAPIKeys: [String: String] = [:]
    private let favoriteManager = FavoriteModelsManager.shared
    
    private init() {}
    
    /// Get all models across all providers, sorted by favorites first, then provider/model
    /// Only shows selected models and favorites, not all available models
    var allModels: [(provider: String, model: AIModel)] {
        let selectedModelsManager = SelectedModelsManager.shared
        var result: [(provider: String, model: AIModel)] = []
        
        for (providerType, models) in cachedModels {
            if selectedModelsManager.hasCustomSelection(for: providerType) {
                let selectedModelIds = selectedModelsManager.getSelectedModelIds(for: providerType)
                let filteredModels = models.filter { model in
                    let isFavorite = favoriteManager.isFavorite(provider: providerType, model: model.id)
                    let isSelected = selectedModelIds.contains(model.id)
                    return isFavorite || isSelected
                }
                for model in filteredModels {
                    result.append((provider: providerType, model: model))
                }
            } else {
                // No custom selection => include all models
                for model in models {
                    result.append((provider: providerType, model: model))
                }
            }
        }
        
        // Sort by favorites first, then by provider name, then by model name
        return result.sorted { first, second in
            let firstIsFavorite = favoriteManager.isFavorite(provider: first.provider, model: first.model.id)
            let secondIsFavorite = favoriteManager.isFavorite(provider: second.provider, model: second.model.id)
            
            // Favorites come first
            if firstIsFavorite != secondIsFavorite {
                return firstIsFavorite
            }
            
            // If both are favorites or both are not, sort by provider then model
            if first.provider != second.provider {
                let firstProviderName = AppConstants.defaultApiConfigurations[first.provider]?.name ?? first.provider
                let secondProviderName = AppConstants.defaultApiConfigurations[second.provider]?.name ?? second.provider
                return firstProviderName < secondProviderName
            }
            return first.model.id < second.model.id
        }
    }
    
    /// Get only favorite models across all providers
    var favoriteModels: [(provider: String, model: AIModel)] {
        return allModels.filter { item in
            favoriteManager.isFavorite(provider: item.provider, model: item.model.id)
        }
    }
    
    /// Get models for a specific provider
    func getModels(for providerType: String) -> [AIModel] {
        // Return cached models if available
        if let cached = cachedModels[providerType], !cached.isEmpty {
            return cached
        }
        
        // Fall back to static models for providers that don't support fetching
        let config = AppConstants.defaultApiConfigurations[providerType]
        if config?.modelsFetching == false {
            return config?.models.map { AIModel(id: $0) } ?? []
        }
        
        return []
    }
    
    /// Get models for a specific provider, sorted with favorites first
    /// Only shows selected models and favorites, not all available models
    func getModelsSorted(for providerType: String) -> [AIModel] {
        let allModels = getModels(for: providerType)
        let selectedModelsManager = SelectedModelsManager.shared
        let hasCustom = selectedModelsManager.hasCustomSelection(for: providerType)
        let selectedModelIds = selectedModelsManager.getSelectedModelIds(for: providerType)
        
        let baseModels: [AIModel]
        if hasCustom {
            baseModels = allModels.filter { model in
                let isFavorite = favoriteManager.isFavorite(provider: providerType, model: model.id)
                let isSelected = selectedModelIds.contains(model.id)
                return isFavorite || isSelected
            }
        } else {
            baseModels = allModels
        }
        
        return baseModels.sorted { first, second in
            let firstIsFavorite = favoriteManager.isFavorite(provider: providerType, model: first.id)
            let secondIsFavorite = favoriteManager.isFavorite(provider: providerType, model: second.id)
            if firstIsFavorite != secondIsFavorite {
                return firstIsFavorite
            }
            return first.id < second.id
        }
    }
    
    /// Check if models are currently loading for a provider
    func isLoading(for providerType: String) -> Bool {
        return loadingStates[providerType] ?? false
    }
    
    /// Get error message for a provider if any
    func getError(for providerType: String) -> String? {
        return fetchErrors[providerType]
    }
    
    /// Fetch models for all configured providers
    func fetchAllModels(from apiServices: [APIServiceEntity]) {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.fetchAllModels(from: apiServices)
            }
            return
        }
        let providerTypes = Set(apiServices.compactMap { $0.type })
        
        for providerType in providerTypes {
            self.fetchModels(for: providerType, from: apiServices)
        }
    }
    
    /// Fetch models for a specific provider
    func fetchModels(for providerType: String, from apiServices: [APIServiceEntity]) {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.fetchModels(for: providerType, from: apiServices)
            }
            return
        }
        guard let service = getServiceForProvider(providerType, from: apiServices) else { return }
        guard let config = AppConstants.defaultApiConfigurations[providerType] else { return }
        
        // Special handling for purely local providers where the "model" is user-defined per service.
        // For these, populate the model list from the saved services instead of static config.
        if providerType.lowercased() == "coreml" || providerType.lowercased() == "coreml llm" {
            let models = apiServices
                .filter { ($0.type ?? "").lowercased() == providerType.lowercased() }
                .compactMap { $0.model?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .map { AIModel(id: $0) }

            cachedModels[providerType] = models
            return
        }

        // Don't fetch if provider doesn't support it
        guard config.modelsFetching != false else {
            // For providers that don't support fetching, use static models
            cachedModels[providerType] = config.models.map { AIModel(id: $0) }
            return
        }
        
        // Special handling for HuggingFace - doesn't require API key
        if providerType.lowercased() == "huggingface" {
            loadingStates[providerType] = true
            fetchErrors[providerType] = nil
            
            Task { [weak self] in
                guard let self else { return }
                do {
                    // Create HuggingFace service to fetch models
                    let huggingFaceService = HuggingFaceService(model: config.defaultModel)
                    let models = try await huggingFaceService.fetchModels()

                    await MainActor.run {
                        self.cachedModels[providerType] = models
                        self.loadingStates[providerType] = false
                        self.fetchErrors[providerType] = nil
                        
                        #if DEBUG
                        WardenLog.app.debug("HuggingFace models cached: \(models.count) models")
                        #endif
                    }

                    // Trigger metadata fetching for HuggingFace
                    await self.triggerMetadataFetch(for: providerType, apiKey: "")
                } catch {
                    await MainActor.run {
                        self.loadingStates[providerType] = false
                        self.fetchErrors[providerType] = error.localizedDescription

                        // Fall back to static models if fetching fails
                        if let staticModels = AppConstants.defaultApiConfigurations[providerType]?.models {
                            self.cachedModels[providerType] = staticModels.map { AIModel(id: $0) }
                        }
                        
                        #if DEBUG
                        WardenLog.app.error("Failed to fetch HuggingFace models: \(error.localizedDescription)")
                        #endif
                    }
                }
            }
            return
        }
        
        // Get current API key
        let currentAPIKey = (try? TokenManager.getToken(for: service.id?.uuidString ?? "")) ?? ""
        
        // Check if we need to fetch:
        // 1. Never fetched before
        // 2. API key changed
        // 3. Currently loading
        let shouldFetch = cachedModels[providerType] == nil ||
                         lastFetchedAPIKeys[providerType] != currentAPIKey
        
        guard shouldFetch else { return }
        guard loadingStates[providerType] != true else { return }
        
        loadingStates[providerType] = true
        fetchErrors[providerType] = nil
        
        // Create API service configuration
        guard let serviceUrl = service.url else {
            loadingStates[providerType] = false
            return
        }
        
        let apiConfig = APIServiceConfig(
            name: providerType,
            apiUrl: serviceUrl,
            apiKey: currentAPIKey,
            model: ""
        )
        
        let apiService = APIServiceFactory.createAPIService(config: apiConfig)
        
        Task { [weak self] in
            guard let self else { return }
            do {
                let models = try await apiService.fetchModels()

                await MainActor.run {
                    self.cachedModels[providerType] = models
                    self.lastFetchedAPIKeys[providerType] = currentAPIKey
                    self.loadingStates[providerType] = false
                    self.fetchErrors[providerType] = nil
                }

                // Trigger metadata fetching for this provider now that we have models
                await self.triggerMetadataFetch(for: providerType, apiKey: currentAPIKey)
            } catch {
                await MainActor.run {
                    self.loadingStates[providerType] = false
                    self.fetchErrors[providerType] = error.localizedDescription

                    // Fall back to static models if fetching fails
                    if let staticModels = AppConstants.defaultApiConfigurations[providerType]?.models {
                        self.cachedModels[providerType] = staticModels.map { AIModel(id: $0) }
                        self.lastFetchedAPIKeys[providerType] = currentAPIKey
                    }
                }
            }
        }
    }
    
    /// Force refresh models for a specific provider
    func refreshModels(for providerType: String, from apiServices: [APIServiceEntity]) {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.refreshModels(for: providerType, from: apiServices)
            }
            return
        }
        cachedModels[providerType] = nil
        lastFetchedAPIKeys[providerType] = nil
        fetchModels(for: providerType, from: apiServices)
    }
    
    /// Clear all cached models
    func clearCache() {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.clearCache()
            }
            return
        }
        cachedModels.removeAll()
        lastFetchedAPIKeys.removeAll()
        loadingStates.removeAll()
        fetchErrors.removeAll()
    }
    
    // MARK: - Private Helpers
    
    private func getServiceForProvider(_ providerType: String, from apiServices: [APIServiceEntity]) -> APIServiceEntity? {
        return apiServices.first { service in
            service.type == providerType && hasValidToken(for: service)
        }
    }
    
    private func hasValidToken(for service: APIServiceEntity) -> Bool {
        // HuggingFace doesn't require an API token
        if let type = service.type?.lowercased(), type == "huggingface" {
            return true
        }
        
        if let type = service.type?.lowercased(), type == "ollama" || type == "lmstudio" {
            return true
        }
        guard let serviceId = service.id?.uuidString else { return false }
        do {
            let token = try TokenManager.getToken(for: serviceId)
            return token?.isEmpty == false
        } catch {
            return false
        }
    }
    
    /// Trigger metadata fetching for a provider
    /// This is called after models are successfully fetched to ensure metadata is available
    private func triggerMetadataFetch(for providerType: String, apiKey: String) async {
        await ModelMetadataCache.shared.fetchMetadataIfNeeded(provider: providerType, apiKey: apiKey)
    }
} 

