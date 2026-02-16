import Foundation

#if canImport(FluxSwift)
import FluxSwift
import Hub
import MLX
import StableDiffusion

extension MLXHandler {
    enum FluxModelType: String {
        case schnell
        case dev
        case kontext
    }

    struct FluxModelInfo {
        let rootURL: URL
        let type: FluxModelType
        let isQuantized: Bool
    }

    struct FluxMetadata: Codable {
        let quantizationBits: Int?
        let groupSize: Int?
        let modelType: String?
        let fluxSwiftVersion: String?
        let createdAt: Date?
        let components: [String]?
    }

    func findFluxModelInfo(at url: URL) -> FluxModelInfo? {
        let fm = FileManager.default
        let maxDepth = 2
        var queue: [(url: URL, depth: Int)] = [(url, 0)]

        while !queue.isEmpty {
            let current = queue.removeFirst()
            let folderName = current.url.lastPathComponent
            let folderLooksFlux = folderName.lowercased().contains("flux")
            if let metadata = readFluxMetadata(at: current.url) {
                let modelTypeString = metadata.modelType ?? ""
                let metadataLooksFlux = modelTypeString.lowercased().contains("flux")
                if folderLooksFlux || metadataLooksFlux {
                    let type = inferFluxModelType(
                        metadataModelType: metadata.modelType,
                        folderName: folderName
                    )
                    return FluxModelInfo(rootURL: current.url, type: type, isQuantized: true)
                }
            }

            if isFluxModelRoot(current.url) && folderLooksFlux {
                let type = inferFluxModelType(metadataModelType: nil, folderName: current.url.lastPathComponent)
                return FluxModelInfo(rootURL: current.url, type: type, isQuantized: false)
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

    func generateFluxImage(
        prompt: String,
        modelInfo: FluxModelInfo,
        imageData: [Data]
    ) async throws -> String {
        let hub = HubApi()
        let loadConfiguration = FluxSwift.LoadConfiguration()

        let model: FLUX
        if modelInfo.isQuantized {
            model = try await FLUX.loadQuantized(
                from: modelInfo.rootURL.path,
                modelType: modelInfo.type.rawValue,
                hub: hub,
                configuration: loadConfiguration
            )
        } else {
            switch modelInfo.type {
            case .schnell:
                model = try Flux1Schnell(hub: hub, modelDirectory: modelInfo.rootURL)
            case .dev:
                model = try Flux1Dev(hub: hub, modelDirectory: modelInfo.rootURL)
            case .kontext:
                model = try Flux1KontextDev(hub: hub, modelDirectory: modelInfo.rootURL)
            }
        }

        if let kontext = model as? FluxSwift.KontextImageToImageGenerator, !imageData.isEmpty {
            return try await generateFluxKontextImage(
                prompt: prompt,
                generator: kontext,
                imageData: imageData[0]
            )
        }

        guard let generator = model as? FluxSwift.TextToImageGenerator else {
            throw APIError.serverError("Flux model does not support text-to-image generation")
        }

        let decoded = try generateFluxTextImage(
            prompt: prompt,
            generator: generator,
            modelType: modelInfo.type
        )
        let raster = (decoded * 255).asType(.uint8).squeezed()
        let cgImage = Image(raster).asCGImage()
        let png = try pngData(from: cgImage)
        let b64 = png.base64EncodedString()
        return "<image-url>data:image/png;base64,\(b64)</image-url>"
    }

    private func readFluxMetadata(at url: URL) -> FluxMetadata? {
        let candidates = ["metadata.json", "config.json", "model_config.json"]
        let fm = FileManager.default
        let metadataURL = candidates
            .map { url.appendingPathComponent($0) }
            .first(where: { fm.fileExists(atPath: $0.path) })
        guard let metadataURL else { return nil }
        guard let data = try? Data(contentsOf: metadataURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(FluxMetadata.self, from: data)
    }

    private func isFluxModelRoot(_ url: URL) -> Bool {
        let fm = FileManager.default
        let required = [
            "transformer",
            "vae",
            "text_encoder",
            "text_encoder_2"
        ]
        let hits = required.filter { fm.fileExists(atPath: url.appendingPathComponent($0).path) }
        return hits.count >= 3
    }

    private func inferFluxModelType(metadataModelType: String?, folderName: String) -> FluxModelType {
        let combined = ((metadataModelType ?? "") + " " + folderName).lowercased()
        if combined.contains("kontext") {
            return .kontext
        }
        if combined.contains("schnell") {
            return .schnell
        }
        if combined.contains("dev") {
            return .dev
        }
        if combined.contains("fluxpipeline") {
            return .dev
        }
        return .dev
    }

    private func generateFluxTextImage(
        prompt: String,
        generator: FluxSwift.TextToImageGenerator,
        modelType: FluxModelType
    ) throws -> MLXArray {
        let parameters = defaultFluxParameters(for: modelType)
        var params = parameters
        params.prompt = prompt

        var denoiser = generator.generateLatents(parameters: params)
        var lastXt: MLXArray?
        while let xt = denoiser.next() {
            eval(xt)
            lastXt = xt
        }

        guard let lastXt = lastXt else {
            throw APIError.serverError("No latents generated for Flux model")
        }

        let unpacked = unpackFluxLatents(lastXt, height: params.height, width: params.width)
        let decoded = generator.decode(xt: unpacked)
        eval(decoded)
        return decoded
    }

    private func generateFluxKontextImage(
        prompt: String,
        generator: FluxSwift.KontextImageToImageGenerator,
        imageData: Data
    ) async throws -> String {
        let tempURL = try writeTempImageFile(data: imageData)
        let inputImage = try Image(url: tempURL)
        let normalized = (inputImage.data.asType(MLX.DType.float32) / 255) * 2 - 1

        var params = defaultFluxParameters(for: .kontext)
        params.prompt = prompt

        var denoiser = generator.generateKontextLatents(image: normalized, parameters: params)
        var lastXt: MLXArray?
        while let xt = denoiser.next() {
            eval(xt)
            lastXt = xt
        }

        guard let lastXt = lastXt else {
            throw APIError.serverError("No latents generated for Flux Kontext model")
        }

        let unpacked = unpackFluxLatents(lastXt, height: params.height, width: params.width)
        let decoded = generator.decode(xt: unpacked)
        eval(decoded)

        let raster = (decoded * 255).asType(.uint8).squeezed()
        let cgImage = Image(raster).asCGImage()
        let png = try pngData(from: cgImage)
        let b64 = png.base64EncodedString()
        return "<image-url>data:image/png;base64,\(b64)</image-url>"
    }

    private func defaultFluxParameters(for modelType: FluxModelType) -> FluxSwift.EvaluateParameters {
        switch modelType {
        case .schnell:
            return FluxConfiguration.flux1Schnell.defaultParameters()
        case .dev:
            return FluxConfiguration.flux1Dev.defaultParameters()
        case .kontext:
            return FluxConfiguration.flux1KontextDev.defaultParameters()
        }
    }

    private func unpackFluxLatents(_ latents: MLXArray, height: Int, width: Int) -> MLXArray {
        let reshaped = latents.reshaped(1, height / 16, width / 16, 16, 2, 2)
        let transposed = reshaped.transposed(0, 1, 4, 2, 5, 3)
        return transposed.reshaped(1, height / 16 * 2, width / 16 * 2, 16)
    }
}
#endif
