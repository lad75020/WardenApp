import CoreML
import Foundation
import Tokenizers
import Generation
import Models
import os

/// Local CoreML text-generation provider using swift-transformers `LanguageModel.loadCompiled`.
///
/// Configure this service by setting the **Model** field to a local folder path that contains:
/// - `Model.mlpackage` or `Model.mlmodelc` (or any *.mlpackage/*.mlmodelc)
/// - `tokenizer.json` or `tokenizer/tokenizer.json`
///
/// This is basically the HuggingFaceService logic, but instead of hardcoding /Volumes/WDBlack4TB/HFModels/<id>
/// it uses the local path provided by the user.
final class CoreMLTextGenerationService: NSObject, APIService {

    var name: String = "CoreML LLM"
    var baseURL: URL = URL(string: "local://coreml-llm")!
    var session: URLSession = .shared
    var model: String // local folder path

    private var modelInstance: LanguageModelProtocol?
    private var isModelLoading = false
    private var modelLoadError: Error?

    init(modelPath: String) {
        self.model = modelPath
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
                let result = try await sendMessage(requestMessages, tools: tools, temperature: temperature)
                completion(.success(result))
            } catch let e as APIError {
                completion(.failure(e))
            } catch {
                completion(.failure(.unknown(error.localizedDescription)))
            }
        }
    }

    func sendMessageStream(
        _ requestMessages: [[String: String]],
        tools: [[String: Any]]?,
        temperature: Float
    ) async throws -> AsyncThrowingStream<(String?, [ToolCall]?), Error> {

        try await ensureModelLoaded()

        let prompt = convertToTransformerInput(requestMessages)
        let config = createGenerationConfig(temperature: temperature)

        guard let modelInstance else {
            throw APIError.serverError("Model not loaded")
        }

        return AsyncThrowingStream { continuation in
            let task = Task(priority: .userInitiated) {
                do {
                    if let real = modelInstance as? LanguageModel {
                        var deliveredResponse = ""
                        try await real.generate(config: config, prompt: prompt) { partial in
                            guard !Task.isCancelled else { return }
                            let response = coremlFormatResponse(partial)
                            let delta = Self.streamingDelta(previous: deliveredResponse, current: response)
                            guard !delta.isEmpty else { return }
                            deliveredResponse = response
                            continuation.yield((delta, nil))
                        }
                    } else {
                        let full = try await modelInstance.generate(config: config, prompt: prompt)
                        continuation.yield((coremlFormatResponse(full), nil))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func fetchModels() async throws -> [AIModel] { [] }

    func prepareRequest(
        requestMessages: [[String: String]],
        tools: [[String: Any]]?,
        model: String,
        temperature: Float,
        stream: Bool
    ) throws -> URLRequest {
        throw APIError.noApiService("CoreMLTextGenerationService does not use network requests")
    }

    func parseJSONResponse(data: Data) -> (String?, String?, [ToolCall]?)? { nil }

    func parseDeltaJSONResponse(data: Data?) -> (Bool, Error?, String?, String?, [ToolCall]?) {
        (true, nil, nil, nil, nil)
    }

    static func streamingDelta(previous: String, current: String) -> String {
        guard current.hasPrefix(previous) else { return current }
        return String(current.dropFirst(previous.count))
    }

    // MARK: - Loading

    static func validateModelDirectory(at modelFolderURL: URL) throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: modelFolderURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue,
              FileManager.default.isReadableFile(atPath: modelFolderURL.path) else {
            throw APIError.serverError("Configured Core ML model directory is unavailable or unreadable.")
        }
    }

    private func ensureModelLoaded() async throws {
        if modelInstance != nil { return }

        if isModelLoading {
            while isModelLoading {
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            if let error = modelLoadError { throw error }
            return
        }

        isModelLoading = true
        modelLoadError = nil
        defer { isModelLoading = false }

        do {
            let modelFolderURL = URL(fileURLWithPath: model).standardizedFileURL
            try Self.validateModelDirectory(at: modelFolderURL)

            let fm = FileManager.default

            // Locate compiled model (prefer Model.mlpackage, then Model.mlmodelc)
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
                throw APIError.serverError("A compiled Core ML model asset (*.mlpackage or *.mlmodelc) is required.")
            }

            // Resolve tokenizer folder
            var tokenizerFolder: URL?
            let tokenizerDir = modelFolderURL.appendingPathComponent("tokenizer")
            let tokenizerJsonInTokenizerDir = tokenizerDir.appendingPathComponent("tokenizer.json")
            let tokenizerJsonInModelFolder = modelFolderURL.appendingPathComponent("tokenizer.json")

            if fm.fileExists(atPath: tokenizerJsonInTokenizerDir.path) {
                tokenizerFolder = tokenizerDir
            } else if fm.fileExists(atPath: tokenizerJsonInModelFolder.path) {
                tokenizerFolder = modelFolderURL
            } else {
                if let anyJSON = try? fm.contentsOfDirectory(at: modelFolderURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]).first(where: { $0.pathExtension.lowercased() == "json" }) {
                    _ = anyJSON
                    tokenizerFolder = modelFolderURL
                }
            }

            guard let tokenizerFolder else {
                throw APIError.serverError("A tokenizer JSON configuration is required in the configured Core ML model directory.")
            }

            _ = try await AutoTokenizer.from(modelFolder: tokenizerFolder)

            self.modelInstance = try LanguageModel.loadCompiled(
                url: compiledURL,
                computeUnits: .cpuAndGPU
            )
        } catch {
            modelLoadError = error
            throw error
        }
    }

    // MARK: - Prompt + config

    private func createGenerationConfig(temperature: Float) -> GenerationConfig {
        // Mirror HuggingFaceService defaults.
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

    private func convertToTransformerInput(_ requestMessages: [[String: String]]) -> String {
        // Simple format: system + conversation.
        var prompt = ""
        for message in requestMessages {
            guard let role = message["role"], let content = message["content"] else { continue }
            switch role {
            case "system":
                prompt += "[SYSTEM]\n\(content)\n\n"
            case "user":
                prompt += "[USER]\n\(content)\n\n"
            case "assistant":
                prompt += "[ASSISTANT]\n\(content)\n\n"
            default:
                prompt += "[\(role.uppercased())]\n\(content)\n\n"
            }
        }
        prompt += "[ASSISTANT]\n"
        return prompt
    }
}

// MARK: - Helpers

private func coremlFormatResponse(_ response: String) -> String {
    response
        .replacingOccurrences(of: "\\n", with: "\n")
        .replacingOccurrences(of: "<s>", with: "")
        .replacingOccurrences(of: "</s>", with: "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
}
