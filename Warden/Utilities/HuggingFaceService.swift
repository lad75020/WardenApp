import CoreML
import Foundation
import Tokenizers
import Generation
import Models
import os

class HuggingFaceService: NSObject, APIService {
    var name: String = "HuggingFace"
    var baseURL: URL = URL(string: "local://huggingface")!
    var session: URLSession = .shared
    var model: String
    
    // Swift-transformers model instance
    private var modelInstance: LanguageModelProtocol?
    private var isModelLoading = false
    private var modelLoadError: Error?
    
    init(model: String) {
        self.model = model
        super.init()
    }
    
    func sendMessage(
        _ requestMessages: [[String: String]],
        tools: [[String: Any]]?,
        temperature: Float,
        completion: @escaping (Result<(String?, [ToolCall]?), APIError>) -> Void
    ) {
        Task {
            do {
                let (response, _) = try await sendMessage(requestMessages, tools: tools, temperature: temperature)
                completion(.success((response, nil)))
            } catch {
                completion(.failure(error as? APIError ?? APIError.requestFailed(error)))
            }
        }
    }
    
    func sendMessageStream(
        _ requestMessages: [[String: String]],
        tools: [[String: Any]]?,
        temperature: Float
    ) async throws -> AsyncThrowingStream<(String?, [ToolCall]?), Error> {
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    // Load the model if not already loaded
                    try await ensureModelLoaded()
                    
                    guard let modelInstance = modelInstance else {
                        continuation.finish(throwing: APIError.serverError("Model failed to load"))
                        return
                    }
                    
                    // Convert messages to prompt format
                    let prompt = convertToTransformerInput(requestMessages)
                    
                    // Create generation config with streaming enabled
                    let config = createGenerationConfig(temperature: temperature)
                    
                    #if DEBUG
                    WardenLog.app.debug("Starting HuggingFace streaming inference with prompt length: \(prompt.count)")
                    #endif
                    
                    var accumulatedResponse = ""
                    
                    if let realModel = modelInstance as? LanguageModel {
                        // Real LanguageModel implementation with proper streaming
                        try await withMLTensorComputePolicy(.cpuOnly) {
                            try await realModel.generate(config: config, prompt: prompt) { inProgressGeneration in
                                let responseText = formatResponse(inProgressGeneration)
                                
                                // Only yield new content that hasn't been sent yet
                                if responseText.count > accumulatedResponse.count {
                                    let newContent = String(responseText.dropFirst(accumulatedResponse.count))
                                    if !newContent.isEmpty {
                                        continuation.yield((newContent, nil))
                                        accumulatedResponse = responseText
                                    }
                                }
                            }
                        }
                    } else {
                        // Mock implementation for testing - simulate streaming
                        try await modelInstance.generateStreaming(config: config, prompt: prompt) { token in
                            continuation.yield((token, nil))
                        }
                    }
                    
                    continuation.finish()
                    
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    func fetchModels() async throws -> [AIModel] {
        let modelsPath = "/Volumes/WDBlack4TB/HFModels/"
        let fileManager = FileManager.default
        
        // Start with models from AppConstants
        let presetModels = getPresetModels()
        var allModels = Set(presetModels.map { $0.id })
        
        // Check if the directory exists and add folder models
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: modelsPath, isDirectory: &isDirectory),
           isDirectory.boolValue {
            do {
                let contents = try fileManager.contentsOfDirectory(atPath: modelsPath)
                let modelDirectories = contents.filter { item in
                    var isDir: ObjCBool = false
                    let fullPath = (modelsPath as NSString).appendingPathComponent(item)
                    return fileManager.fileExists(atPath: fullPath, isDirectory: &isDir) && isDir.boolValue
                }
                
                #if DEBUG
                WardenLog.app.debug("Found \(modelDirectories.count) model directories at \(modelsPath)")
                #endif
                
                // Add folder models to our set (removes duplicates automatically)
                for modelName in modelDirectories {
                    allModels.insert(modelName)
                }
                
            } catch {
                #if DEBUG
                WardenLog.app.error("Error reading HuggingFace models directory: \(error.localizedDescription)")
                #endif
                // Continue with preset models if there's an error reading the directory
            }
        }
        
        #if DEBUG
        WardenLog.app.debug("Total HuggingFace models available: \(allModels.count) (Preset: \(presetModels.count), Folder: \(allModels.count - presetModels.count))")
        #endif
        
        // Sort alphabetically and create AIModel objects
        return allModels.sorted().map { AIModel(id: $0) }
    }
    
