import Foundation

// MARK: - Gemini (Google AI Studio) REST API
// This handler targets the native Gemini REST endpoints:
//   POST https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key=...
//   POST https://generativelanguage.googleapis.com/v1beta/models/{model}:streamGenerateContent?alt=sse&key=...
//
// Warden's AppConstants historically used an OpenAI-compatible URL for Gemini.
// We intentionally ignore the exact path of `baseURL` and only reuse scheme+host+version.

private struct GeminiModelsResponse: Codable {
    let models: [GeminiModel]
}

private struct GeminiModel: Codable {
    let name: String
    var id: String { name.replacingOccurrences(of: "models/", with: "") }
}

final class GeminiHandler: BaseAPIHandler {
    private let dataLoader = BackgroundDataLoader()

    // MARK: Models

    override func fetchModels() async throws -> [AIModel] {
        // GET /v1beta/models?key=...
        let url = try geminiEndpoint(path: "/models", model: nil, stream: false)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        do {
            let (data, response) = try await session.data(for: request)
            let result = handleAPIResponse(response, data: data, error: nil)
            switch result {
            case .success(let responseData):
                guard let responseData else { throw APIError.invalidResponse }
                let decoded = try JSONDecoder().decode(GeminiModelsResponse.self, from: responseData)
                return decoded.models.map { AIModel(id: $0.id) }
            case .failure(let error):
                throw error
            }
        } catch let e as APIError {
            throw e
        } catch {
            throw APIError.requestFailed(error)
        }
    }

    // MARK: Requests

    override func prepareRequest(
        requestMessages: [[String: String]],
        tools: [[String: Any]]?,
        model: String,
        temperature: Float,
        stream: Bool
    ) throws -> URLRequest {
        // NOTE: Gemini does not (yet) use Warden's tool schema here.
        _ = tools

        let url = try geminiEndpoint(path: "/models", model: model, stream: stream)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Extract special markers
        let imageUUIDPattern = "<image-([a-fA-F0-9-]+)>"
        let fileUUIDPattern = "<file-([a-fA-F0-9-]+)>"

        func mapRole(_ role: String) -> String {
            switch role.lowercased() {
            case "assistant": return "model"
            case "system": return "user" // system is handled separately via systemInstruction
            default: return "user"
            }
        }

        // System instruction: Gemini supports `systemInstruction` (v1beta)
        let systemText = requestMessages
            .filter { ($0["role"] ?? "").lowercased() == "system" }
            .compactMap { $0["content"] }
            .joined(separator: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        var contents: [[String: Any]] = []

        for message in requestMessages {
            let rawRole = (message["role"] ?? "user").lowercased()
            if rawRole == "system" { continue }
            guard var text = message["content"] else { continue }

            let role = mapRole(rawRole)

            // Extract UUIDs
            let imageUUIDs: [String] = Self.extractUUIDs(from: text, pattern: imageUUIDPattern)
            let fileUUIDs: [String] = Self.extractUUIDs(from: text, pattern: fileUUIDPattern)

            // Strip markers from text
            text = Self.stripMarkers(from: text, patterns: [imageUUIDPattern, fileUUIDPattern])

            var parts: [[String: Any]] = []

            // Expand file markers into text parts
            for uuidString in fileUUIDs {
                if let uuid = UUID(uuidString: uuidString),
                   let fileContent = try? dataLoader.loadFileContent(uuid: uuid)
                {
                    parts.append(["text": fileContent])
                }
            }

            // Add remaining text
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                parts.append(["text": trimmed])
            }

            // Expand image markers into inlineData parts
            for uuidString in imageUUIDs {
                if let uuid = UUID(uuidString: uuidString),
                   let imageData = dataLoader.loadImageData(uuid: uuid)
                {
                    parts.append([
                        "inlineData": [
                            // Best-effort: Warden currently stores JPEGs for attachments.
                            "mimeType": "image/jpeg",
                            "data": imageData.base64EncodedString()
                        ]
                    ])
                }
            }

            if !parts.isEmpty {
                contents.append([
                    "role": role,
                    "parts": parts
                ])
            }
        }

        // If everything was system-only, Gemini still needs at least one content.
        if contents.isEmpty {
            contents = [[
                "role": "user",
                "parts": [["text": "(no content)"]]
            ]]
        }

        var body: [String: Any] = [
            "contents": contents,
            "generationConfig": [
                "temperature": temperature
            ]
        ]

        if !systemText.isEmpty {
            body["systemInstruction"] = [
                "parts": [["text": systemText]]
            ]
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        return request
    }

    // MARK: Response parsing

    override func parseJSONResponse(data: Data) -> (String?, String?, [ToolCall]?)? {
        // Expected shape:
        // { "candidates": [ { "content": { "parts": [ {"text":"..."} | {"inlineData":{...}} ] } } ] }
        do {
            let json = try JSONSerialization.jsonObject(with: data, options: [])
            guard let root = json as? [String: Any] else { return nil }
            if let error = root["error"] as? [String: Any],
               let message = error["message"] as? String
            {
                return ("Gemini error: \(message)", "assistant", nil)
            }

            guard let candidates = root["candidates"] as? [[String: Any]],
                  let first = candidates.first
            else { return nil }

            guard let content = first["content"] as? [String: Any],
                  let parts = content["parts"] as? [[String: Any]]
            else { return nil }

            let rendered = Self.renderParts(parts)
            return (rendered, "assistant", nil)
        } catch {
            return nil
        }
    }

    override func parseDeltaJSONResponse(data: Data?) -> (Bool, Error?, String?, String?, [ToolCall]?) {
        // Gemini SSE events deliver JSON payloads similar to the non-streaming response,
        // and typically include incremental `candidates[0].content.parts`.
        guard let data else {
            return (true, APIError.decodingFailed("No data for delta"), nil, nil, nil)
        }

        do {
            // Some servers may send a terminal marker; be tolerant.
            if let s = String(data: data, encoding: .utf8), s.trimmingCharacters(in: .whitespacesAndNewlines) == "[DONE]" {
                return (true, nil, nil, nil, nil)
            }

            let obj = try JSONSerialization.jsonObject(with: data, options: [])
            guard let root = obj as? [String: Any] else { return (false, nil, nil, nil, nil) }

            if let error = root["error"] as? [String: Any],
               let message = error["message"] as? String
            {
                return (true, APIError.serverError(message), nil, nil, nil)
            }

            guard let candidates = root["candidates"] as? [[String: Any]],
                  let first = candidates.first
            else {
                // Not finished, but nothing to yield.
                return (false, nil, nil, nil, nil)
            }

            var finished = false
            if let finishReason = first["finishReason"] as? String, !finishReason.isEmpty {
                finished = true
            }
            if let finishReason = first["finish_reason"] as? String, !finishReason.isEmpty {
                finished = true
            }

            if let content = first["content"] as? [String: Any],
               let parts = content["parts"] as? [[String: Any]]
            {
                let rendered = Self.renderParts(parts)
                // If it's an image, we still send it as a chunk.
                if rendered.isEmpty {
                    return (finished, nil, nil, nil, nil)
                }
                return (finished, nil, rendered, "assistant", nil)
            }

            return (finished, nil, nil, nil, nil)
        } catch {
            return (false, APIError.decodingFailed("Gemini delta parse failed: \(error.localizedDescription)"), nil, nil, nil)
        }
    }
}

// MARK: - Helpers

private extension GeminiHandler {
    /// Build a Gemini endpoint by reusing scheme/host/version from `baseURL`.
    /// - If `model != nil`, returns :generateContent or :streamGenerateContent.
    /// - If `model == nil`, returns `/models` for listing.
    func geminiEndpoint(path: String, model: String?, stream: Bool) throws -> URL {
        // baseURL is expected to be something like:
        // https://generativelanguage.googleapis.com/v1beta/chat/completions
        // We'll keep scheme+host+firstPathComponent (v1beta).
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: true) else {
            throw APIError.unknown("Invalid base URL")
        }

