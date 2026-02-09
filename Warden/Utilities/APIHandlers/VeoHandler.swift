import Foundation
import os

/// Google Veo video-generation handler for the Generative Language API (v1beta).
///
/// Final REST flow (as validated with curl):
/// 1) Start long-running prediction
///    POST /v1beta/models/{model}:predictLongRunning
///    Headers: x-goog-api-key: ...
///    Body: { "instances": [ { "prompt": "..." } ] }
///    Response: { "name": "models/{model}/operations/{id}" }
///
/// 2) Poll operation until done
///    GET /v1beta/{name}
///    Headers: x-goog-api-key: ...
///
/// 3) Download the mp4 bytes
///    GET https://generativelanguage.googleapis.com/v1beta/files/{file}:download?alt=media
///    Headers: x-goog-api-key: ...
///
/// Notes:
/// - No streaming; `sendMessageStream` yields once.
/// - We use header-based API key auth (x-goog-api-key), not `?key=` query items.
final class VeoHandler: BaseAPIHandler {
    private let dataLoader = BackgroundDataLoader()
    private let logger = Logger(subsystem: "Warden", category: "VeoHandler")

    #if DEBUG
    private func debugLogRequest(_ request: URLRequest) {
        let method = request.httpMethod ?? "<no method>"
        let url = request.url?.absoluteString ?? "<no url>"

        var headerSummary: [String] = []
        if let headers = request.allHTTPHeaderFields {
            for (k, v) in headers.sorted(by: { $0.key.lowercased() < $1.key.lowercased() }) {
                // Avoid leaking secrets into logs
                if k.lowercased() == "authorization" || k.lowercased() == "x-goog-api-key" {
                    headerSummary.append("\(k): <redacted>")
                } else {
                    headerSummary.append("\(k): \(v)")
                }
            }
        }

        let bodyBytes = request.httpBody?.count ?? 0
        logger.debug("VEO request → \(method, privacy: .public) \(url, privacy: .public) headers=[\(headerSummary.joined(separator: ", "), privacy: .public)] bodyBytes=\(bodyBytes, privacy: .public)")
    }

    private func debugLogResponse(_ response: URLResponse?, data: Data?) {
        guard let http = response as? HTTPURLResponse else {
            logger.debug("VEO response ← <non-http response>")
            return
        }

        let url = http.url?.absoluteString ?? "<no url>"
        let status = http.statusCode
        let bytes = data?.count ?? 0

        let wanted = [
            "x-request-id",
            "x-trace-id",
            "traceparent",
            "request-id",
            "cf-ray",
            "server",
            "via"
        ]
        var picked: [String] = []
        for key in wanted {
            if let v = http.allHeaderFields.first(where: { (k, _) in
                String(describing: k).lowercased() == key
            })?.value {
                picked.append("\(key): \(v)")
            }
        }

        if (200...299).contains(status) {
            logger.debug("VEO response ← HTTP \(status, privacy: .public) \(url, privacy: .public) bytes=\(bytes, privacy: .public)")
        } else {
            logger.error("VEO response ← HTTP \(status, privacy: .public) \(url, privacy: .public) bytes=\(bytes, privacy: .public) headers=[\(picked.joined(separator: ", "), privacy: .public)]")
        }
    }
    #endif

    // MARK: - APIService

    override func sendMessage(
        _ requestMessages: [[String: String]],
        tools: [[String : Any]]? = nil,
        temperature: Float,
        completion: @escaping (Result<(String?, [ToolCall]?), APIError>) -> Void
    ) {
        Task {
            do {
                let (content, toolCalls) = try await self.generateVideo(requestMessages: requestMessages)
                completion(.success((content, toolCalls)))
            } catch let e as APIError {
                completion(.failure(e))
            } catch {
                completion(.failure(.unknown(error.localizedDescription)))
            }
        }
    }

    override func sendMessageStream(
        _ requestMessages: [[String : String]],
        tools: [[String : Any]]? = nil,
        temperature: Float
    ) async throws -> AsyncThrowingStream<(String?, [ToolCall]?), Error> {
        let (content, toolCalls) = try await self.generateVideo(requestMessages: requestMessages)
        return AsyncThrowingStream { continuation in
            continuation.yield((content, toolCalls))
            continuation.finish()
        }
    }

    // MARK: - Core

    private func generateVideo(requestMessages: [[String: String]]) async throws -> (String?, [ToolCall]?) {
        let prompt = extractPrompt(from: requestMessages)
        if prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw APIError.decodingFailed("No prompt provided for video generation")
        }

        // Extract optional hidden Veo parameters tag (appended by the UI to the API payload only).
        let (promptWithoutParams, veoParams) = Self.extractVeoParameters(from: prompt)

