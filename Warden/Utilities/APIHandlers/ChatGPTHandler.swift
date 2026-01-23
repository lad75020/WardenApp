import CoreData
import Foundation
import os

private struct ChatGPTModelsResponse: Codable {
    let data: [ChatGPTModel]
}

private struct ChatGPTModel: Codable {
    let id: String
}

class ChatGPTHandler: BaseAPIHandler {
    internal let dataLoader = BackgroundDataLoader()
    private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Warden", category: "ChatGPT")

    override init(config: APIServiceConfiguration, session: URLSession, streamingSession: URLSession) {
        super.init(config: config, session: session, streamingSession: streamingSession)
        log.debug("ChatGPTHandler initialized with config: \(config.name)")
    }
    
    convenience init(config: APIServiceConfiguration, session: URLSession) {
        self.init(config: config, session: session, streamingSession: session)
    }

    override func fetchModels() async throws -> [AIModel] {
        let modelsURL = baseURL.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("models")
        log.debug("Fetching models from: \(modelsURL.absoluteString, privacy: .public)")

        var request = URLRequest(url: modelsURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        do {
            log.debug("Starting models fetch request")
            let (data, response) = try await session.data(for: request)

            let result = handleAPIResponse(response, data: data, error: nil)
            switch result {
            case .success(let responseData):
                guard let responseData = responseData else {
                    log.error("No response data received for models fetch")
                    throw APIError.invalidResponse
                }

                log.debug("Received models response data: \(responseData.count, privacy: .public) bytes")
                
                do {
                    let gptResponse = try JSONDecoder().decode(ChatGPTModelsResponse.self, from: responseData)
                    log.debug("Successfully decoded \(gptResponse.data.count, privacy: .public) models")
                    
                    return gptResponse.data.map { AIModel(id: $0.id) }

                } catch {
                    log.error("Failed to decode models response: \(error.localizedDescription, privacy: .public)")
                    throw APIError.decodingFailed(error.localizedDescription)
                }

            case .failure(let error):
                log.error("Models fetch failed: \(error.localizedDescription, privacy: .public)")
                throw error
            }
        }
        catch {
            log.error("Models fetch request failed: \(error.localizedDescription, privacy: .public)")
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
        log.debug("Preparing request for \(requestMessages.count, privacy: .public) messages, model: \(model), stream: \(stream), temperature: \(temperature)")
        
        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let isImageGeneration = baseURL.absoluteString.contains("/images/generations") || self.model.lowercased().hasPrefix("gpt-image")
        log.debug("Is image generation request: \(isImageGeneration)")

        if isImageGeneration {
            // Build a single prompt string by concatenating all message contents
            var combinedPromptParts: [String] = []
            for message in requestMessages {
                if let content = message["content"], !content.isEmpty {
                    combinedPromptParts.append(content)
                }
            }
            var combinedPrompt = combinedPromptParts.joined(separator: "\n\n")
            // Remove attachment UUID markers
            let imagePattern = "<image-uuid>(.*?)</image-uuid>"
            let filePattern = "<file-uuid>(.*?)</file-uuid>"
            combinedPrompt = combinedPrompt.replacingOccurrences(of: imagePattern, with: "", options: .regularExpression)
            combinedPrompt = combinedPrompt.replacingOccurrences(of: filePattern, with: "", options: .regularExpression)
            combinedPrompt = combinedPrompt.trimmingCharacters(in: .whitespacesAndNewlines)

            log.debug("Image generation prompt: \(combinedPrompt, privacy: .public)")

            var jsonDict: [String: Any] = [
                "model": self.model,
                "prompt": combinedPrompt,
                "n": 1,
                "size": "1024x1024"
            ]

            do {
                request.httpBody = try JSONSerialization.data(withJSONObject: jsonDict, options: [])
                log.debug("Image generation request body created: \(request.httpBody?.count ?? 0, privacy: .public) bytes")
            } catch {
                log.error("Failed to serialize image generation request: \(error.localizedDescription, privacy: .public)")
                throw APIError.decodingFailed(error.localizedDescription)
            }

            return request
        }

        var temperatureOverride = temperature

        if AppConstants.openAiReasoningModels.contains(self.model) {
            temperatureOverride = 1
            log.debug("Using temperature override for reasoning model: \(temperatureOverride)")
        }

        var processedMessages: [[String: Any]] = []

        for (index, message) in requestMessages.enumerated() {
            log.debug("Processing message \(index + 1): role=\(message["role"] ?? "unknown", privacy: .public)")
            
            var processedMessage: [String: Any] = [:]

            if let role = message["role"] {
                processedMessage["role"] = role
            }
            
            // Handle tool_call_id if present (for tool results)
            if let toolCallId = message["tool_call_id"] {
                processedMessage["tool_call_id"] = toolCallId
                log.debug("Message has tool_call_id: \(toolCallId, privacy: .public)")
            }
            
            // Handle name if present (for tool results)
            if let name = message["name"] {
                processedMessage["name"] = name
                log.debug("Message has name: \(name, privacy: .public)")
            }

            if let content = message["content"] {
                let imagePattern = "<image-uuid>(.*?)</image-uuid>"
                let filePattern = "<file-uuid>(.*?)</file-uuid>"
                
                let hasImages = content.range(of: imagePattern, options: .regularExpression) != nil
                let hasFiles = content.range(of: filePattern, options: .regularExpression) != nil

                log.debug("Message content evaluation - hasImages: \(hasImages), hasFiles: \(hasFiles), content length: \(content.count, privacy: .public)")

                if hasImages || hasFiles {
                    var textContent = content
                    
                    // Remove all UUID patterns from text content
                    textContent = textContent.replacingOccurrences(of: imagePattern, with: "", options: .regularExpression)
                    textContent = textContent.replacingOccurrences(of: filePattern, with: "", options: .regularExpression)
                    textContent = textContent.trimmingCharacters(in: .whitespacesAndNewlines)

                    var contentArray: [[String: Any]] = []

                    // Process file attachments first (as text content)
                    if hasFiles {
                        let fileRegex = try? NSRegularExpression(pattern: filePattern, options: [])
                        let nsString = content as NSString
                        let fileMatches = fileRegex?.matches(in: content, options: [], range: NSRange(location: 0, length: nsString.length)) ?? []

                        log.debug("Found \(fileMatches.count, privacy: .public) file attachments")
                        
                        for match in fileMatches {
                            if match.numberOfRanges > 1 {
                                let uuidRange = match.range(at: 1)
                                let uuidString = nsString.substring(with: uuidRange)
                                log.debug("Processing file UUID: \(uuidString, privacy: .public)")

                                if let uuid = UUID(uuidString: uuidString),
                                   let fileContent = self.dataLoader.loadFileContent(uuid: uuid) {
                                    contentArray.append(["type": "text", "text": fileContent])
                                    log.debug("Added file content to message, length: \(fileContent.count, privacy: .public)")
                                } else {
                                    log.error("Failed to load file content for UUID: \(uuidString, privacy: .public)")
                                }
                            }
                        }
                    }
                    
                    // Add remaining text content if any
                    if !textContent.isEmpty {
                        contentArray.append(["type": "text", "text": textContent])
                        log.debug("Added text content: \(textContent.count, privacy: .public) chars")
                    }

                    // Process image attachments
                    if hasImages {
                        let imageRegex = try? NSRegularExpression(pattern: imagePattern, options: [])
                        let nsString = content as NSString
                        let imageMatches = imageRegex?.matches(in: content, options: [], range: NSRange(location: 0, length: nsString.length)) ?? []

                        log.debug("Found \(imageMatches.count, privacy: .public) image attachments")
                        
                        for match in imageMatches {
                            if match.numberOfRanges > 1 {
                                let uuidRange = match.range(at: 1)
                                let uuidString = nsString.substring(with: uuidRange)
                                log.debug("Processing image UUID: \(uuidString, privacy: .public)")

                                if let uuid = UUID(uuidString: uuidString),
                                    let imageData = self.dataLoader.loadImageData(uuid: uuid)
                                {
                                    let base64String = imageData.base64EncodedString()
                                    contentArray.append([
                                        "type": "image_url",
                                        "image_url": ["url": "data:image/jpeg;base64,\(base64String)"],
                                    ])
                                    log.debug("Added image attachment, data size: \(imageData.count, privacy: .public) bytes")
                                } else {
                                    log.error("Failed to load image data for UUID: \(uuidString, privacy: .public)")
                                }
                            }
                        }
                    }

                    processedMessage["content"] = contentArray
                    log.debug("Final message content: array with \(contentArray.count, privacy: .public) elements")
                }
                else {
                    processedMessage["content"] = content
                    log.debug("Plain text content: \(content.count, privacy: .public) chars")
                }
            }
            
            // Handle tool_calls in assistant messages
            if let toolCallsJson = message["tool_calls"], 
               let data = toolCallsJson.data(using: .utf8),
               let toolCalls = try? JSONSerialization.jsonObject(with: data, options: []) as? [[String: Any]] {
                processedMessage["tool_calls"] = toolCalls
                log.debug("Added tool_calls from string: \(toolCalls.count, privacy: .public) calls")
            }
            // Also check for our custom serialized key for Core Data compatibility
            else if let toolCallsJsonStr = message["tool_calls_json"],
                    let data = toolCallsJsonStr.data(using: .utf8),
                    let toolCalls = try? JSONSerialization.jsonObject(with: data, options: []) as? [[String: Any]] {
                processedMessage["tool_calls"] = toolCalls
                log.debug("Added tool_calls from tool_calls_json: \(toolCalls.count, privacy: .public) calls")
            }

            processedMessages.append(processedMessage)
        }

        var jsonDict: [String: Any] = [
            "model": self.model,
            "stream": stream,
            "messages": processedMessages,
            "temperature": temperatureOverride,
        ]
        
        if let tools = tools, !tools.isEmpty {
            jsonDict["tools"] = tools
            jsonDict["tool_choice"] = "auto"
            log.debug("Added \(tools.count, privacy: .public) tools to request")
        }

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: jsonDict, options: [])
            log.debug("Request body created: \(request.httpBody?.count ?? 0, privacy: .public) bytes")
            
            if let bodyString = String(data: request.httpBody ?? Data(), encoding: .utf8) {
                log.debug("Request body preview: \(String(bodyString.prefix(200)), privacy: .public)...")
            }
        } catch {
            log.error("Failed to serialize request JSON: \(error.localizedDescription, privacy: .public)")
            throw APIError.decodingFailed(error.localizedDescription)
        }

        return request
    }

