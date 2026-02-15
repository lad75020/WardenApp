import Foundation
import os

private let ollamaLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "App", category: "Ollama")

private struct OllamaModelsResponse: Codable {
    let models: [OllamaModel]
}

private struct OllamaModel: Codable {
    let name: String
}

class OllamaHandler: BaseAPIHandler {
    
    internal let dataLoader = BackgroundDataLoader()
    
    // Track image generation state for streaming
    private var isImageGenerationInProgress = false
    private var accumulatedBase64Data = ""
    
    override func fetchModels() async throws -> [AIModel] {
        let tagsURL = baseURL.deletingLastPathComponent().appendingPathComponent("tags")
        
        var request = URLRequest(url: tagsURL)
        request.httpMethod = "GET"
        ollamaLog.debug("Fetching Ollama models from: \(tagsURL.absoluteString, privacy: .public)")
        
        do {
            let (data, response) = try await session.data(for: request)
            ollamaLog.debug("Received models response: \((response as? HTTPURLResponse)?.statusCode ?? -1, privacy: .public)")
            ollamaLog.debug("Models payload size: \(data.count, privacy: .public) bytes")
            
            let result = handleAPIResponse(response, data: data, error: nil)
            switch result {
            case .success(let responseData):
                guard let responseData = responseData else {
                    throw APIError.invalidResponse
                }
                
                let ollamaResponse = try JSONDecoder().decode(OllamaModelsResponse.self, from: responseData)
                
                return ollamaResponse.models.map { AIModel(id: $0.name) }
                
            case .failure(let error):
                throw error
            }
        } catch {
            throw APIError.requestFailed(error)
        }
    }
    
    private func replacingChatWithGenerate(in url: URL) -> URL {
        let chatSuffix = "/api/chat"
        let generateSuffix = "/api/generate"

        let urlString = url.absoluteString

        guard urlString.hasSuffix(chatSuffix),
              let newURL = URL(
                string: String(urlString.dropLast(chatSuffix.count)) + generateSuffix
              )
        else {
            return url
        }

        return newURL
    }
    
    private func detectImageGeneration(in requestMessages: [[String: String]]) -> Bool {
        // Route any vision input (image markers, file markers with image data, or data URLs) to /api/generate.
        let imagePattern = "<image-uuid>(.*?)</image-uuid>"
        let filePattern = "<file-uuid>(.*?)</file-uuid>"

        for message in requestMessages {
            guard let role = message["role"], role == "user", let content = message["content"] else { continue }
            if content.contains("data:image/") {
                return true
            }

            if let regex = try? NSRegularExpression(pattern: imagePattern, options: []) {
                let nsString = content as NSString
                let matches = regex.matches(in: content, options: [], range: NSRange(location: 0, length: nsString.length))
                if !matches.isEmpty {
                    return true
                }
            }

            if let regex = try? NSRegularExpression(pattern: filePattern, options: []) {
                let nsString = content as NSString
                let matches = regex.matches(in: content, options: [], range: NSRange(location: 0, length: nsString.length))
                for match in matches {
                    if match.numberOfRanges > 1 {
                        let uuidString = nsString.substring(with: match.range(at: 1))
                        if let uuid = UUID(uuidString: uuidString),
                           let imageData = self.dataLoader.loadFileImageData(uuid: uuid),
                           !imageData.isEmpty {
                            return true
                        }
                    }
                }
            }
        }

        // Also route explicit image generation models to /api/generate.
        return isImageGenerationModel(self.model.lowercased())
    }
    
    private func isImageGenerationModel(_ modelName: String) -> Bool {
        // Common patterns for image generation models in Ollama
        let imageKeywords = [
            "image", "img", "diffusion", "stable-diffusion", "sdxl", "sd",
            "flux", "kandinsky", "dream", "pixel", "turbo", "generative",
            "bark", "riffusion", "cogview", "wand"
        ]
        
        return imageKeywords.contains { modelName.contains($0) }
    }
    