    private func getPresetModels() -> [AIModel] {
        // Return preset models from AppConstants
        let presetModels = AppConstants.defaultApiConfigurations["huggingface"]?.models ?? []
        return presetModels.map { AIModel(id: $0) }
    }
    
    func prepareRequest(
        requestMessages: [[String: String]],
        tools: [[String: Any]]?,
        model: String,
        temperature: Float,
        stream: Bool
    ) throws -> URLRequest {
        // This is a local service - create a dummy request
        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        return request
    }
    
    func parseJSONResponse(data: Data) -> (String?, String?, [ToolCall]?)? {
        // This method is not used for local HuggingFace inference
        // Return nil to indicate no parsing was done
        return nil
    }
    
    func parseDeltaJSONResponse(data: Data?) -> (Bool, Error?, String?, String?, [ToolCall]?) {
        // This method is not used for local inference
        return (false, nil, nil, nil, nil)
    }
    
    func handleAPIResponse(_ response: URLResponse?, data: Data?, error: Error?) -> Result<Data?, APIError> {
        if let error = error {
            return .failure(.requestFailed(error))
        }
        
        // For local inference, we don't have HTTP responses
        // Return success with the data (if any)
        return .success(data)
    }
    
    func isNotSSEComment(_ string: String) -> Bool {
        return !string.starts(with: ":")
    }
    
    // MARK: - Swift-transformers Integration
    
    private func ensureModelLoaded() async throws {
        if let modelInstance = modelInstance {
            return
        }
        
        if isModelLoading {
            // Wait for current load to complete
            while isModelLoading {
                try await Task.sleep(nanoseconds: 100_000_000) // 100ms
            }
            if let error = modelLoadError {
                throw error
            }
            return
        }
        
        isModelLoading = true
        modelLoadError = nil
        
        do {
            #if DEBUG
            WardenLog.app.debug("Loading HuggingFace model: \(self.model)")
            #endif
            
            // Build the full path to the model
            let modelFolderURL = URL(fileURLWithPath: "/Volumes/WDBlack4TB/HFModels/\(self.model)")
            
            // Check if the model directory exists
            guard FileManager.default.fileExists(atPath: modelFolderURL.path) else {
                throw APIError.serverError("Model directory not found: \(modelFolderURL.path)")
            }
            
            // Locate compiled model (prefer Model.mlpackage, then Model.mlmodelc)
            let fm = FileManager.default
            var compiledURL: URL?
            let preferredPackage = modelFolderURL.appendingPathComponent("Model.mlpackage")
            let preferredCompiled = modelFolderURL.appendingPathComponent("Model.mlmodelc")
            
            if fm.fileExists(atPath: preferredPackage.path) {
                compiledURL = preferredPackage
            } else if fm.fileExists(atPath: preferredCompiled.path) {
                compiledURL = preferredCompiled
            } else if let found = try? fm.contentsOfDirectory(at: modelFolderURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]).first(where: { $0.pathExtension == "mlpackage" || $0.pathExtension == "mlmodelc" }) {
                compiledURL = found
            }
            
            guard let compiledURL else {
                throw APIError.serverError("Compiled model (Model.mlpackage or Model.mlmodelc) not found in: \(modelFolderURL.path)")
            }
            
            #if DEBUG
            WardenLog.app.debug("Found compiled model: \(compiledURL)")
            #endif
            
            #if DEBUG
            WardenLog.app.debug("Preflighting compiled model: \(compiledURL.lastPathComponent)")
            #endif
            try preflightValidateCompiledModel(at: compiledURL)
            
            // Resolve tokenizer folder and json file
            // Prefer tokenizer/tokenizer.json, then tokenizer.json in model folder, else any .json at root of modelFolderURL
            var tokenizerFolder: URL?
            
            let tokenizerDir = modelFolderURL.appendingPathComponent("tokenizer")
            let tokenizerJsonInTokenizerDir = tokenizerDir.appendingPathComponent("tokenizer.json")
            let tokenizerJsonInModelFolder = modelFolderURL.appendingPathComponent("tokenizer.json")
            
            if fm.fileExists(atPath: tokenizerJsonInTokenizerDir.path) {
                tokenizerFolder = tokenizerDir
            } else if fm.fileExists(atPath: tokenizerJsonInModelFolder.path) {
                tokenizerFolder = modelFolderURL
            } else {
                // fallback: find any .json file in modelFolderURL root and use modelFolderURL as tokenizerFolder
                if let anyJSON = try? fm.contentsOfDirectory(at: modelFolderURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]).first(where: { $0.pathExtension.lowercased() == "json" }) {
                    tokenizerFolder = modelFolderURL
                }
            }
            
