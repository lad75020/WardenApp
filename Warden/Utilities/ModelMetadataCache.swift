import Foundation
import SwiftUI
import os

/// Manages metadata caching for models with freshness tracking
@MainActor
final class ModelMetadataCache: ObservableObject {
    static let shared = ModelMetadataCache()
    
    @AppStorage("modelMetadataCache") private var metadataCacheData: Data = Data()
    @Published private(set) var cachedMetadata: [String: [String: ModelMetadata]] = [:] // [provider][modelId]
    @Published private(set) var isFetching: [String: Bool] = [:]
    
    private var lastRefreshAttempt: [String: Date] = [:]
    
    private init() {
        loadFromStorage()
    }
    
    /// Upsert a single model metadata entry for a provider
    func upsertMetadata(provider: String, metadata: ModelMetadata) {
        var providerCache = cachedMetadata[provider] ?? [:]
        providerCache[metadata.modelId] = metadata
        cachedMetadata[provider] = providerCache
        saveToStorage()
    }
    
    /// Get metadata for a model, fetching if needed
    func getMetadata(provider: String, modelId: String) -> ModelMetadata? {
        return cachedMetadata[provider]?[modelId]
    }
    
    /// Get metadata for all models of a provider
    func getMetadata(for provider: String) -> [String: ModelMetadata] {
        return cachedMetadata[provider] ?? [:]
    }
    
    /// Fetch metadata for a provider if stale or missing
    func fetchMetadataIfNeeded(provider: String, apiKey: String) async {
        // Check if we're already fetching
        if isFetching[provider] == true {
            return
        }
        
        // Check if we attempted recently (avoid spam)
        if let lastAttempt = lastRefreshAttempt[provider],
           Date().timeIntervalSince(lastAttempt) < 60 {
            return
        }
        
        isFetching[provider] = true
        
        defer {
            isFetching[provider] = false
            lastRefreshAttempt[provider] = Date()
        }
        
        do {
            let fetcher = ModelMetadataFetcherFactory.createFetcher(for: provider)
            let newMetadata = try await fetcher.fetchAllMetadata(apiKey: apiKey)
            
            cachedMetadata[provider] = newMetadata
            
            // Ensure OpenAI image model metadata exists with image-generation capability
            let normalized = provider.lowercased()
            if normalized == "chatgpt" || normalized == "openai" {
                let modelId = "gpt-image-1"
                if cachedMetadata[provider]?[modelId] == nil {
                    let imageMeta = ModelMetadata(
                        modelId: modelId,
                        provider: provider,
                        pricing: nil,
                        maxContextTokens: nil,
                        capabilities: ["image-generation"],
                        latency: nil,
                        costLevel: nil,
                        lastUpdated: Date(),
                        source: .providerDocumentation
                    )
                    upsertMetadata(provider: provider, metadata: imageMeta)
                } else {
                    // Ensure the capability includes image-generation
                    if var existing = cachedMetadata[provider]?[modelId] {
                        if !existing.capabilities.contains("image-generation") {
                            var caps = existing.capabilities
                            caps.append("image-generation")
                            let updated = ModelMetadata(
                                modelId: existing.modelId,
                                provider: existing.provider,
                                pricing: existing.pricing,
                                maxContextTokens: existing.maxContextTokens,
                                capabilities: caps,
                                latency: existing.latency,
                                costLevel: existing.costLevel,
                                lastUpdated: Date(),
                                source: existing.source
                            )
                            upsertMetadata(provider: provider, metadata: updated)
                        }
                    }
                }
            }
            
            saveToStorage()
        } catch {
            WardenLog.app.error(
                "Failed to fetch metadata for \(provider, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
        }
    }
    
    /// Force refresh metadata for a provider
    func refreshMetadata(provider: String, apiKey: String) async {
        lastRefreshAttempt[provider] = nil
        await fetchMetadataIfNeeded(provider: provider, apiKey: apiKey)
    }
    
    /// Clear cache for a provider
    func clearCache(for provider: String) {
        cachedMetadata[provider] = nil
        lastRefreshAttempt[provider] = nil
        saveToStorage()
    }
    
    /// Clear all cached metadata
    func clearAllCache() {
        cachedMetadata.removeAll()
        lastRefreshAttempt.removeAll()
        saveToStorage()
    }
    
    // MARK: - Storage
    
    private func saveToStorage() {
        do {
            let encoder = JSONEncoder()
            metadataCacheData = try encoder.encode(cachedMetadata)
        } catch {
            WardenLog.app.error("Failed to save metadata cache: \(error.localizedDescription, privacy: .public)")
        }
    }
    
    private func loadFromStorage() {
        guard !metadataCacheData.isEmpty else { return }
        
        do {
            let decoder = JSONDecoder()
            cachedMetadata = try decoder.decode([String: [String: ModelMetadata]].self, from: metadataCacheData)
        } catch {
            WardenLog.app.error("Failed to load metadata cache: \(error.localizedDescription, privacy: .public)")
            cachedMetadata = [:]
        }
    }
}