        let version: String = {
            let comps = baseURL.path.split(separator: "/")
            return comps.first.map(String.init) ?? "v1beta"
        }()

        var endpointPath: String
        if let model {
            let method = stream ? "streamGenerateContent" : "generateContent"
            endpointPath = "/\(version)/models/\(model):\(method)"
        } else {
            endpointPath = "/\(version)\(path)"
        }

        components.path = endpointPath

        var items = components.queryItems ?? []
        if !items.contains(where: { $0.name == "key" }) {
            items.append(URLQueryItem(name: "key", value: apiKey))
        }
        if stream {
            // Required for SSE streaming responses
            if !items.contains(where: { $0.name == "alt" }) {
                items.append(URLQueryItem(name: "alt", value: "sse"))
            }
        }
        components.queryItems = items

        guard let url = components.url else {
            throw APIError.unknown("Invalid Gemini endpoint URL")
        }
        return url
    }

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

    static func renderParts(_ parts: [[String: Any]]) -> String {
        var textParts: [String] = []
        var inlineData: (mime: String, data: String)? = nil

        for part in parts {
            if let text = part["text"] as? String {
                textParts.append(text)
            } else if let inline = part["inlineData"] as? [String: Any],
                      let dataString = inline["data"] as? String
            {
                let mime = (inline["mimeType"] as? String) ?? "image/png"
                inlineData = (mime: mime, data: dataString)
            }
        }

        if !textParts.isEmpty {
            return textParts.joined()
        }

        if let inlineData {
            return "<image-url>data:\(inlineData.mime);base64,\(inlineData.data)</image-url>"
        }

        return ""
    }
}
