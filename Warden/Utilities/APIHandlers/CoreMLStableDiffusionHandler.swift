import Foundation
import AppKit
import CoreML

#if canImport(StableDiffusion)
import StableDiffusion
#endif

/// Local CoreML Stable Diffusion provider.
///
/// This provider is designed for **image generation** (text-to-image). It returns the generated
/// image as a `<image-url>data:image/png;base64,...</image-url>` payload so the existing Warden UI
/// can display it.
///
/// Configuration:
/// - `model` should be a local folder path that contains the compiled Core ML bundle:
///   - TextEncoder.mlmodelc
///   - Unet.mlmodelc (or UnetChunk1/2)
///   - VAEDecoder.mlmodelc
///   - merges.txt
///   - vocab.json
///
/// Notes:
/// - This file compiles even if the Apple `ml-stable-diffusion` Swift package isn't added.
///   If `StableDiffusion` can't be imported, it will throw a clear error at runtime.
final class CoreMLStableDiffusionHandler: APIService {

    let name: String
    let baseURL: URL
    let session: URLSession
    let model: String

    private var cachedPipeline: Any? = nil
    private let pipelineLock = NSLock()

    init(config: APIServiceConfiguration) {
        self.name = config.name
        self.baseURL = config.apiUrl
        self.model = config.model
        self.session = APIServiceFactory.standardSession
    }

    func sendMessage(
        _ requestMessages: [[String: String]],
        tools: [[String: Any]]?,
        temperature: Float,
        completion: @escaping (Result<(String?, [ToolCall]?), APIError>) -> Void
    ) {
        Task {
            do {
                let (content, toolCalls) = try await self.sendMessage(requestMessages, tools: tools, temperature: temperature)
                completion(.success((content, toolCalls)))
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
        // No true streaming; yield once.
        let (content, toolCalls) = try await sendMessage(requestMessages, tools: tools, temperature: temperature)
        return AsyncThrowingStream { continuation in
            continuation.yield((content, toolCalls))
            continuation.finish()
        }
    }

    func fetchModels() async throws -> [AIModel] {
        // This provider expects a local folder path, so there isn't a canonical model list.
        return []
    }

    func prepareRequest(
        requestMessages: [[String: String]],
        tools: [[String: Any]]?,
        model: String,
        temperature: Float,
        stream: Bool
    ) throws -> URLRequest {
        throw APIError.noApiService("CoreML provider does not use network requests")
    }

    func parseJSONResponse(data: Data) -> (String?, String?, [ToolCall]?)? { nil }

    func parseDeltaJSONResponse(data: Data?) -> (Bool, Error?, String?, String?, [ToolCall]?) {
        (true, nil, nil, nil, nil)
    }

    // MARK: - Core generation

    private func sendMessage(
        _ requestMessages: [[String: String]],
        tools: [[String: Any]]?,
        temperature: Float
    ) async throws -> (String?, [ToolCall]?) {

        #if !canImport(StableDiffusion)
        throw APIError.noApiService("StableDiffusion module not available. Add the Swift package https://github.com/apple/ml-stable-diffusion and link product 'StableDiffusion' to the Warden target.")
        #else

        let prompt = extractPrompt(from: requestMessages)
        guard !prompt.isEmpty else {
            throw APIError.decodingFailed("No user prompt found")
        }

        let baseURL = URL(fileURLWithPath: model)
        guard FileManager.default.fileExists(atPath: baseURL.path) else {
            throw APIError.serverError("CoreML model folder not found: \(baseURL.path)")
        }

        let pipeline = try getOrCreatePipeline(resourcesAt: baseURL)

        // SD2 typically 512x512; SDXL typically 768x768. The model bundle determines actual size.
        var cfg = PipelineConfiguration(prompt: prompt)
        cfg.negativePrompt = ""
        cfg.stepCount = 20
        cfg.guidanceScale = 7.5
        cfg.imageCount = 1
        cfg.seed = UInt32(Date().timeIntervalSince1970) // non-deterministic
        cfg.disableSafety = true

        let images = try pipeline.generateImages(configuration: cfg) { _ in true }
        guard let cg = images.first ?? nil else {
            throw APIError.serverError("No image produced")
        }

        let pngData = try pngData(from: cg)
        let b64 = pngData.base64EncodedString()
        let content = "<image-url>data:image/png;base64,\(b64)</image-url>"
        return (content, nil)

        #endif
    }

    #if canImport(StableDiffusion)
    private func getOrCreatePipeline(resourcesAt baseURL: URL) throws -> any StableDiffusionPipelineProtocol {
        pipelineLock.lock(); defer { pipelineLock.unlock() }

        if let existing = cachedPipeline as? any StableDiffusionPipelineProtocol {
            return existing
        }

        let config = MLModelConfiguration()
        config.computeUnits = .cpuAndNeuralEngine

        let fm = FileManager.default
        let hasSDXL = fm.fileExists(atPath: baseURL.appendingPathComponent("TextEncoder2.mlmodelc").path)
            || fm.fileExists(atPath: baseURL.appendingPathComponent("UnetRefiner.mlmodelc").path)

        // reduceMemory=true to be safer on smaller Macs.
        let pipe: any StableDiffusionPipelineProtocol
        if hasSDXL {
            pipe = try StableDiffusionXLPipeline(
                resourcesAt: baseURL,
                configuration: config,
                reduceMemory: true
            )
        } else {
            pipe = try StableDiffusionPipeline(
                resourcesAt: baseURL,
                controlNet: [],
                configuration: config,
                disableSafety: true,
                reduceMemory: true
            )
        }

        try pipe.loadResources()

        cachedPipeline = pipe
        return pipe
    }
    #endif

    private func extractPrompt(from requestMessages: [[String: String]]) -> String {
        // Prefer last user message.
        for msg in requestMessages.reversed() {
            if (msg["role"] ?? "").lowercased() == "user" {
                return msg["content"] ?? ""
            }
        }
        // fallback to last message content
        return requestMessages.last?["content"] ?? ""
    }

    private func pngData(from cgImage: CGImage) throws -> Data {
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw APIError.decodingFailed("Failed to encode PNG")
        }
        return data
    }
}
