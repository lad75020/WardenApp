import Foundation

private struct ModelResponse: Codable {
    let models: [Model]
}

private struct Model: Codable {
    let name: String
    
    var id: String {
        name.replacingOccurrences(of: "models/", with: "")
    }
}

class GeminiHandler: ChatGPTHandler {
    override func fetchModels() async throws -> [AIModel] {
        var urlComponents = URLComponents(url: baseURL.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("models"), resolvingAgainstBaseURL: true)
        urlComponents?.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        
        guard let modelsURL = urlComponents?.url else {
            throw APIError.unknown("Invalid URL")
        }

        var request = URLRequest(url: modelsURL)
        request.httpMethod = "GET"

        do {
            let (data, response) = try await session.data(for: request)

            let result = handleAPIResponse(response, data: data, error: nil)
            switch result {
            case .success(let responseData):
                guard let responseData = responseData else {
                    throw APIError.invalidResponse
                }

                let geminiResponse = try JSONDecoder().decode(ModelResponse.self, from: responseData)
                return geminiResponse.models.map { AIModel(id: $0.id) }

            case .failure(let error):
                throw error
            }
        }
        catch {
            throw APIError.requestFailed(error)
        }
    }

    override internal func prepareRequest(
        requestMessages: [[String: String]],
        tools: [[String: Any]]?,
        model: String,
        temperature: Float,
        stream: Bool
    ) throws -> URLRequest {
        // Build URL with key query item if missing
        var urlComponents = URLComponents(url: baseURL, resolvingAgainstBaseURL: true)
        var queryItems = urlComponents?.queryItems ?? []
        if !queryItems.contains(where: { $0.name == "key" }) {
            queryItems.append(URLQueryItem(name: "key", value: apiKey))
        }
        urlComponents?.queryItems = queryItems
        
        guard let requestURL = urlComponents?.url else {
            throw APIError.unknown("Invalid URL")
        }
        
        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // No Authorization header
        
        // Helper to map roles
        func mapRole(_ role: String) -> String {
            switch role.lowercased() {
            case "user":
                return "user"
            case "assistant":
                return "model"
            default:
                return "user"
            }
        }
        
        // Extract markers pattern
        // <image-uuid>... and <file-uuid>...
        let imageUUIDPattern = "<image-([a-fA-F0-9-]+)>"
        let fileUUIDPattern = "<file-([a-fA-F0-9-]+)>"
        
        var contents: [[String: Any]] = []
        
        for message in requestMessages {
            guard let content = message["content"] else { continue }
            let role = mapRole(message["role"] ?? "user")
            var text = content
            
            // Extract image UUIDs
            let imageUUIDs: [String] = {
                var uuids: [String] = []
                do {
                    let regex = try NSRegularExpression(pattern: imageUUIDPattern, options: [])
                    let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count))
                    for match in matches {
                        if match.numberOfRanges > 1,
                           let range = Range(match.range(at: 1), in: text) {
                            let uuid = String(text[range])
                            uuids.append(uuid)
                        }
                    }
                } catch {
                    // ignore malformed regex
                }
                return uuids
            }()
            