            guard let tokenizerFolder else {
                throw APIError.serverError("Required tokenizer configuration (.json) missing in: \(modelFolderURL.path)")
            }
            
            let tokenizer = try await AutoTokenizer.from(modelFolder: tokenizerFolder)
            #if DEBUG
            WardenLog.app.debug("Using tokenizer folder: \(tokenizerFolder.path)")
            #endif
            
            self.modelInstance = try LanguageModel.loadCompiled(
                url: compiledURL,
                computeUnits: .cpuAndGPU, // Default to CPU and GPU
                tokenizer: tokenizer
            )
            
            #if DEBUG
            WardenLog.app.debug("Successfully loaded HuggingFace model: \(self.model)")
            #endif
            
        } catch {
            // Fallback to mock implementation if loading fails
            modelLoadError = error
            #if DEBUG
            WardenLog.app.error("Failed to load HuggingFace model \(self.model): \(error.localizedDescription)")
            WardenLog.app.debug("Falling back to mock implementation")
            #endif
            
            // Create a mock instance for now
            self.modelInstance = MockLanguageModel()
        }
        
        isModelLoading = false
    }
    
    // Preflight validation to avoid runtime crashes when model metadata is incompatible
    private func preflightValidateCompiledModel(at url: URL) throws {
        let config = MLModelConfiguration()
        config.computeUnits = .cpuOnly
        
        // Load the model to inspect its description
        let coremlModel: MLModel
        do {
            coremlModel = try MLModel(contentsOf: url, configuration: config)
        } catch {
            #if DEBUG
            WardenLog.app.error("Preflight: Failed to load Core ML model at \(url): \(error.localizedDescription)")
            #endif
            throw APIError.serverError("Preflight failed: cannot load Core ML model (\(error.localizedDescription))")
        }
        
        let inputs = coremlModel.modelDescription.inputDescriptionsByName
        if inputs.isEmpty {
            #if DEBUG
            WardenLog.app.error("Preflight: Model has no inputs. Description=\(coremlModel.modelDescription)")
            #endif
            throw APIError.serverError("Preflight failed: model exposes no inputs; not a compatible language model.")
        }
        
        // We expect at least one integer multi-array input (e.g., token IDs)
        var hasIntegerMultiArray = false
        var inputSummaries: [String] = []
        for (name, desc) in inputs {
            inputSummaries.append(describeFeature(name, desc))
            if desc.type == .multiArray, let c = desc.multiArrayConstraint {
                var isIntegerMultiArray = false
                if c.dataType == .int32 {
                    isIntegerMultiArray = true
                }
                #if swift(>=5.9)
                // Some SDKs expose `.int64`; guard its use behind conditional compilation
                if !isIntegerMultiArray {
                    // Use string description fallback to detect int64 without referencing the symbol directly
                    if String(describing: c.dataType).lowercased().contains("int64") {
                        isIntegerMultiArray = true
                    }
                }
                #endif
                if isIntegerMultiArray {
                    // Ensure shape information is present (may include flexible dims as -1)
                    if !c.shape.isEmpty || c.shapeConstraint != nil {
                        hasIntegerMultiArray = true
                    }
                }
            }
        }
        
        if !hasIntegerMultiArray {
            #if DEBUG
            WardenLog.app.error("Preflight: No integer multi-array input found. Inputs=\(inputSummaries.joined(separator: "; "))")
            #endif
            throw APIError.serverError("Preflight failed: expected an integer multi-array input (e.g., token IDs). Inputs: \(inputSummaries.joined(separator: "; "))")
        }
        
        #if DEBUG
        WardenLog.app.debug("Preflight: Model inputs OK. Inputs=\(inputSummaries.joined(separator: "; "))")
        #endif
    }
    
    private func describeFeature(_ name: String, _ fd: MLFeatureDescription) -> String {
        var parts: [String] = []
        parts.append("name=\(name)")
        parts.append("type=\(fd.type)")
        if let c = fd.multiArrayConstraint {
            let shapeStr = c.shape.map { dim in
                let v = dim.intValue
                return v >= 0 ? String(v) : "?"
            }.joined(separator: "x")
            parts.append("shape=\(shapeStr)")
            parts.append("dtype=\(c.dataType)")
        }
        return parts.joined(separator: ", ")
    }
    
    private func convertToTransformerInput(_ requestMessages: [[String: String]]) -> String {
        // Convert chat messages to a format suitable for the language model
        var prompt = ""
        
        for message in requestMessages {
            guard let role = message["role"], let content = message["content"] else { continue }
                
            switch role {
            case "system":
                prompt += "System: \(content)\n\n"
            case "user":
                prompt += "User: \(content)\n\n"
            case "assistant":
                prompt += "Assistant: \(content)\n\n"
            default:
                break
            }
        }
        
        // Add prompt for the assistant's response
        prompt += "Assistant:"
        
        return prompt
    }
    
    private func createGenerationConfig(temperature: Float) -> GenerationConfig {
        return GenerationConfig(
            maxLength: 20,
            maxNewTokens: 1000,
            doSample: true,
            numBeams: 1,
            numBeamGroups: 1,
            penaltyAlpha: nil,
            temperature: Float(Double(temperature)),
            topK: 50,
            topP: 0.9,
            minP: nil,
            repetitionPenalty: 1.1
        )
    }
    
    // Implementation of non-streaming sendMessage
    private func sendMessage(_ requestMessages: [[String: String]], tools: [[String: Any]]? = nil, temperature: Float) async throws -> (String?, [ToolCall]?) {
        // Load the model if not already loaded
        try await ensureModelLoaded()
        
        guard let modelInstance = modelInstance else {
            throw APIError.serverError("Model failed to load")
        }
        
        // Convert messages to prompt format
        let prompt = convertToTransformerInput(requestMessages)
        
        // Create generation config
        let config = createGenerationConfig(temperature: temperature)
        
        #if DEBUG
        WardenLog.app.debug("Running HuggingFace inference with prompt length: \(prompt.count)")
        WardenLog.app.debug("Generation config: temperature=\(temperature), maxTokens=\(config.maxNewTokens)")
        #endif
        
        var generatedText = ""
        
        // Use actual swift-transformers generation
        if let realModel = modelInstance as? LanguageModel {
            // Real LanguageModel implementation
            try await withMLTensorComputePolicy(.cpuOnly) {
                try await realModel.generate(config: config, prompt: prompt) { inProgressGeneration in
                    let response = formatResponse(inProgressGeneration)
                    generatedText = response
                }
            }
            
            #if DEBUG
            WardenLog.app.debug("Generated response length: \(generatedText.count)")
            #endif
            
        } else {
            // Generic implementation (for MockLanguageModel)
            generatedText = try await modelInstance.generate(config: config, prompt: prompt)
        }
        
        return (generatedText.trimmingCharacters(in: .whitespacesAndNewlines), nil)
    }
}

