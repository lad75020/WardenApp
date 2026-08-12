import CoreData
import Foundation
import SwiftUI

/// A lossless, persistent model identity. Both components are opaque values and
/// are therefore encoded as structured JSON rather than joined with a delimiter.
struct ModelSelectionIdentity: Codable, Hashable, Identifiable, Sendable {
    let provider: String
    let modelID: String

    var id: Self { self }
}

/// Pure selection rules that can be exercised without credentials or network access.
enum ModelSelectionPolicy {
    static func isSelectable(
        _ identity: ModelSelectionIdentity,
        configuredProviders: Set<String>,
        visibleModels: Set<ModelSelectionIdentity>
    ) -> Bool {
        configuredProviders.contains(identity.provider) && visibleModels.contains(identity)
    }

    private struct HuggingFaceStoredModel: Codable {
        let name: String
    }

    @MainActor
    static func visibleModels(for services: [APIServiceEntity]) -> Set<ModelSelectionIdentity> {
        let cache = ModelCacheManager.shared
        let selections = SelectedModelsManager.shared
        let metadataCache = ModelMetadataCache.shared

        return Set(services.flatMap { service -> [ModelSelectionIdentity] in
            guard let provider = service.type, !provider.isEmpty else { return [] }

            var modelIDs = cache.getModels(for: provider).map(\.id)
            if provider.caseInsensitiveCompare("huggingface") == .orderedSame,
               let rawModels = UserDefaults.standard.string(forKey: "hfModelsStore"),
               let data = rawModels.data(using: .utf8),
               let storedModels = try? JSONDecoder().decode([HuggingFaceStoredModel].self, from: data) {
                modelIDs.append(contentsOf: storedModels.map(\.name))
            }

            let normalizedProvider = provider.lowercased()
            let requiresCustomSelection = normalizedProvider != "coreml llm" && normalizedProvider != "mlx"
            let selectedModelIDs = selections.getSelectedModelIds(for: provider)
            let hasCustomSelection = selections.hasCustomSelection(for: provider)

            return Set(modelIDs).compactMap { modelID in
                if requiresCustomSelection, hasCustomSelection, !selectedModelIDs.contains(modelID) {
                    return nil
                }

                let isImageGeneration = metadataCache
                    .getMetadata(provider: provider, modelId: modelID)?
                    .hasCapability("image-generation") ?? false
                guard !isImageGeneration || service.imageUploadsAllowed else { return nil }

                return ModelSelectionIdentity(provider: provider, modelID: modelID)
            }
        })
    }
}

/// Applies a validated provider/model pair as one Core Data change and recreates
/// only the affected chat manager after the save succeeds.
@MainActor
enum ChatModelSelectionCoordinator {
    enum Failure: LocalizedError {
        case unavailable
        case persistence

        var errorDescription: String? {
            switch self {
            case .unavailable:
                return "That model is no longer available for this chat."
            case .persistence:
                return "The chat configuration could not be saved."
            }
        }
    }

    static func apply(
        service: APIServiceEntity,
        modelID: String,
        to chat: ChatEntity,
        services: [APIServiceEntity],
        context: NSManagedObjectContext
    ) -> Result<Void, Failure> {
        guard services.contains(where: { $0.objectID == service.objectID }),
              let provider = service.type,
              !provider.isEmpty else {
            return .failure(.unavailable)
        }

        let identity = ModelSelectionIdentity(provider: provider, modelID: modelID)
        let configuredProviders = Set(services.compactMap(\.type))
        let visibleModels = ModelSelectionPolicy.visibleModels(for: services)
        guard ModelSelectionPolicy.isSelectable(
            identity,
            configuredProviders: configuredProviders,
            visibleModels: visibleModels
        ) else {
            return .failure(.unavailable)
        }

        let previousService = chat.apiService
        let previousModel = chat.gptModel
        let previousUpdatedDate = chat.updatedDate

        chat.apiService = service
        chat.gptModel = modelID
        chat.updatedDate = Date()
        chat.objectWillChange.send()

        do {
            try context.save()
            NotificationCenter.default.post(
                name: NSNotification.Name("RecreateMessageManager"),
                object: nil,
                userInfo: ["chatId": chat.id]
            )
            return .success(())
        } catch {
            chat.apiService = previousService
            chat.gptModel = previousModel
            chat.updatedDate = previousUpdatedDate
            chat.objectWillChange.send()
            WardenLog.coreData.error("Failed to save chat model selection")
            return .failure(.persistence)
        }
    }
}

