import AppKit
import Foundation

#if canImport(MLX)
import MLX
import MLXLLM
import MLXLMCommon
import MLXVLM
import Hub
#endif

#if canImport(StableDiffusion)
import StableDiffusion
#endif

#if canImport(MLX)
private actor MLXContainerCache {
    private var textPath: String?
    private var visionPath: String?
    private var textContainer: MLXLMCommon.ModelContainer?
    private var visionContainer: MLXLMCommon.ModelContainer?

    func textContainer(for modelURL: URL) async throws -> MLXLMCommon.ModelContainer {
        if textPath == modelURL.path, let container = textContainer {
            return container
        }
        let configuration = ModelConfiguration(directory: modelURL)
        let container = try await LLMModelFactory.shared.loadContainer(configuration: configuration)
        textPath = modelURL.path
        textContainer = container
        return container
    }

    func visionContainer(for modelURL: URL) async throws -> MLXLMCommon.ModelContainer {
        if visionPath == modelURL.path, let container = visionContainer {
            return container
        }
        let configuration = ModelConfiguration(directory: modelURL)
        let container = try await VLMModelFactory.shared.loadContainer(configuration: configuration)
        visionPath = modelURL.path
        visionContainer = container
        return container
    }
}
#endif

/// Local MLX provider for text, vision, and image generation models.
///
/// Configuration:
/// - `model` should be a local folder path that contains MLX model assets.
///
/// Notes:
/// - This file compiles even if MLX isn't available. If missing, it throws a clear runtime error.
final class MLXHandler: APIService {

    let name: String
    let baseURL: URL
    let session: URLSession
    let model: String