    override internal func parseJSONResponse(data: Data) -> (String?, String?, [ToolCall]?)? {
        log.debug("Parsing JSON response: \(data.count, privacy: .public) bytes")
        
        if let responseString = String(data: data, encoding: .utf8) {
            #if DEBUG
            WardenLog.app.debug("ChatGPT response received: \(responseString.count, privacy: .public) char(s)")
            #endif
            
            log.debug("Raw response preview: \(String(responseString.prefix(500)), privacy: .public)...")
            
            do {
                let json = try JSONSerialization.jsonObject(with: data, options: [])
                log.debug("Successfully parsed response JSON")

                if let dict = json as? [String: Any], let dataArr = dict["data"] as? [[String: Any]], let first = dataArr.first {
                    log.debug("Detected image generation response")
                    
                    if let url = first["url"] as? String {
                        let content = "<image-url>\(url)</image-url>"
                        log.debug("Image URL response: \(url, privacy: .public)")
                        return (content, "assistant", nil)
                    }
                    if let b64 = first["b64_json"] as? String {
                        let content = "<image-url>data:image/png;base64,\(b64)</image-url>"
                        log.debug("Image base64 response: \(b64.count, privacy: .public) chars")
                        return (content, "assistant", nil)
                    }
                    // If the images response is present but lacks expected fields, return an empty assistant message to avoid parse failure
                    if dict["data"] is [[String: Any]] {
                        log.warning("Image response missing expected fields, returning empty content")
                        return ("", "assistant", nil)
                    }
                }

                if let dict = json as? [String: Any],
                   let choices = dict["choices"] as? [[String: Any]],
                   let lastIndex = choices.indices.last,
                   let message = choices[lastIndex]["message"] as? [String: Any]
                {
                    log.debug("Found chat completion response with \(choices.count, privacy: .public) choices")
                    
                    let messageRole = message["role"] as? String
                    let contentText = extractTextContent(from: message["content"])
                    let reasoningText = extractTextContent(from: message["reasoning_content"] ?? message["reasoning"])
                    
                    var toolCalls: [ToolCall]? = nil
                    if let toolCallsData = message["tool_calls"] as? [[String: Any]] {
                        toolCalls = toolCallsData.compactMap { dict -> ToolCall? in
                            guard let id = dict["id"] as? String,
                                  let type = dict["type"] as? String,
                                  let function = dict["function"] as? [String: Any],
                                  let name = function["name"] as? String,
                                  let arguments = function["arguments"] as? String else {
                                log.warning("Invalid tool call structure: \(dict, privacy: .public)")
                                return nil
                            }
                            return ToolCall(id: id, type: type, function: ToolCall.FunctionCall(name: name, arguments: arguments))
                        }
                        log.debug("Parsed \(toolCalls?.count ?? 0, privacy: .public) tool calls")
                    }
                    
                    let finalContent = composeResponse(reasoningText: reasoningText, contentText: contentText)
                    log.debug("Final content composed - Reasoning: \(reasoningText?.count ?? 0, privacy: .public) chars, Content: \(contentText?.count ?? 0, privacy: .public) chars")
                    
                    return (finalContent, messageRole, toolCalls)
                } else {
                    log.warning("Response doesn't match expected chat completion format")
                }
            }
            catch {
                log.error("ChatGPT JSON parse error: \(error.localizedDescription, privacy: .public)")
                return nil
            }
        } else {
            log.error("Failed to convert response data to string")
        }
        return nil
    }