/// Manages non-secret favorite model identities across configured providers.
@MainActor
final class FavoriteModelsManager: ObservableObject {
    static let shared = FavoriteModelsManager()

    @AppStorage("favoriteModels") private var favoriteModelsData: Data = Data()
    @Published private(set) var favoriteModels: Set<ModelSelectionIdentity> = []

    private init() {
        loadFavorites()
    }

    func isFavorite(provider: String, model: String) -> Bool {
        favoriteModels.contains(ModelSelectionIdentity(provider: provider, modelID: model))
    }

    func toggleFavorite(provider: String, model: String) {
        let identity = ModelSelectionIdentity(provider: provider, modelID: model)
        if favoriteModels.contains(identity) {
            favoriteModels.remove(identity)
        } else {
            favoriteModels.insert(identity)
        }
        saveFavorites()
    }

    func addFavorite(provider: String, model: String) {
        favoriteModels.insert(ModelSelectionIdentity(provider: provider, modelID: model))
        saveFavorites()
    }

    func removeFavorite(provider: String, model: String) {
        favoriteModels.remove(ModelSelectionIdentity(provider: provider, modelID: model))
        saveFavorites()
    }

    func getAllFavorites() -> [ModelSelectionIdentity] {
        favoriteModels.sorted {
            if $0.provider != $1.provider { return $0.provider < $1.provider }
            return $0.modelID < $1.modelID
        }
    }

    func getFavorites(for provider: String) -> [String] {
        getAllFavorites()
            .filter { $0.provider == provider }
            .map(\.modelID)
    }

    func clearAllFavorites() {
        favoriteModels.removeAll()
        saveFavorites()
    }

    static func decodeFavorites(from data: Data) -> Set<ModelSelectionIdentity> {
        let decoder = JSONDecoder()
        if let identities = try? decoder.decode([ModelSelectionIdentity].self, from: data) {
            return Set(identities)
        }
        if let legacyKeys = try? decoder.decode([String].self, from: data) {
            return legacyIdentities(from: legacyKeys)
        }
        return []
    }

    private static func legacyIdentities(from keys: [String]) -> Set<ModelSelectionIdentity> {
        // Migration from the former provider:model representation. Split only at the
        // first separator so opaque model identifiers retain subsequent separators.
        Set(keys.compactMap { key in
            guard let separator = key.firstIndex(of: ":") else { return nil }
            let provider = String(key[..<separator])
            let modelStart = key.index(after: separator)
            let model = String(key[modelStart...])
            guard !provider.isEmpty, !model.isEmpty else { return nil }
            return ModelSelectionIdentity(provider: provider, modelID: model)
        })
    }

    private func loadFavorites() {
        guard !favoriteModelsData.isEmpty else { return }

        let decoder = JSONDecoder()
        if let identities = try? decoder.decode([ModelSelectionIdentity].self, from: favoriteModelsData) {
            favoriteModels = Set(identities)
        } else if let legacyKeys = try? decoder.decode([String].self, from: favoriteModelsData) {
            favoriteModels = Self.legacyIdentities(from: legacyKeys)
        } else {
            favoriteModels = []
            WardenLog.app.error("Failed to load favorite model preferences")
        }
    }

    private func saveFavorites() {
        do {
            favoriteModelsData = try JSONEncoder().encode(getAllFavorites())
        } catch {
            WardenLog.app.error("Failed to save favorite model preferences")
        }
    }
}