        // Extract images in order; currently unused for this REST shape.
        // (Kept so prompts containing <image-UUID> markers are cleaned.)
        let imageUUIDPattern = "<image-([a-fA-F0-9-]+)>"
        _ = Self.extractUUIDs(from: promptWithoutParams, pattern: imageUUIDPattern)
        let cleanedPrompt = Self.stripMarkers(from: promptWithoutParams, patterns: [imageUUIDPattern])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Hardening: Veo model ids used here are typically like "veo-3.1-generate-preview".
        let veoModel: String = {
            if model.contains("-generate-") { return model }
            if model.hasSuffix("-generate-preview") { return model }
            return "\(model)-generate-preview"
        }()

        // 1) Start operation: POST :predictLongRunning
        let startURL = try veoEndpoint(model: veoModel, kind: .predictLongRunning)
        var startReq = URLRequest(url: startURL)
        startReq.httpMethod = "POST"
        startReq.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        startReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var payload: [String: Any] = [
            "instances": [
                ["prompt": cleanedPrompt]
            ]
        ]

        if let veoParams {
            payload["parameters"] = [
                "aspectRatio": veoParams.aspectRatio,
                "durationSeconds": veoParams.durationSeconds,
                "negativePrompt": veoParams.negativePrompt
            ]
        }

        startReq.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        #if DEBUG
        debugLogRequest(startReq)
        #endif

        let (startData, startResp) = try await session.data(for: startReq)

        #if DEBUG
        debugLogResponse(startResp, data: startData)
        #endif