    override internal func parseDeltaJSONResponse(data: Data?) -> (Bool, Error?, String?, String?, [ToolCall]?) {
    guard let data = data else {
        let error = APIError.decodingFailed("No data received in SSE event")
        log.error("No data received in SSE event")
        return (true, error, nil, nil, nil)
    }

    log.debug("Parsing delta JSON: \(data.count, privacy: .public) bytes")
    
    let defaultRole = "assistant"
    let dataString = String(data: data, encoding: .utf8)
    
    if dataString == "[DONE]" {
        log.debug("Received [DONE] message from stream")
        return (true, nil, nil, nil, nil)
    }

    log.debug("Delta data preview: \(dataString?.prefix(200) ?? "nil", privacy: .public)...")

    // Check if this is an error response first
    do {
        let jsonResponse = try JSONSerialization.jsonObject(with: data, options: [])
        
        if let errorDict = jsonResponse as? [String: Any],
           errorDict["error"] != nil || errorDict["message"] != nil {
            // This is an error response, not streaming data
            log.error("API returned error response: \(errorDict, privacy: .public)")
            
            if let errorMessage = errorDict["error"] as? String {
                return (true, APIError.serverError(errorMessage), nil, nil, nil)
            } else if let errorMessage = errorDict["message"] as? String {
                return (true, APIError.serverError(errorMessage), nil, nil, nil)
            } else {
                return (true, APIError.unknown("Unknown API error"), nil, nil, nil)
            }
        }
        
        log.debug("Successfully parsed delta JSON")

        if let dict = jsonResponse as? [String: Any] {
            if let choices = dict["choices"] as? [[String: Any]],
                let firstChoice = choices.first,
                let delta = firstChoice["delta"] as? [String: Any]
            {
                log.debug("Found delta in choice")
                
                let contentPart = extractTextContent(from: delta["content"])
                let reasoningPart = extractTextContent(from: delta["reasoning_content"] ?? delta["reasoning"])

                var toolCalls: [ToolCall]? = nil
                if let toolCallsData = delta["tool_calls"] as? [[String: Any]] {
                    log.debug("Processing delta tool calls")
                    toolCalls = toolCallsData.compactMap { dict -> ToolCall? in
                        guard let index = dict["index"] as? Int else { 
                            log.warning("Missing index in tool call delta")
                            return nil 
                        }
                        let id = dict["id"] as? String ?? ""
                        let type = dict["type"] as? String ?? ""
                        let function = dict["function"] as? [String: Any]
                        let name = function?["name"] as? String ?? ""
                        let arguments = function?["arguments"] as? String ?? ""

                        log.debug("Tool call delta - index: \(index, privacy: .public), name: \(name, privacy: .public)")
                        return ToolCall(id: id, type: type, function: ToolCall.FunctionCall(name: name, arguments: arguments))
                    }
                }

                let finishReason = firstChoice["finish_reason"] as? String
                let finished = finishReason == "stop" || finishReason == "tool_calls" || finishReason == "length"
                
                log.debug("Finish reason: \(finishReason ?? "nil", privacy: .public), finished: \(finished)")

                if let reasoning = reasoningPart, !reasoning.isEmpty {
                    log.debug("Yielding reasoning content: \(reasoning.count, privacy: .public) chars")
                    return (finished, nil, reasoning, "reasoning", nil)
                }
                
                if let contentPart = contentPart {
                    log.debug("Yielding content: \(contentPart.count, privacy: .public) chars")
                }
                
                return (finished, nil, contentPart, defaultRole, toolCalls)
            } else {
                log.warning("Delta response missing expected structure")
                return (true, APIError.decodingFailed("Unexpected response format"), nil, nil, nil)
            }
        }
    }
    catch {
        #if DEBUG
        WardenLog.app.debug(
            "ChatGPT delta JSON parse error: \(error.localizedDescription, privacy: .public) (\(data.count, privacy: .public) byte(s))"
        )
        #endif
        
        log.error("Failed to parse delta JSON: \(error.localizedDescription, privacy: .public)")
        return (false, APIError.decodingFailed("Failed to parse JSON: \(error.localizedDescription)"), nil, nil, nil)
    }

    log.warning("Delta response didn't match expected format")
    return (false, nil, nil, nil, nil)
}
}