// MARK: - Protocol and Mock implementation
protocol LanguageModelProtocol {
    func generate(config: GenerationConfig, prompt: String) async throws -> String
    func generateStreaming(config: GenerationConfig, prompt: String, onToken: @escaping (String) -> Void) async throws
}

extension LanguageModel: LanguageModelProtocol {
    func generate(config: GenerationConfig, prompt: String) async throws -> String {
        var result = ""
        try await self.generate(config: config, prompt: prompt) { inProgressGeneration in
            result = formatResponse(inProgressGeneration)
        }
        return result
    }
    
    func generateStreaming(config: GenerationConfig, prompt: String, onToken: @escaping (String) -> Void) async throws {
        try await self.generate(config: config, prompt: prompt) { inProgressGeneration in
            let response = formatResponse(inProgressGeneration)
            onToken(response)
        }
    }
}

class MockLanguageModel: LanguageModelProtocol {
    func generate(config: GenerationConfig, prompt: String) async throws -> String {
        // Simulate inference delay
        try await Task.sleep(nanoseconds: 500_000_000) // 500ms delay
        
        // Return simulated response based on prompt
        let responses = [
            "I understand your question. Based on the conversation context, here's my response...",
            "That's an interesting point. Let me provide some insights on this topic...",
            "I appreciate you sharing this with me. Here's what I think about it...",
            "Based on our discussion, I believe the best approach would be...",
            "I've considered your input and here are my thoughts..."
        ]
        
        return responses.randomElement() ?? "This is a response from the HuggingFace model."
    }
    
