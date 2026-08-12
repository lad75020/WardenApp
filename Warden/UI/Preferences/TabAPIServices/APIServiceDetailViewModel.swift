import Combine
import SwiftUI
import os

@MainActor
final class APIServiceDetailViewModel: ObservableObject {
    private let viewContext: NSManagedObjectContext
    var apiService: APIServiceEntity?
    private var cancellables = Set<AnyCancellable>()
    private var notificationDismissTask: Task<Void, Never>?
    private var modelFetchTask: Task<Void, Never>?
    private var modelFetchGeneration = 0
    private var connectionTestGeneration = 0
    private var lastPromptedModelPath: String?

    @Published var name: String = AppConstants.defaultApiConfigurations[AppConstants.defaultApiType]?.name ?? ""
    @Published var type: String = AppConstants.defaultApiType
    @Published var url: String = ""
    @Published var model: String = ""
    @Published var contextSize: Float = 20
    @Published var contextSizeUnlimited: Bool = false
    @Published var useStreamResponse: Bool = true
    @Published var generateChatNames: Bool = true
    @Published var imageUploadsAllowed: Bool = false
    @Published var defaultAiPersona: PersonaEntity?
    @Published var apiKey: String = ""
    @Published var isCustomModel: Bool = false
    @Published var selectedModel: String =
        (AppConstants.defaultApiConfigurations[AppConstants.defaultApiType]?.defaultModel ?? "")
    @Published var defaultApiConfiguration = AppConstants.defaultApiConfigurations[AppConstants.defaultApiType]
    @Published var fetchedModels: [AIModel] = []
    @Published var isLoadingModels: Bool = false
    @Published var modelFetchError: String? = nil
    @Published var userNotification: UserNotification?
    @Published var accessRequestPath: String?
    @Published private(set) var isTestingConnection = false
    
    private let selectedModelsManager = SelectedModelsManager.shared
    
    // User-facing notification structure
    struct UserNotification: Identifiable {
        let id = UUID()
        let type: NotificationType
        let message: String
        
        enum NotificationType {
            case info
            case warning
            case error
            case success
        }
    }

    init(viewContext: NSManagedObjectContext, apiService: APIServiceEntity?) {
        self.viewContext = viewContext
        self.apiService = apiService

        setupInitialValues()
        setupBindings()
    }