private extension ChatGPTHandler {
    func extractTextContent(from value: Any?) -> String? {
        guard let value = value, !(value is NSNull) else { 
            log.debug("extractTextContent: value is nil or NSNull")
            return nil 
        }

        // Direct string
        if let text = value as? String {
            log.debug("extractTextContent: direct string - \(text.count, privacy: .public) chars")
            return text
        }

        // Dictionary content: handle typed content and image URLs
        if let dict = value as? [String: Any] {
            log.debug("extractTextContent: processing dictionary")
            
            // Handle typed content arrays used by OpenAI (e.g., {type: "text", text: "..."} or {type: "image_url", image_url: {url: "..."}})
            if let type = dict["type"] as? String {
                if type == "text", let text = dict["text"] as? String {
                    log.debug("extractTextContent: extracted text from typed content - \(text.count, privacy: .public) chars")
                    return text
                }
                if type == "image_url" {
                    if let imageDict = dict["image_url"] as? [String: Any], let url = imageDict["url"] as? String {
                        log.debug("extractTextContent: found image URL")
                        return "<image-url>\(url)</image-url>"
                    }
                    if let url = dict["image_url"] as? String {
                        log.debug("extractTextContent: found image URL string")
                        return "<image-url>\(url)</image-url>"
                    }
                }
            }
            
            // Generic keys
            if let text = dict["text"] as? String {
                log.debug("extractTextContent: extracted text from generic key - \(text.count, privacy: .public) chars")
                return text
            }
            if let imageDict = dict["image_url"] as? [String: Any], let url = imageDict["url"] as? String {
                log.debug("extractTextContent: found image URL in image_url dict")
                return "<image-url>\(url)</image-url>"
            }
            if let url = dict["image_url"] as? String {
                log.debug("extractTextContent: found image URL string in image_url")
                return "<image-url>\(url)</image-url>"
            }
            if let nested = dict["content"] {
                log.debug("extractTextContent: recursing into content")
                return extractTextContent(from: nested)
            }
            if let nested = dict["value"] {
                log.debug("extractTextContent: recursing into value")
                return extractTextContent(from: nested)
            }
            
            log.debug("extractTextContent: dictionary had no extractable content")
        }

        // Array content: join parts
        if let array = value as? [Any] {
            log.debug("extractTextContent: processing array with \(array.count, privacy: .public) elements")
            let parts = array.compactMap { extractTextContent(from: $0) }
            if parts.isEmpty { 
                log.debug("extractTextContent: array yielded no parts")
                return nil 
            }
            // Separate parts with newlines to avoid accidental concatenation
            log.debug("extractTextContent: array yielded \(parts.count, privacy: .public) parts")
            return parts.joined(separator: "\n")
        }

        log.debug("extractTextContent: couldn't extract content from \(type(of: value))")
        return nil
    }
    
    func composeResponse(reasoningText: String?, contentText: String?) -> String? {
        let trimmedReasoning = reasoningText?.trimmingCharacters(in: .whitespacesAndNewlines)
        let content = contentText
        var sections: [String] = []
        
        if let reasoning = trimmedReasoning, !reasoning.isEmpty {
            sections.append("<think>\n\(reasoning)\n</think>")
        }
        if let content = content, !content.isEmpty {
            sections.append(content)
        }
        if sections.isEmpty {
            log.debug("composeResponse: no content to compose")
            return nil
        }
        
        let result = sections.joined(separator: "\n\n")
        log.debug("composeResponse: composed \(sections.count, privacy: .public) sections, total length: \(result.count, privacy: .public) chars")
        return result
    }
}