        switch handleAPIResponse(startResp, data: startData, error: nil) {
        case .failure(let e):
            throw e
        case .success(let okData):
            guard let okData else { throw APIError.invalidResponse }
            let start = try Self.decodeStart(from: okData)
            let completed = try await pollOperation(name: start.name, veoModel: veoModel)
            let videoURI = try Self.extractFirstVideoURI(from: completed)
            let fileURL = try await downloadVideoToFile(videoURI: videoURI)
            return ("<video-url>\(fileURL.absoluteString)</video-url>", nil)
        }
    }

    // MARK: - Operations

    private enum VeoCallKind {
        case predictLongRunning
        case getOperation(name: String)
    }

    private func pollOperation(name: String, veoModel: String) async throws -> VeoOperation {
        var opName = name
        if opName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw APIError.decodingFailed("Veo operation missing name")
        }

        // Poll every 5 seconds as requested.
        let delayNs: UInt64 = 15 * 1_000_000_000

        while true {
            let url = try veoEndpoint(model: veoModel, kind: .getOperation(name: opName))
            var req = URLRequest(url: url)
            req.httpMethod = "GET"
            req.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")

            #if DEBUG
            debugLogRequest(req)
            #endif

            let (data, resp) = try await session.data(for: req)

            #if DEBUG
            debugLogResponse(resp, data: data)
            #endif

            switch handleAPIResponse(resp, data: data, error: nil) {
            case .failure(let e):
                throw e
            case .success(let okData):
                guard let okData else { throw APIError.invalidResponse }
                let op = try Self.decodeOperation(from: okData)

                if op.done == true {
                    if let err = op.error {
                        let msg = err.message ?? "Unknown operation error"
                        throw APIError.serverError("Veo operation failed: \(msg)")
                    }
                    return op
                }
            }

            try await Task.sleep(nanoseconds: delayNs)
        }
    }

    // MARK: - Download

    private func downloadVideoToFile(videoURI: String) async throws -> URL {
        guard let url = URL(string: videoURI) else {
            throw APIError.unknown("Invalid video URI")
        }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")

        #if DEBUG
        debugLogRequest(req)
        #endif

        let (data, resp) = try await session.data(for: req)

        #if DEBUG
        debugLogResponse(resp, data: data)
        #endif

        switch handleAPIResponse(resp, data: data, error: nil) {
        case .failure(let e):
            throw e
        case .success(let okData):
            guard let okData else { throw APIError.invalidResponse }
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("WardenVideos", isDirectory: true)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

            let filename = "veo-\(UUID().uuidString).mp4"
            let fileURL = folder.appendingPathComponent(filename)
            try okData.write(to: fileURL, options: .atomic)
            return fileURL
        }
    }

    // MARK: - URL building

    private func veoEndpoint(model: String, kind: VeoCallKind) throws -> URL {
        // Based on the validated curl examples.
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: true) else {
            throw APIError.unknown("Invalid base URL")
        }

        let version: String = {
            let comps = baseURL.path.split(separator: "/")
            return comps.first.map(String.init) ?? "v1beta"
        }()

        switch kind {
        case .predictLongRunning:
            components.path = "/\(version)/models/\(model):predictLongRunning"
        case .getOperation(let name):
            // name is like: models/{model}/operations/{id}
            components.path = "/\(version)/\(name)"
        }

        guard let url = components.url else {
            throw APIError.unknown("Invalid Veo endpoint URL")
        }
        return url
    }

    // MARK: - Prompt helpers

    private func extractPrompt(from requestMessages: [[String: String]]) -> String {
        for msg in requestMessages.reversed() {
            if (msg["role"] ?? "").lowercased() == "user" {
                return msg["content"] ?? ""
            }
        }
        return requestMessages.last?["content"] ?? ""
    }

    // MARK: - JSON decoding

    private struct VeoStart: Codable {
        let name: String
    }

    private struct VeoOperation: Codable {
        struct OpError: Codable {
            let message: String?
        }

        struct OperationResponse: Codable {
            let type: String?
            let generateVideoResponse: GenerateVideoResponse?

            enum CodingKeys: String, CodingKey {
                case type = "@type"
                case generateVideoResponse
            }
        }

        struct GenerateVideoResponse: Codable {
            let generatedSamples: [GeneratedSample]?
        }

        struct GeneratedSample: Codable {
            let video: VideoObj?
        }

        struct VideoObj: Codable {
            let uri: String?
        }

        var name: String?
        var done: Bool?
        var error: OpError?
        var response: OperationResponse?

        // Best-effort fallback parsing
        var fallbackURI: String?

        enum CodingKeys: String, CodingKey {
            case name, done, error, response
        }
    }

    private static func decodeStart(from data: Data) throws -> VeoStart {
        do {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return try decoder.decode(VeoStart.self, from: data)
        } catch {
            let preview = String(data: data, encoding: .utf8) ?? "<non-utf8>"
            throw APIError.decodingFailed("Failed to decode Veo start response: \(error.localizedDescription). Body: \(String(preview.prefix(600)))")
        }
    }

    private static func decodeOperation(from data: Data) throws -> VeoOperation {
        do {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            var op = try decoder.decode(VeoOperation.self, from: data)

            if let json = try? JSONSerialization.jsonObject(with: data, options: []),
               let uri = Self.findFirstURI(in: json)
            {
                op.fallbackURI = uri
            }

            return op
        } catch {
            let preview = String(data: data, encoding: .utf8) ?? "<non-utf8>"
            throw APIError.decodingFailed("Failed to decode Veo operation: \(error.localizedDescription). Body: \(String(preview.prefix(600)))")
        }
    }

    private static func extractFirstVideoURI(from op: VeoOperation) throws -> String {
        if let uri = op.response?.generateVideoResponse?.generatedSamples?.first?.video?.uri,
           !uri.isEmpty {
            return uri
        }
        if let uri = op.fallbackURI, !uri.isEmpty {
            return uri
        }
        throw APIError.decodingFailed("Veo completed but no video URI found")
    }

    // MARK: - Veo parameters helpers

    private struct VeoParametersPayload: Codable {
        let aspectRatio: String
        let durationSeconds: Int
        let negativePrompt: String
    }

    private static func extractVeoParameters(from prompt: String) -> (String, VeoParametersPayload?) {
        let startTag = "<veo-parameters>"
        let endTag = "</veo-parameters>"

        guard let start = prompt.range(of: startTag),
              let end = prompt.range(of: endTag, range: start.upperBound..<prompt.endIndex)
        else {
            return (prompt, nil)
        }

        let jsonRange = start.upperBound..<end.lowerBound
        let jsonString = String(prompt[jsonRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        let cleaned = (prompt[..<start.lowerBound] + prompt[end.upperBound...])

        guard let data = jsonString.data(using: .utf8) else {
            return (String(cleaned), nil)
        }
        do {
            let decoded = try JSONDecoder().decode(VeoParametersPayload.self, from: data)
            // Clamp duration to expected server range.
            let clamped = VeoParametersPayload(
                aspectRatio: decoded.aspectRatio,
                durationSeconds: min(max(decoded.durationSeconds, 4), 10),
                negativePrompt: decoded.negativePrompt
            )
            return (String(cleaned), clamped)
        } catch {
            // Don't fail the whole request if params can't be decoded.
            return (String(cleaned), nil)
        }
    }

    // MARK: - JSON helpers

    private static func findFirstURI(in json: Any) -> String? {
        if let dict = json as? [String: Any] {
            if let uri = dict["uri"] as? String, !uri.isEmpty {
                return uri
            }
            for v in dict.values {
                if let found = findFirstURI(in: v) { return found }
            }
            return nil
        }
        if let arr = json as? [Any] {
            for v in arr {
                if let found = findFirstURI(in: v) { return found }
            }
            return nil
        }
        return nil
    }

    // MARK: - Regex helpers

    static func extractUUIDs(from text: String, pattern: String) -> [String] {
        do {
            let regex = try NSRegularExpression(pattern: pattern, options: [])
            let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count))
            return matches.compactMap { match in
                guard match.numberOfRanges > 1,
                      let range = Range(match.range(at: 1), in: text)
                else { return nil }
                return String(text[range])
            }
        } catch {
            return []
        }
    }

    static func stripMarkers(from text: String, patterns: [String]) -> String {
        var t = text
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                t = regex.stringByReplacingMatches(
                    in: t,
                    options: [],
                    range: NSRange(location: 0, length: t.utf16.count),
                    withTemplate: ""
                )
            }
        }
        return t
    }
}