    private func setupInitialValues() {
        if let service = apiService {
            name = service.name ?? defaultApiConfiguration?.name ?? "Untitled Service"
            type = service.type ?? AppConstants.defaultApiType
            url = service.url?.absoluteString ?? ""
            model = service.model ?? ""
            contextSize = Float(service.contextSize)
            useStreamResponse = service.useStreamResponse
            generateChatNames = service.generateChatNames
            imageUploadsAllowed = service.imageUploadsAllowed
            defaultAiPersona = service.defaultPersona
            defaultApiConfiguration = AppConstants.defaultApiConfigurations[type]
            if type.lowercased() == "chatgpt image" {
                useStreamResponse = false
            }
            selectedModel = model
            isCustomModel = !(defaultApiConfiguration?.models.contains(model) ?? false)

            if let serviceIDString = service.id?.uuidString {
                do {
                    apiKey = try TokenManager.getToken(for: serviceIDString) ?? ""
                }
                catch {
                    WardenLog.app.error("Failed to get token: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
        else {
            url = AppConstants.apiUrlChatCompletions
            imageUploadsAllowed = AppConstants.defaultApiConfigurations[type]?.imageUploadsSupported ?? false
        }
    }

    private func setupBindings() {
        $selectedModel
            .sink { [weak self] newValue in
                guard let self = self else { return }
                self.isCustomModel = (newValue == "custom")
                if !self.isCustomModel {
                    self.model = newValue
                }
            }
            .store(in: &cancellables)

        $model
            .sink { [weak self] newValue in
                self?.ensureSecurityScopedAccessIfNeeded(for: newValue)
            }
            .store(in: &cancellables)

        $type
            .sink { [weak self] _ in
                guard let self else { return }
                self.invalidateModelFetch()
                self.ensureSecurityScopedAccessIfNeeded(for: self.model)
            }
            .store(in: &cancellables)

        $url
            .dropFirst()
            .sink { [weak self] _ in self?.invalidateModelFetch() }
            .store(in: &cancellables)
    }

    func requestAccessIfNeeded() {
        ensureSecurityScopedAccessIfNeeded(for: model)
    }

    func updateModelPathIfNeeded(_ path: String) {
        let normalized = normalizePathSeparators(path)
        let existing = model
        if existing.contains(normalized) {
            return
        }
        if existing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            model = normalized
        } else {
            let trimmed = existing.trimmingCharacters(in: .whitespacesAndNewlines)
            model = trimmed + "\n" + normalized
        }
    }

    private func ensureSecurityScopedAccessIfNeeded(for rawModel: String) {
        let lowerType = type.lowercased()
        guard lowerType == "mlx" || lowerType == "coreml llm" else { return }

        let modelPath = resolveFirstModelPath(from: rawModel)
        guard !modelPath.isEmpty else { return }
        guard modelPath.contains("/") else { return }
        guard modelPath.split(separator: "/").count >= 3 else { return }

        if SecurityScopedBookmarkStore.resolveBookmarkURL(for: modelPath) != nil {
            lastPromptedModelPath = modelPath
            return
        }

        if lastPromptedModelPath == modelPath {
            return
        }
        lastPromptedModelPath = modelPath

        accessRequestPath = modelPath
    }

    private func resolveFirstModelPath(from raw: String) -> String {
        let first = raw
            .split(whereSeparator: { $0 == "\n" || $0 == "," || $0 == ";" })
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty }) ?? ""

        let normalized = normalizePathSeparators(first)

        if normalized.hasPrefix("file://"), let url = URL(string: normalized) {
            return url.standardizedFileURL.path
        }

        let expanded = (normalized as NSString).expandingTildeInPath
        return URL(fileURLWithPath: expanded).standardizedFileURL.path
    }

    private func normalizePathSeparators(_ value: String) -> String {
        let dashVariants: [String] = [
            "\u{2010}", "\u{2011}", "\u{2012}", "\u{2013}",
            "\u{2014}", "\u{2015}", "\u{2212}"
        ]
        var normalized = value
        for dash in dashVariants {
            normalized = normalized.replacingOccurrences(of: dash, with: "-")
        }
        return normalized
    }

    private func invalidateModelFetch() {
        modelFetchGeneration += 1
        modelFetchTask?.cancel()
        isLoadingModels = false
    }

    /// Runs only after an explicit Refresh action; opening or editing a draft never contacts a provider.
    private func fetchModelsForService() {
        guard type.lowercased() == "ollama" || !apiKey.isEmpty else {
            fetchedModels = []
            // Notify user if API key is missing for non-Ollama services
            if type.lowercased() != "ollama" {
                userNotification = UserNotification(
                    type: .warning,
                    message: "API key required to fetch models. Using default model list."
                )
            }
            return
        }
        
        guard case .success(let apiUrl) = APIServiceManager.validateEndpoint(url, credential: apiKey) else {
            fetchedModels = []
            userNotification = UserNotification(
                type: .error,
                message: "Enter a valid HTTP or HTTPS service URL."
            )
            return
        }

        isLoadingModels = true
        modelFetchError = nil
        userNotification = nil // Clear previous notifications

        let config = APIServiceConfig(
            name: type,
            apiUrl: apiUrl,
            apiKey: apiKey,
            model: ""
        )

        let apiService = APIServiceFactory.createAPIService(config: config)

        modelFetchTask?.cancel()
        let requestGeneration = modelFetchGeneration
        modelFetchTask = Task { [weak self] in
            guard let self else { return }
            do {
                let models = try await apiService.fetchModels()
                guard !Task.isCancelled, requestGeneration == self.modelFetchGeneration else { return }
                self.fetchedModels = models
                self.isLoadingModels = false

                if !models.contains(where: { $0.id == self.selectedModel })
                    && !self.availableModels.contains(where: { $0 == self.selectedModel })
                {
                    self.selectedModel = "custom"
                    self.isCustomModel = true
                }

                userNotification = UserNotification(
                    type: .success,
                    message: "✅ Fetched \(models.count) models from API"
                )

                notificationDismissTask?.cancel()
                notificationDismissTask = Task { [weak self] in
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    guard let self, case .success? = self.userNotification?.type else { return }
                    self.userNotification = nil
                }
            }
            catch {
                guard !Task.isCancelled, requestGeneration == self.modelFetchGeneration else { return }
                modelFetchError = APIServiceManager.userSafeErrorMessage(for: error)
                isLoadingModels = false

                userNotification = UserNotification(
                    type: .error,
                    message: APIServiceManager.userSafeErrorMessage(for: error)
                )

                #if DEBUG
                WardenLog.app.debug("Model discovery failed without exposing provider response details")
                #endif
            }
        }
    }

    var availableModels: [String] {
        if fetchedModels.isEmpty == false {
            return fetchedModels.map { $0.id }
        }
        else {
            return defaultApiConfiguration?.models ?? []
        }
    }

    func testConnection() {
        guard !isTestingConnection else { return }
        guard case .success(let serviceURL) = APIServiceManager.validateEndpoint(url, credential: apiKey) else {
            let validation = APIServiceManager.validateEndpoint(url, credential: apiKey)
            if case .failure(let error) = validation {
                userNotification = UserNotification(type: .error, message: APIServiceManager.userSafeEndpointMessage(for: error))
            }
            return
        }
        connectionTestGeneration += 1
        let generation = connectionTestGeneration
        isTestingConnection = true
        userNotification = UserNotification(type: .info, message: "Testing service connection…")
        let config = APIServiceConfig(name: type, apiUrl: serviceURL, apiKey: apiKey, model: model)
        let service = APIServiceFactory.createAPIService(config: config)
        MessageManager(apiService: service, viewContext: viewContext).testAPI(model: model) { [weak self] result in
            DispatchQueue.main.async {
                guard let self, generation == self.connectionTestGeneration else { return }
                self.isTestingConnection = false
                switch result {
                case .success:
                    self.userNotification = UserNotification(type: .success, message: "Service connection succeeded.")
                case .failure(let error):
                    self.userNotification = UserNotification(type: .error, message: APIServiceManager.userSafeErrorMessage(for: error))
                }
            }
        }
    }

    func saveAPIService() {
        guard case .success(let serviceURL) = APIServiceManager.validateEndpoint(url, credential: apiKey) else {
            let validation = APIServiceManager.validateEndpoint(url, credential: apiKey)
            if case .failure(let error) = validation {
                userNotification = UserNotification(type: .error, message: APIServiceManager.userSafeEndpointMessage(for: error))
            }
            return
        }

        switch APIServiceManager(viewContext: viewContext).saveAPIService(
            apiService,
            name: name,
            type: type,
            url: serviceURL,
            model: model,
            contextSize: Int16(contextSize),
            useStreamResponse: useStreamResponse,
            generateChatNames: generateChatNames,
            imageUploadsAllowed: imageUploadsAllowed,
            defaultPersona: defaultAiPersona,
            credential: apiKey
        ) {
        case .success(let saved):
            apiService = saved
            selectedModelsManager.saveToService(saved, context: viewContext)
            userNotification = UserNotification(type: .success, message: "Service saved.")
        case .failure:
            userNotification = UserNotification(type: .error, message: "Could not save the service. The previous configuration remains available when possible.")
        }
    }


    func deleteAPIService() -> Bool {
        guard let serviceToDelete = apiService else { return false }
        switch APIServiceManager(viewContext: viewContext).deleteAPIServiceTransactionally(serviceToDelete) {
        case .success:
            userNotification = UserNotification(type: .success, message: "Service deleted.")
            return true
        case .failure:
            userNotification = UserNotification(type: .error, message: "Could not delete the service. It remains available for recovery.")
            return false
        }
    }


    func onChangeApiType(_ type: String) {
        let oldConfigName = self.defaultApiConfiguration?.name ?? ""
        self.name = self.name == oldConfigName ? "" : self.name
        self.defaultApiConfiguration = AppConstants.defaultApiConfigurations[type]
        self.name = self.name == "" ? (self.defaultApiConfiguration?.name ?? "New API Service") : self.name
        self.url = self.defaultApiConfiguration?.url ?? ""
        self.model = self.defaultApiConfiguration?.defaultModel ?? ""
        self.selectedModel = self.model
        
        self.imageUploadsAllowed = self.defaultApiConfiguration?.imageUploadsSupported ?? false

        // Images endpoint does not support streaming; force disable when selecting this type
        if type.lowercased() == "chatgpt image" {
            self.useStreamResponse = false
        } else if self.useStreamResponse == false {
            // Re-enable by default for other types unless user changed it explicitly
            self.useStreamResponse = true
        }

        // A provider type change only updates editable defaults. Model discovery remains user initiated.
    }

    func onChangeApiKey(_ token: String) {
        apiKey = token
        invalidateModelFetch()
    }

    func onUpdateModelsList() {
        fetchModelsForService()
    }

    var supportsImageUploads: Bool {
        return AppConstants.defaultApiConfigurations[type]?.imageUploadsSupported ?? false
    }
    
    func updateSelectedModels(_ selectedIds: Set<String>) {
        selectedModelsManager.setSelectedModels(for: type, modelIds: selectedIds)
    }
    
    // MARK: - Error Handling
    private func validateSelectedModel() {
        // If the current model is not in available models, keep it as custom selection
        if !availableModels.contains(selectedModel) && !selectedModel.isEmpty {
            isCustomModel = true
            model = selectedModel
        }
    }
    /// Converts API errors to user-friendly messages
    private func getUserFriendlyErrorMessage(_ error: Error) -> String {
        if let apiError = error as? APIError {
            switch apiError {
            case .unauthorized:
                return "Invalid API key. Please check your credentials."
            case .serverError(let message):
                // Extract meaningful part of server error if possible
                if message.contains("401") {
                    return "Authentication failed - check your API key"
                } else if message.contains("404") {
                    return "API endpoint not found - check your URL"
                } else if message.contains("500") {
                    return "Server error - the API service is having issues"
                } else {
                    return "Server error: \(message.prefix(100))"
                }
            case .rateLimited:
                return "Rate limited - too many requests. Try again later."
            case .invalidResponse:
                return "Invalid response from server - check your API URL"
            case .requestFailed:
                return "Network request failed - check your internet connection"
            case .decodingFailed:
                return "Could not parse server response"
            default:
                return apiError.localizedDescription
            }
        }

        // Handle standard errors
        let nsError = error as NSError
        switch nsError.code {
        case NSURLErrorNotConnectedToInternet:
            return "No internet connection"
        case NSURLErrorTimedOut:
            return "Request timed out - check your network"
        case NSURLErrorCannotFindHost:
            return "Cannot find server - check your URL"
        case NSURLErrorCannotConnectToHost:
            return "Cannot connect to server - check if it's running"
        default:
            return error.localizedDescription
        }
    }
}