    private let dataLoader = BackgroundDataLoader()
    #if canImport(MLX)
    private let containerCache = MLXContainerCache()
    #endif

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
            } catch let error as APIError {
                completion(.failure(error))
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
        AsyncThrowingStream { continuation in
            Task {
                do {
                    var streamedCharacterCount = 0
                    let full = try await self.sendMessage(
                        requestMessages,
                        tools: tools,
                        temperature: temperature,
                        onToken: { chunk in
                            guard !chunk.isEmpty else { return true }
                            streamedCharacterCount += chunk.count
                            continuation.yield((chunk, nil))
                            return true
                        }
                    )

                    if let full = full, full.count > streamedCharacterCount {
                        let remaining = String(full.dropFirst(streamedCharacterCount))
                        if !remaining.isEmpty {
                            continuation.yield((remaining, nil))
                        }
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
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
        throw APIError.noApiService("MLX provider does not use network requests")
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
        let content = try await sendMessage(requestMessages, tools: tools, temperature: temperature, onToken: nil)
        return (content, nil)
    }

    private func sendMessage(
        _ requestMessages: [[String: String]],
        tools: [[String: Any]]?,
        temperature: Float,
        onToken: ((String) -> Bool)?
    ) async throws -> String? {
        #if !canImport(MLX)
        throw APIError.noApiService(
            "MLX module not available. Add the Apple MLX Swift packages and link them to the Warden target."
        )
        #else
        _ = tools

        let modelPath = resolveModelPath(model)
        guard !modelPath.isEmpty else {
            throw APIError.decodingFailed("No MLX model path provided")
        }

        return try await SecurityScopedBookmarkStore.withAccess(path: modelPath) {
            let modelURL = URL(fileURLWithPath: modelPath)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: modelURL.path, isDirectory: &isDirectory),
                  isDirectory.boolValue
            else {
                throw APIError.serverError("MLX model folder not found: \(modelURL.path)")
            }

            let rawPrompt = extractPrompt(from: requestMessages)
            guard !rawPrompt.isEmpty else {
                throw APIError.decodingFailed("No user prompt found")
            }

            let extraction = extractImageInputs(from: rawPrompt)
            let prompt = extraction.prompt
            let imageData = extraction.imageData

            #if canImport(FluxSwift)
            if let fluxInfo = findFluxModelInfo(at: modelURL) {
                return try await generateFluxImage(
                    prompt: prompt,
                    modelInfo: fluxInfo,
                    imageData: imageData
                )
            }
            #endif

            if let stableDiffusionRoot = findStableDiffusionRoot(at: modelURL) {
                return try await generateImage(prompt: prompt, modelURL: stableDiffusionRoot)
            }

            if !imageData.isEmpty {
                return try await generateVision(prompt: prompt, imageData: imageData, temperature: temperature, onToken: onToken)
            }

            return try await generateText(prompt: prompt, temperature: temperature, onToken: onToken)
        }
        #endif
    }

    private func extractPrompt(from requestMessages: [[String: String]]) -> String {
        for msg in requestMessages.reversed() {
            if (msg["role"] ?? "").lowercased() == "user" {
                return msg["content"] ?? ""
            }
        }
        return requestMessages.last?["content"] ?? ""
    }

    private func resolveModelPath(_ rawPath: String) -> String {
        let first = rawPath
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

    private func extractImageInputs(from content: String) -> (prompt: String, imageData: [Data]) {
        let imagePattern = "<image-uuid>(.*?)</image-uuid>"
        let filePattern = "<file-uuid>(.*?)</file-uuid>"
        let dataUrlPattern = "data:image/[^;]+;base64,([A-Za-z0-9+\\/=]+)"

        var images: [Data] = []
        var cleaned = content

        if let regex = try? NSRegularExpression(pattern: imagePattern, options: []) {
            let nsString = cleaned as NSString
            let matches = regex.matches(in: cleaned, options: [], range: NSRange(location: 0, length: nsString.length))
            for match in matches {
                if match.numberOfRanges > 1 {
                    let uuidString = nsString.substring(with: match.range(at: 1))
                    if let uuid = UUID(uuidString: uuidString), let data = dataLoader.loadImageData(uuid: uuid) {
                        images.append(data)
                    }
                }
            }
            cleaned = regex.stringByReplacingMatches(
                in: cleaned,
                options: [],
                range: NSRange(location: 0, length: nsString.length),
                withTemplate: ""
            )
        }

        if let regex = try? NSRegularExpression(pattern: filePattern, options: []) {
            let nsString = cleaned as NSString
            let matches = regex.matches(in: cleaned, options: [], range: NSRange(location: 0, length: nsString.length))
            for match in matches {
                if match.numberOfRanges > 1 {
                    let uuidString = nsString.substring(with: match.range(at: 1))
                    if let uuid = UUID(uuidString: uuidString),
                       let data = dataLoader.loadFileImageData(uuid: uuid),
                       !data.isEmpty {
                        images.append(data)
                    }
                }
            }
            cleaned = regex.stringByReplacingMatches(
                in: cleaned,
                options: [],
                range: NSRange(location: 0, length: nsString.length),
                withTemplate: ""
            )
        }

        if let regex = try? NSRegularExpression(pattern: dataUrlPattern, options: []) {
            let nsString = cleaned as NSString
            let matches = regex.matches(in: cleaned, options: [], range: NSRange(location: 0, length: nsString.length))
            for match in matches {
                if match.numberOfRanges > 1 {
                    let base64String = nsString.substring(with: match.range(at: 1))
                    if let data = Data(base64Encoded: base64String) {
                        images.append(data)
                    }
                }
            }
            cleaned = regex.stringByReplacingMatches(
                in: cleaned,
                options: [],
                range: NSRange(location: 0, length: nsString.length),
                withTemplate: ""
            )
        }

        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        return (cleaned, images)
    }

    private func findStableDiffusionRoot(at url: URL) -> URL? {
        let fm = FileManager.default
        let maxDepth = 2
        var queue: [(url: URL, depth: Int)] = [(url, 0)]

        while !queue.isEmpty {
            let current = queue.removeFirst()
            if isStableDiffusionRoot(current.url) {
                return current.url
            }
            guard current.depth < maxDepth else { continue }
            if let children = try? fm.contentsOfDirectory(
                at: current.url,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) {
                for child in children {
                    if (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                        queue.append((child, current.depth + 1))
                    }
                }
            }
        }
        return nil
    }

    private func isStableDiffusionRoot(_ url: URL) -> Bool {
        missingStableDiffusionComponents(at: url).isEmpty
    }

    private func missingStableDiffusionComponents(at url: URL) -> [String] {
        let fm = FileManager.default
        let requiredPaths = [
            "unet/config.json",
            "vae/config.json",
            "scheduler/scheduler_config.json",
            "tokenizer/vocab.json"
        ]
        let encoderPaths = [
            "text_encoder/config.json",
            "text_encoder_2/config.json"
        ]

        var missing: [String] = []
        for path in requiredPaths {
            if !fm.fileExists(atPath: url.appendingPathComponent(path).path) {
                missing.append(path)
            }
        }

        let hasEncoder = encoderPaths.contains { fm.fileExists(atPath: url.appendingPathComponent($0).path) }
        if !hasEncoder {
            missing.append("text_encoder/config.json")
        }

        return missing
    }

    private func imageExtension(from data: Data, fallback: String = "png") -> String {
        if data.count >= 8 {
            let pngSignature: [UInt8] = [0x89, 0x50, 0x4E, 0x47]
            let jpgSignature: [UInt8] = [0xFF, 0xD8]
            let gifSignature: [UInt8] = [0x47, 0x49, 0x46]
            let riffSignature: [UInt8] = [0x52, 0x49, 0x46, 0x46]

            let bytes = [UInt8](data.prefix(12))
            if bytes.starts(with: pngSignature) { return "png" }
            if bytes.starts(with: jpgSignature) { return "jpg" }
            if bytes.starts(with: gifSignature) { return "gif" }
            if bytes.starts(with: riffSignature), bytes.count >= 12 {
                let webp = bytes[8...11] == [0x57, 0x45, 0x42, 0x50]
                if webp { return "webp" }
            }
        }
        return fallback
    }

    func writeTempImageFile(data: Data) throws -> URL {
        let ext = imageExtension(from: data)
        let filename = "mlx_image_\(UUID().uuidString).\(ext)"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try data.write(to: url)
        return url
    }

    #if canImport(MLX)
    private func loadTextContainer(modelURL: URL) async throws -> MLXLMCommon.ModelContainer {
        return try await containerCache.textContainer(for: modelURL)
    }

    private func loadVisionContainer(modelURL: URL) async throws -> MLXLMCommon.ModelContainer {
        return try await containerCache.visionContainer(for: modelURL)
    }

    private func generateText(
        prompt: String,
        temperature: Float,
        onToken: ((String) -> Bool)?
    ) async throws -> String {
        let container = try await loadTextContainer(modelURL: URL(fileURLWithPath: model))
        let parameters = GenerateParameters(temperature: temperature)

        let input = try await container.prepare(input: UserInput(prompt: prompt))
        let stream = try await container.generate(input: input, parameters: parameters)
        var streamedOutput = ""

        for await generation in stream {
            guard let chunk = generation.chunk, !chunk.isEmpty else { continue }
            streamedOutput.append(contentsOf: chunk)
            if let onToken, !onToken(chunk) {
                break
            }
        }

        return streamedOutput
    }

    private func generateVision(
        prompt: String,
        imageData: [Data],
        temperature: Float,
        onToken: ((String) -> Bool)?
    ) async throws -> String {
        let container = try await loadVisionContainer(modelURL: URL(fileURLWithPath: model))
        let parameters = GenerateParameters(temperature: temperature)

        var images: [UserInput.Image] = []
        for data in imageData {
            let url = try writeTempImageFile(data: data)
            images.append(.url(url))
        }

        let imagesCopy = images
        let input = try await container.prepare(
            input: UserInput(prompt: prompt, images: imagesCopy)
        )
        let stream = try await container.generate(input: input, parameters: parameters)
        var streamedOutput = ""

        for await generation in stream {
            guard let chunk = generation.chunk, !chunk.isEmpty else { continue }
            streamedOutput.append(contentsOf: chunk)
            if let onToken, !onToken(chunk) {
                break
            }
        }

        return streamedOutput
    }
    #endif

    private func generateImage(prompt: String, modelURL: URL) async throws -> String {
        #if !canImport(StableDiffusion)
        throw APIError.noApiService(
            "StableDiffusion module not available. Add the mlx-swift-examples StableDiffusion product to the Warden target."
        )
        #else
        let missing = missingStableDiffusionComponents(at: modelURL)
        if !missing.isEmpty {
            let missingList = missing.prefix(4).joined(separator: ", ")
            throw APIError.serverError(
                "MLX image model is missing required files. Expected under \(modelURL.path): \(missingList)"
            )
        }
        let configuration = stableDiffusionConfiguration(for: modelURL)
        try prepareStableDiffusionCache(configuration: configuration, modelURL: modelURL)

        let container = try ModelContainer<TextToImageGenerator>.createTextToImageGenerator(
            configuration: configuration,
            loadConfiguration: LoadConfiguration()
        )
        await container.setConserveMemory(false)

        let decoded = try await container.performTwoStage { generator in
            var parameters = configuration.defaultParameters()
            parameters.prompt = prompt
            parameters.negativePrompt = ""
            let latents = generator.generateLatents(parameters: parameters)
            return (generator.detachedDecoder(), latents)
        } second: { decoder, latents in
            var lastXt: MLXArray?
            for xt in latents {
                eval(xt)
                lastXt = xt
            }
            guard let lastXt = lastXt else {
                throw APIError.serverError("No latents generated")
            }
            let decoded = decoder(lastXt)
            eval(decoded)
            return decoded
        }

        let raster = (decoded * 255).asType(.uint8).squeezed()
        let cgImage = Image(raster).asCGImage()
        let png = try pngData(from: cgImage)
        let b64 = png.base64EncodedString()
        return "<image-url>data:image/png;base64,\(b64)</image-url>"
        #endif
    }

    #if canImport(StableDiffusion)
    private func stableDiffusionConfiguration(for modelURL: URL) -> StableDiffusionConfiguration {
        let hasSDXL = FileManager.default.fileExists(atPath: modelURL.appendingPathComponent("text_encoder_2").path)
            || FileManager.default.fileExists(atPath: modelURL.appendingPathComponent("tokenizer_2").path)
        return hasSDXL
            ? StableDiffusionConfiguration.presetSDXLTurbo
            : StableDiffusionConfiguration.presetStableDiffusion21Base
    }

    private func prepareStableDiffusionCache(
        configuration: StableDiffusionConfiguration,
        modelURL: URL
    ) throws {
        let hub = HubApi()
        let repo = Hub.Repo(id: configuration.id)
        let cacheURL = hub.localRepoLocation(repo)

        let fm = FileManager.default
        let cacheParent = cacheURL.deletingLastPathComponent()
        if !fm.fileExists(atPath: cacheParent.path) {
            try fm.createDirectory(at: cacheParent, withIntermediateDirectories: true)
        }

        if fm.fileExists(atPath: cacheURL.path) {
            var shouldReplace = true
            if let attrs = try? fm.attributesOfItem(atPath: cacheURL.path),
               let type = attrs[.type] as? FileAttributeType,
               type == .typeSymbolicLink,
               let destination = try? fm.destinationOfSymbolicLink(atPath: cacheURL.path),
               destination == modelURL.path {
                shouldReplace = false
            }

            if shouldReplace {
                try fm.removeItem(at: cacheURL)
            } else {
                return
            }
        } else if (try? fm.destinationOfSymbolicLink(atPath: cacheURL.path)) != nil {
            // Broken symlink still occupies the path but fileExists() returns false.
            try fm.removeItem(at: cacheURL)
        }
        do {
            try fm.createSymbolicLink(at: cacheURL, withDestinationURL: modelURL)
        } catch {
            let nsError = error as NSError
            if nsError.code == NSFileWriteFileExistsError {
                try fm.removeItem(at: cacheURL)
                try fm.createSymbolicLink(at: cacheURL, withDestinationURL: modelURL)
            } else {
                throw error
            }
        }
    }
    #endif

    func pngData(from cgImage: CGImage) throws -> Data {
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw APIError.decodingFailed("Failed to encode PNG")
        }
        return data
    }

}