    override func prepareRequest(
        requestMessages: [[String: String]],
        tools: [[String: Any]]?,
        model: String,
        temperature: Float,
        stream: Bool
    ) throws -> URLRequest {
        // Determine if this is image generation
        let isImageGeneration = detectImageGeneration(in: requestMessages)
        
        // Reset image generation state
        self.isImageGenerationInProgress = isImageGeneration && stream
        self.accumulatedBase64Data = ""
        
        // For image generation, switch to /api/generate endpoint
        let effectiveURL = isImageGeneration ? replacingChatWithGenerate(in: baseURL) : baseURL
        let effectiveStream = isImageGeneration ? false : stream
        let useChatEndpoint = !isImageGeneration && effectiveURL.absoluteString.contains("/api/chat")
        
        var request = URLRequest(url: effectiveURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 1800
        request.setValue(effectiveStream ? "application/x-ndjson" : "application/json", forHTTPHeaderField: "Accept")
        
        ollamaLog.debug("Preparing Ollama request. model=\(model, privacy: .public) stream=\(effectiveStream, privacy: .public) temperature=\(temperature, privacy: .public)")
        ollamaLog.debug("Incoming messages count: \(requestMessages.count, privacy: .public)")
        ollamaLog.debug("Is image generation: \(isImageGeneration, privacy: .public)")
        ollamaLog.debug("Using endpoint: \(effectiveURL.absoluteString, privacy: .public)")
        
        // Log the incoming messages for debugging
        for (index, msg) in requestMessages.enumerated() {
            if let role = msg["role"], let content = msg["content"] {
                let isSystem = role == "system"
                let preview = String(content.prefix(100))
                ollamaLog.debug("Input[\(index)]: role=\(role, privacy: .public) isSystem=\(isSystem, privacy: .public) content=\(preview, privacy: .public)")
            }
        }
        
        var jsonDict: [String: Any] = [
            "model": model,
            "stream": effectiveStream,
            "options": ["temperature": temperature]
        ]
        
        if useChatEndpoint {
            var processedMessages: [[String: Any]] = []
            let imagePattern = "<image-uuid>(.*?)</image-uuid>"
            let dataUrlPattern = "data:image/[^;]+;base64,([A-Za-z0-9+/=]+)"
            let filePattern = "<file-uuid>(.*?)</file-uuid>"

            for message in requestMessages {
                guard let role = message["role"], var content = message["content"] else { continue }

                var imagesB64: [String] = []
                if let regex = try? NSRegularExpression(pattern: imagePattern, options: []) {
                    let nsString = content as NSString
                    let matches = regex.matches(in: content, options: [], range: NSRange(location: 0, length: nsString.length))
                    for match in matches {
                        if match.numberOfRanges > 1 {
                            let uuidString = nsString.substring(with: match.range(at: 1))
                            if let uuid = UUID(uuidString: uuidString),
                               let imageData = self.dataLoader.loadImageData(uuid: uuid) {
                                imagesB64.append(imageData.base64EncodedString())
                            }
                        }
                    }
                    // Strip markers from content text
                    content = regex.stringByReplacingMatches(in: content, options: [], range: NSRange(location: 0, length: nsString.length), withTemplate: "")
                }
                if let regex = try? NSRegularExpression(pattern: dataUrlPattern, options: []) {
                    let nsString = content as NSString
                    let matches = regex.matches(in: content, options: [], range: NSRange(location: 0, length: nsString.length))
                    for match in matches {
                        if match.numberOfRanges > 1 {
                            let base64String = nsString.substring(with: match.range(at: 1))
                            imagesB64.append(base64String)
                        }
                    }
                    // Strip data URLs from content text
                    content = regex.stringByReplacingMatches(in: content, options: [], range: NSRange(location: 0, length: nsString.length), withTemplate: "")
                }
                if let regex = try? NSRegularExpression(pattern: filePattern, options: []) {
                    let nsString = content as NSString
                    let matches = regex.matches(in: content, options: [], range: NSRange(location: 0, length: nsString.length))
                    for match in matches {
                        if match.numberOfRanges > 1 {
                            let uuidString = nsString.substring(with: match.range(at: 1))
                            if let uuid = UUID(uuidString: uuidString),
                               let imageData = self.dataLoader.loadFileImageData(uuid: uuid),
                               !imageData.isEmpty {
                                imagesB64.append(imageData.base64EncodedString())
                            }
                        }
                    }
                    // Strip file markers from content text
                    content = regex.stringByReplacingMatches(in: content, options: [], range: NSRange(location: 0, length: nsString.length), withTemplate: "")
                }
                content = content.trimmingCharacters(in: .whitespacesAndNewlines)

                var dict: [String: Any] = [
                    "role": role,
                    "content": content
                ]
                if !imagesB64.isEmpty {
                    dict["images"] = imagesB64
                }
                processedMessages.append(dict)
            }

            // Filter messages intelligently:
            // - Keep system messages even if they contain [omitted image response]
            // - Filter empty assistant messages (placeholders)
            // - Keep user messages if they have text or images
            let filteredMessages = processedMessages.filter { message in
                guard let role = message["role"] as? String else { return true }
                let content = (message["content"] as? String) ?? ""
                let images = (message["images"] as? [String]) ?? []

                if role == "system" { return true }
                if role == "assistant" && content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return false }
                if role == "user" {
                    let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
                    return !trimmed.isEmpty || !images.isEmpty
                }
                return true
            }

            jsonDict["messages"] = filteredMessages
            
            ollamaLog.debug("Using /api/chat endpoint with \(filteredMessages.count) message(s) (from \(requestMessages.count) input)")
            
            // Log message breakdown for debugging
            for (index, msg) in filteredMessages.enumerated() {
                if let role = msg["role"] as? String,
                   let content = msg["content"] as? String {
                    let isSystem = role == "system"
                    let preview = String(content.prefix(100))
                    ollamaLog.debug("Filtered[\(index)]: role=\(role, privacy: .public) isSystem=\(isSystem, privacy: .public) content=\(preview, privacy: .public)")
                }
            }
            
        } else {
            // Use /api/generate endpoint with "prompt" field
            if isImageGeneration {
                var prompt = ""
                var rawUserContentForImages = ""
                for message in requestMessages.reversed() {
                    if message["role"] == "user", let content = message["content"],
                       !content.hasPrefix("[omitted image") {
                        prompt = content
                        rawUserContentForImages = content
                        break
                    }
                }

                // Remove image/file markers from the prompt text
                let imagePattern = "<image-uuid>(.*?)</image-uuid>"
                let filePattern = "<file-uuid>(.*?)</file-uuid>"
                prompt = prompt.replacingOccurrences(of: imagePattern, with: "", options: .regularExpression)
                prompt = prompt.replacingOccurrences(of: filePattern, with: "", options: .regularExpression)
                prompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)

                jsonDict["prompt"] = prompt

                // Extract base64 images from markers and attach to payload
                let dataUrlPattern = "data:image/[^;]+;base64,([A-Za-z0-9+/=]+)"
                var imagesB64: [String] = []
                if let regex = try? NSRegularExpression(pattern: imagePattern, options: []) {
                    let nsString = rawUserContentForImages as NSString
                    let matches = regex.matches(in: rawUserContentForImages, options: [], range: NSRange(location: 0, length: nsString.length))
                    for match in matches {
                        if match.numberOfRanges > 1 {
                            let uuidString = nsString.substring(with: match.range(at: 1))
                            if let uuid = UUID(uuidString: uuidString),
                               let imageData = self.dataLoader.loadImageData(uuid: uuid) {
                                imagesB64.append(imageData.base64EncodedString())
                            }
                        }
                    }
                }
                if let regex = try? NSRegularExpression(pattern: dataUrlPattern, options: []) {
                    let nsString = rawUserContentForImages as NSString
                    let matches = regex.matches(in: rawUserContentForImages, options: [], range: NSRange(location: 0, length: nsString.length))
                    for match in matches {
                        if match.numberOfRanges > 1 {
                            let base64String = nsString.substring(with: match.range(at: 1))
                            imagesB64.append(base64String)
                        }
                    }
                }
                if let regex = try? NSRegularExpression(pattern: filePattern, options: []) {
                    let nsString = rawUserContentForImages as NSString
                    let matches = regex.matches(in: rawUserContentForImages, options: [], range: NSRange(location: 0, length: nsString.length))
                    for match in matches {
                        if match.numberOfRanges > 1 {
                            let uuidString = nsString.substring(with: match.range(at: 1))
                            if let uuid = UUID(uuidString: uuidString),
                               let imageData = self.dataLoader.loadFileImageData(uuid: uuid),
                               !imageData.isEmpty {
                                imagesB64.append(imageData.base64EncodedString())
                            }
                        }
                    }
                }
                if !imagesB64.isEmpty {
                    jsonDict["images"] = imagesB64
                } else if rawUserContentForImages.contains("<image-uuid>") || rawUserContentForImages.contains("data:image/") || rawUserContentForImages.contains("<file-uuid>") {
                    ollamaLog.error("Image markers present but no image data was attached to /api/generate payload")
                }

                ollamaLog.debug("Image generation with /api/generate. Prompt length: \(prompt.count, privacy: .public)")
                ollamaLog.debug("Image prompt preview (first 200 chars): \(String(prompt.prefix(200)), privacy: .public)")
                ollamaLog.debug("Attached images count: \(imagesB64.count, privacy: .public)")
            } else {
                // For /api/generate with non-image content (legacy support), just send the last user message
                var prompt = ""
                for message in requestMessages.reversed() {
                    if message["role"] == "user", let content = message["content"],
                       !content.isEmpty &&
                       !content.hasPrefix("[omitted image") {
                        prompt = content
                        break
                    }
                }
                
                jsonDict["prompt"] = prompt
                ollamaLog.debug("Using /api/generate with prompt. Length: \(prompt.count, privacy: .public)")
                ollamaLog.debug("Prompt preview (first 200 chars): \(String(prompt.prefix(200)), privacy: .public)")
            }
        }
        