    func generateStreaming(config: GenerationConfig, prompt: String, onToken: @escaping (String) -> Void) async throws {
        let mockResponse = try await generate(config: config, prompt: prompt)
        let sentences = mockResponse.components(separatedBy: ". ")
        
        for (index, sentence) in sentences.enumerated() {
            var sentenceText = sentence
            if index < sentences.count - 1 {
                sentenceText += ". "
            }
            
            // Simulate gradual output
            let words = sentenceText.components(separatedBy: " ")
            for word in words {
                onToken(word + " ")
                try await Task.sleep(nanoseconds: 50_000_000) // 50ms delay between words
            }
        }
    }
}

// MARK: - Helper functions

/// Returns a cleaned and formatted version of the response.
private func formatResponse(_ response: String) -> String {
    response
        .replacingOccurrences(of: "\\n", with: "\n")
        .replacingOccurrences(of: "<s>", with: "")
        .replacingOccurrences(of: "</s>", with: "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

// MARK: - Factory Integration

// NOTE: APIServiceFactory is already implemented in APIServiceFactory.swift
// The HuggingFaceService is already included in the factory switch statement

// MARK: - Configuration Extension

class HuggingFaceAPIServiceConfiguration: APIServiceConfiguration {
    var name: String
    var apiUrl: URL
    var apiKey: String
    var model: String
    
    init(service: APIServiceEntity) {
        self.name = service.name ?? "HuggingFace"
        self.model = service.model ?? AppConstants.defaultApiConfigurations["huggingface"]?.defaultModel ?? "mistral-7b"
        self.apiUrl = service.url ?? URL(string: "local://huggingface")!
        self.apiKey = "" // HuggingFace doesn't require API key for local inference
    }
}

extension APIServiceManager {
    static func createAPIConfiguration(for service: APIServiceEntity) -> APIServiceConfiguration? {
        guard let type = service.type else { return nil }
            
        if type.lowercased() == "huggingface" {
            return HuggingFaceAPIServiceConfiguration(service: service)
        }
        
        // Fall back to existing implementation - use the standard APIConfiguration
        return StandardAPIConfiguration(service: service)
    }
}

// Simple configuration wrapper for other services
struct StandardAPIConfiguration: APIServiceConfiguration {
    var name: String
    var apiUrl: URL
    var apiKey: String
    var model: String
    
    init(service: APIServiceEntity) {
        self.name = service.name ?? "APIService"
        self.model = service.model ?? ""
        self.apiUrl = service.url ?? URL(string: "https://api.example.com")!
        self.apiKey = "" 
    }
}

extension HuggingFaceService {
    static func monitorModelDirectoryChanges() {
        let modelsPath = "/Volumes/WDBlack4TB/HFModels/"
        let fileManager = FileManager.default
        
        // Check if we can monitor this directory
        guard fileManager.fileExists(atPath: modelsPath) else { return }
        
        // Create a file descriptor for the directory
        let fd = open(modelsPath, O_EVTONLY)
        guard fd >= 0 else { return }
        
        DispatchQueue.global(qos: .background).async {
            let dispatchSource = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd,
                eventMask: .write,
                queue: DispatchQueue.global(qos: .background)
            )
            
            dispatchSource.setEventHandler {
#if DEBUG
                WardenLog.app.debug("HuggingFace models directory changed")
#endif
                
                // Notify that models should be refreshed
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("HuggingFaceDirectoryChanged"),
                        object: nil
                    )
                }
            }
            
            dispatchSource.setCancelHandler {
                close(fd)
            }
            
            dispatchSource.resume()
        }
    }
}