            // Extract file UUIDs
            let fileUUIDs: [String] = {
                var uuids: [String] = []
                do {
                    let regex = try NSRegularExpression(pattern: fileUUIDPattern, options: [])
                    let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count))
                    for match in matches {
                        if match.numberOfRanges > 1,
                           let range = Range(match.range(at: 1), in: text) {
                            let uuid = String(text[range])
                            uuids.append(uuid)
                        }
                    }
                } catch {
                    // ignore malformed regex
                }
                return uuids
            }()
            
            // Remove all markers from text
            do {
                let allPatterns = [imageUUIDPattern, fileUUIDPattern]
                for pattern in allPatterns {
                    let regex = try NSRegularExpression(pattern: pattern, options: [])
                    text = regex.stringByReplacingMatches(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count), withTemplate: "")
                }
            } catch {
                // ignore errors, leave text as is
            }
            
            var parts: [[String: Any]] = []
            
            // Append file contents parts
            for uuidString in fileUUIDs {
                if let uuid = UUID(uuidString: uuidString),
                   let fileContent = try? self.dataLoader.loadFileContent(uuid: uuid) {
                    parts.append(["text": fileContent])
                }
            }
            
            // Append remaining text if not empty or not whitespace only
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                parts.append(["text": text])
            }
            
            // Append image inlineData parts
            for uuidString in imageUUIDs {
                if let uuid = UUID(uuidString: uuidString),
                   let imageData = self.dataLoader.loadImageData(uuid: uuid) {
                    let b64 = imageData.base64EncodedString()
                    let inlineData: [String: Any] = [
                        "inlineData": [
                            "mimeType": "image/jpeg",
                            "data": b64
                        ]
                    ]
                    parts.append(inlineData)
                }
            }
            
            if !parts.isEmpty {
                let messageDict: [String: Any] = [
                    "role": role,
                    "parts": parts
                ]
                contents.append(messageDict)
            }
        }
        
        // Prepare generationConfig
        let generationConfig: [String: Any] = [
            "temperature": temperature
        ]
        
        let bodyDict: [String: Any] = [
            "contents": contents,
            "generationConfig": generationConfig
        ]
        
        let jsonData = try JSONSerialization.data(withJSONObject: bodyDict, options: [])
        request.httpBody = jsonData
        
        return request
    }
    
    override internal func parseJSONResponse(data: Data) -> (String?, String?, [ToolCall]?)? {
        do {
            let json = try JSONSerialization.jsonObject(with: data, options: [])
            guard let root = json as? [String: Any],
                  let candidates = root["candidates"] as? [[String: Any]],
                  let first = candidates.first
            else {
                return nil
            }
            
            if let content = first["content"] as? [String: Any],
               let parts = content["parts"] as? [[String: Any]] {
                
                var textParts: [String] = []
                var inlineDataPart: (data: String, mimeType: String)? = nil
                
                for part in parts {
                    if let text = part["text"] as? String {
                        textParts.append(text)
                    } else if let inlineData = part["inlineData"] as? [String: Any],
                              let dataString = inlineData["data"] as? String {
                        let mimeType = (inlineData["mimeType"] as? String) ?? "image/png"
                        inlineDataPart = (data: dataString, mimeType: mimeType)
                    }
                }
                
                if !textParts.isEmpty {
                    let contentString = textParts.joined()
                    return (contentString, "assistant", nil)
                } else if let inline = inlineDataPart {
                    let contentString = "<image-url>data:\(inline.mimeType);base64,\(inline.data)</image-url>"
                    return (contentString, "assistant", nil)
                }
            }
            
            return nil
        } catch {
            return nil
        }
    }

    override internal func parseDeltaJSONResponse(data: Data?) -> (Bool, Error?, String?, String?, [ToolCall]?) {
        guard let data = data else {
            return (false, APIError.decodingFailed("No data for delta"), nil, nil, nil)
        }
        do {
            let jsonObj = try JSONSerialization.jsonObject(with: data, options: [])
            guard let root = jsonObj as? [String: Any],
                  let candidates = root["candidates"] as? [[String: Any]],
                  let first = candidates.first
            else {
                return (false, nil, nil, nil, nil)
            }
            
            // Determine finish status
            var finished = false
            // Check finishReason with case-insensitive keys
            let finishReasonKeys = ["finishReason", "finishreason", "finish_reason", "finishreason"]
            for key in finishReasonKeys {
                if let finishReasonValue = (first[key] as? String) ?? (root[key] as? String) {
                    if !finishReasonValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        finished = true
                        break
                    }
                }
            }
            // Also consider top-level "done" key boolean true
            if let done = root["done"] as? Bool, done {
                finished = true
            }
            
            // Extract streamed text if available
            if let content = first["content"] as? [String: Any],
               let parts = content["parts"] as? [[String: Any]] {
                var streamedText = ""
                var foundText = false
                var foundInlineDataString: String? = nil
                var inlineMimeType: String = "image/png"
                
                for part in parts {
                    if let text = part["text"] as? String {
                        streamedText += text
                        foundText = true
                    } else if let inlineData = part["inlineData"] as? [String: Any] {
                        if let dataString = inlineData["data"] as? String {
                            foundInlineDataString = dataString
                            inlineMimeType = (inlineData["mimeType"] as? String) ?? "image/png"
                        }
                    }
                }
                
                if foundText {
                    return (finished, nil, streamedText, "assistant", nil)
                } else if let inlineDataStr = foundInlineDataString {
                    let contentString = "<image-url>data:\(inlineMimeType);base64,\(inlineDataStr)</image-url>"
                    return (finished, nil, contentString, "assistant", nil)
                }
            }
            
            return (finished, nil, nil, nil, nil)
        } catch {
            return (false, APIError.decodingFailed("Gemini delta parse failed: \(error.localizedDescription)"), nil, nil, nil)
        }
    }
}