        do {
            ollamaLog.debug("Final JSON payload keys: \(Array(jsonDict.keys).joined(separator: ","), privacy: .public)")
            request.httpBody = try JSONSerialization.data(withJSONObject: jsonDict, options: [])
            let requestSize = request.httpBody?.count ?? 0
            ollamaLog.debug("Request body size: \(requestSize) bytes")
            
            if let httpBody = request.httpBody, let jsonString = String(data: httpBody, encoding: .utf8) {
                ollamaLog.debug("ACTUAL JSON PAYLOAD SENT TO OLLAMA: \(jsonString, privacy: .public)")
            }
        } catch {
            ollamaLog.error("Failed to serialize JSON body: \(error.localizedDescription, privacy: .public)")
            throw APIError.decodingFailed(error.localizedDescription)
        }
        
        ollamaLog.debug("Prepared request for URL: \(request.url?.absoluteString ?? "nil", privacy: .public) Accept=\(request.value(forHTTPHeaderField: "Accept") ?? "", privacy: .public) timeout=\(request.timeoutInterval, privacy: .public))")

        return request
    }

    override func parseJSONResponse(data: Data) -> (String?, String?, [ToolCall]?)? {
    ollamaLog.debug("parseJSONResponse called with \(data.count, privacy: .public) bytes")
    
    // Ollama's /api/generate endpoint returns NDJSON (multiple JSON lines on newlines)
    // even with stream=false. We need to parse the last complete line.
    if let responseString = String(data: data, encoding: .utf8) {
        let lines = responseString.split(separator: "\n").map(String.init)
        ollamaLog.debug("Response contains \(lines.count, privacy: .public) line(s) of NDJSON")
        
        // Find the last non-empty line that has JSON
        if let lastJSONLine = lines.reversed().first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            ollamaLog.debug("Processing last JSON line (first 100 chars): \(String(lastJSONLine.prefix(100)), privacy: .public)")
            
            if let lastData = lastJSONLine.data(using: .utf8) {
                do {
                    let json = try JSONSerialization.jsonObject(with: lastData, options: [])
                    if let dict = json as? [String: Any] {
                        ollamaLog.debug("Top-level keys: \(Array(dict.keys).joined(separator: ","), privacy: .public)")
                        
                        // Handle thinking prefix
                        var thinkingPrefix: String? = nil
                        if let thinking = dict["thinking"] as? String, !thinking.isEmpty {
                            thinkingPrefix = "🫣\n\(thinking)\n🤖\n\n"
                        }
                        
                        // Handle Ollama image generation response - the image data is in the "image" field
                        if let imageBase64 = dict["image"] as? String, !imageBase64.isEmpty {
                            ollamaLog.debug("Detected image response in 'image' field. Size: \(imageBase64.count, privacy: .public) chars")
                            
                            // Verify it's valid base64 image data
                            if let imageData = Data(base64Encoded: imageBase64, options: [.ignoreUnknownCharacters]),
                               let mime = self.guessImageMimeType(from: imageData) {
                                ollamaLog.debug("Image data successfully decoded. Size: \(imageData.count, privacy: .public) bytes, MIME: \(mime)")
                                let content = "<image-url>\(imageBase64)</image-url>"
                                return ((thinkingPrefix ?? "") + content, "assistant", nil)
                            } else {
                                ollamaLog.warning("Image data appears to be invalid base64")
                            }
                        }
                        
                        // /api/generate format: uses "response" field at top level
                        if let response = dict["response"] as? String {
                            let stripped = response.hasPrefix("IMAGE_BASE64:") ? String(response.dropFirst("IMAGE_BASE64:".count)) : response
                            
                            if let imageData = Data(base64Encoded: stripped, options: [.ignoreUnknownCharacters]),
                               let mime = self.guessImageMimeType(from: imageData) {
                                ollamaLog.debug("Detected image response (base64). Emitting image-url wrapper. Size: \(imageData.count, privacy: .public) bytes")
                                let content = "<image-url>\(stripped)</image-url>"
                                return ((thinkingPrefix ?? "") + content, "assistant", nil)
                            } else {
                                ollamaLog.debug("Detected text response. Length: \(response.count, privacy: .public)")
                                return ((thinkingPrefix ?? "") + response, "assistant", nil)
                            }
                        }
                        // /api/chat format: uses "message" field
                        else if let message = dict["message"] as? [String: Any],
                                let messageContent = message["content"] as? String {
                            ollamaLog.debug("Using 'message' field from /api/chat.")
                            return ((thinkingPrefix ?? "") + messageContent, "assistant", nil)
                        }
                    }
                } catch {
                    ollamaLog.error("Failed to parse JSON line: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
        
        // Fallback: try to find IMAGE_BASE64: in the raw response
        if let base64Range = responseString.range(of: "IMAGE_BASE64:") {
            let base64Start = responseString.index(after: base64Range.upperBound)
            let potentialBase64 = String(responseString[base64Start...])
            
            // The base64 might be followed by more JSON, so we need to find where it ends
            // The base64 ends at the closing quote or end of data
            if let quoteEnd = potentialBase64.firstIndex(of: "\"") {
                let trimmedBase64 = String(potentialBase64[..<quoteEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
                ollamaLog.debug("Fallback: found potential base64 data. Length: \(trimmedBase64.count, privacy: .public) chars")
                
                if let imageData = Data(base64Encoded: trimmedBase64, options: [.ignoreUnknownCharacters]),
                   let mime = self.guessImageMimeType(from: imageData) {
                    ollamaLog.debug("Fallback base64 successfully decoded as image. Size: \(imageData.count, privacy: .public) bytes")
                    let content = "<image-url>\(trimmedBase64)</image-url>"
                    return (content, "assistant", nil)
                }
            } else {
                // No closing quote found, try the whole string up to the end
                let trimmedBase64 = potentialBase64.trimmingCharacters(in: .whitespacesAndNewlines)
                ollamaLog.debug("Fallback: trying trailing base64. Length: \(trimmedBase64.count, privacy: .public) chars")
                
                if let imageData = Data(base64Encoded: trimmedBase64, options: [.ignoreUnknownCharacters]),
                   let mime = self.guessImageMimeType(from: imageData) {
                    ollamaLog.debug("Fallback trailing base64 successfully decoded as image. Size: \(imageData.count, privacy: .public) bytes")
                    let content = "<image-url>\(trimmedBase64)</image-url>"
                    return (content, "assistant", nil)
                }
            }
        }
        
        ollamaLog.error("Could not extract image or text from response")
        #if DEBUG
        WardenLog.app.debug("Ollama full response: \(responseString.prefix(500), privacy: .public)")
        #endif
    }
    
    return nil
}

    override func parseDeltaJSONResponse(data: Data?) -> (Bool, Error?, String?, String?, [ToolCall]?) {
        guard let data = data else {
            return (true, APIError.decodingFailed("No data received in SSE event"), nil, nil, nil)
        }
        let dataString = String(data: data, encoding: .utf8)
        ollamaLog.debug("parseDeltaJSONResponse called with \(data.count, privacy: .public) bytes: \(dataString?.prefix(100) ?? "nil", privacy: .public)")

        do {
            guard let dataString = dataString else {
                ollamaLog.error("Could not decode response as UTF-8")
                return (false, APIError.decodingFailed("Could not decode response"), nil, nil, nil)
            }
            
            // Debug: Log the raw data string to see what we're getting
            ollamaLog.debug("Raw delta data string: \(dataString.prefix(200), privacy: .public)")
            
            // Handle Ollama's newline-delimited JSON without "data:" prefix
            // Ollama sends raw JSON objects separated by newlines directly  
            let trimmedString = dataString.trimmingCharacters(in: .whitespacesAndNewlines)
            
            guard !trimmedString.isEmpty else {
                // Empty line, skip
                ollamaLog.debug("Skipping empty line in delta response")
                return (false, nil, nil, nil, nil)
            }
            
            if let trimmedData = trimmedString.data(using: .utf8) {
                let jsonResponse = try JSONSerialization.jsonObject(with: trimmedData, options: [])

                if let dict = jsonResponse as? [String: Any] {
                    ollamaLog.debug("Delta keys: \(Array(dict.keys).joined(separator: ","), privacy: .public)")
                    let done = dict["done"] as? Bool ?? false
                    ollamaLog.debug("Delta 'done' = \(done, privacy: .public)")
                    
                    // Extract content and thinking separately
                    var contentField: String? = nil
                    var thinkingField: String? = nil
                    
                    // Handle /api/generate format with full response in one payload
                    if let response = dict["response"] as? String, !response.isEmpty {
                        ollamaLog.debug("Delta contains full response payload. Length: \(response.count, privacy: .public)")
                        return (true, nil, response, "assistant", nil)
                    }
                    
                    // Handle message object format (most common)
                    if let message = dict["message"] as? [String: Any] {
                        contentField = message["content"] as? String
                        thinkingField = message["thinking"] as? String
                    }
                    // Handle content/thinking at top level
                    else {
                        contentField = dict["content"] as? String
                        thinkingField = dict["thinking"] as? String
                    }
                    
                    // Special case for final [DONE] message or done indicator
                    if done && dict.count == 1 {
                        ollamaLog.debug("Received final done indicator")
                        
                        // If we're in image generation mode and have accumulated data, return it now
                        if self.isImageGenerationInProgress && !self.accumulatedBase64Data.isEmpty {
                            let finalImageData = self.accumulatedBase64Data
                            self.isImageGenerationInProgress = false
                            self.accumulatedBase64Data = ""
                            ollamaLog.debug("Delivering accumulated image data: \(finalImageData.count, privacy: .public) chars")
                            return (true, nil, "<image-url>\(finalImageData)</image-url>", "assistant", nil)
                        }
                        
                        return (true, nil, nil, "assistant", nil)
                    }
                    
                    // Handle both content and thinking fields
                    var combinedContent: String = ""
                    var role: String = "assistant"
                    
                    // Add thinking content first if present
                    if let thinking = thinkingField, !thinking.isEmpty {
                        ollamaLog.debug("Delta thinking chunk length: \(thinking.count, privacy: .public)")
                        // We'll return thinking content as reasoning role
                        return (false, nil, thinking, "reasoning", nil)
                    }
                    
                    // Then add regular content if present
                    if let content = contentField, !content.isEmpty {
                        combinedContent += content
                    }
                    
                    // Handle image generation streaming
                    if self.isImageGenerationInProgress {
                        // For image generation, accumulate base64 data across chunks
                        if !combinedContent.isEmpty {
                            if combinedContent.hasPrefix("IMAGE_BASE64:") {
                                // Remove the prefix and accumulate the base64 data
                                let base64Data = String(combinedContent.dropFirst("IMAGE_BASE64:".count))
                                self.accumulatedBase64Data += base64Data
                                ollamaLog.debug("Accumulated image base64 chunk: \(base64Data.count, privacy: .public) chars")
                            } else {
                                // Sometimes Ollama might send base64 without prefix in streaming
                                self.accumulatedBase64Data += combinedContent
                                ollamaLog.debug("Accumulated image data chunk (no prefix): \(combinedContent.count, privacy: .public) chars")
                            }
                            
                            // Don't yield anything yet - wait for the final chunk
                            return (false, nil, nil, "assistant", nil)
                        }
                        
                        // If this is the final chunk and we have accumulated data, deliver it
                        if done && !self.accumulatedBase64Data.isEmpty {
                            let finalImageData = self.accumulatedBase64Data
                            self.isImageGenerationInProgress = false
                            self.accumulatedBase64Data = ""
                            ollamaLog.debug("Delivering final image data: \(finalImageData.count, privacy: .public) chars")
                            return (true, nil, "<image-url>\(finalImageData)</image-url>", "assistant", nil)
                        }
                    }
                    // Handle text content streaming
                    else if !combinedContent.isEmpty {
                        // Skip empty image base64 markers in regular text streaming
                        if combinedContent.hasPrefix("IMAGE_BASE64:") {
                            ollamaLog.debug("Delta suppresses image base64 content in text stream, continuing")
                            return (false, nil, nil, "assistant", nil)
                        }
                        
                        ollamaLog.debug("Delta text content length: \(combinedContent.count, privacy: .public)")
                        return (done, nil, combinedContent, "assistant", nil)
                    }
                    
                    // Handle case where there's no content but done=true (end of stream marker)  
                    if done {
                        ollamaLog.debug("Delta has no content but done=true, marking end of stream")
                        return (true, nil, nil, "assistant", nil)
                    }
                }
            }
        } catch {
            ollamaLog.error("Delta JSON parse error: \(error.localizedDescription, privacy: .public)")
            #if DEBUG
            WardenLog.app.debug(
                "Ollama delta JSON parse error: \(error.localizedDescription, privacy: .public) (\(data.count, privacy: .public) byte(s))"
            )
            #endif
            return (false, APIError.decodingFailed("Failed to parse JSON: \(error.localizedDescription)"), nil, nil, nil)
        }

        // Return empty success if nothing could be parsed but stream should continue
        ollamaLog.debug("Delta response processed without content or errors, continuing stream")
        return (false, nil, nil, nil, nil)
    }
    
    private func guessImageMimeType(from data: Data) -> String? {
        if data.count >= 4 {
            let header4 = [UInt8](data.prefix(4))
            if header4[0] == 0x89 && header4[1] == 0x50 && header4[2] == 0x4E && header4[3] == 0x47 {
                return "image/png"
            }
        }
        if data.count >= 3 {
            let header3 = [UInt8](data.prefix(3))
            if header3[0] == 0x25 && header3[1] == 0x50 && header3[2] == 0x44 && header3[3] == 0x46 {
                return "application/pdf"
            } else if header3[0] == 0xFF && header3[1] == 0xD8 && header3[2] == 0xFF {
                return "image/jpeg"
            }
        }
        return nil
    }
    
    // Override the sendMessageStream method to use NDJSON format for Ollama
    override func sendMessageStream(
        _ requestMessages: [[String: String]],
        tools: [[String: Any]]? = nil,
        temperature: Float
    ) async throws -> AsyncThrowingStream<(String?, [ToolCall]?), Error> {
        let request = try prepareRequest(
            requestMessages: requestMessages,
            tools: tools,
            model: model,
            temperature: temperature,
            stream: true
        )
        
        #if DEBUG
        let log = WardenLog.streaming
        log.debug("Starting stream: \(request.url?.absoluteString ?? "nil", privacy: .public)")
        #endif
        
        return AsyncThrowingStream { continuation in
            let task = Task(priority: .userInitiated) {
                do {
                    let (stream, response) = try await streamingSession.bytes(for: request)
                    
                    #if DEBUG
                    log.debug("Got stream from URL session")
                    log.debug("Response status: \((response as? HTTPURLResponse)?.statusCode ?? -1, privacy: .public)")
                    
                    if let httpResponse = response as? HTTPURLResponse {
                        for (key, value) in httpResponse.allHeaderFields {
                            let valueString: String
                            if let stringArray = value as? [String] {
                                valueString = stringArray.joined(separator: ";")
                            } else {
                                valueString = "\(value)"
                            }
                            log.debug("Header: \(key, privacy: .public) = \(valueString, privacy: .public)")
                        }
                    }
                    #endif
                    
                    // Use NDJSON format for Ollama streaming
                    try await SSEStreamParser.parse(
                        stream: stream,
                        format: .ndjson,  // This is the key change
                        deliveryMode: .bufferedWithCompatibilityFlush
                    ) { [weak self] dataString in
                        guard let data = dataString.data(using: .utf8) else { return }
                        
                        guard let self = self else { return }
                        let (finished, error, messageData, role, toolCalls) = self.parseDeltaJSONResponse(data: data)
                        
                        if let error = error {
                            continuation.yield((nil, nil))
                            continuation.finish(throwing: error)
                            return
                        }
                        
                        if let messageData = messageData {
                            #if DEBUG
                            log.debug("Yielding chunk: \(String(messageData.prefix(50)), privacy: .public)...")
                            #endif
                            continuation.yield((messageData, toolCalls))
                        }
                        
                        if finished {
                            continuation.finish()
                        }
                    }
                    
                    continuation.finish()
                } catch {
                    #if DEBUG
                    log.error("Stream failed: \(error.localizedDescription, privacy: .public)")
                    #endif
                    continuation.finish(throwing: error)
                }
            }
            
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}


