import Foundation

class OllamaCustomHandler: BaseAPIHandler {
    override internal func prepareRequest(requestMessages: [[String: String]], tools: [[String: Any]]?, model: String, temperature: Float, stream: Bool) throws -> URLRequest {
        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        
        let isOllamaGenerateEndpoint = baseURL.absoluteString.contains("/api/generate")
        let isOllamaChatEndpoint = baseURL.absoluteString.contains("/api/chat")
        
        var requestBody: [String: Any] = [:]

        if isOllamaGenerateEndpoint {
            requestBody = [
                "model": model,
                "prompt": requestMessages.last?["content"] ?? "",
                "stream": stream,
                "options": ["temperature": temperature]
            ]
        } else if isOllamaChatEndpoint {
            let processedMessages: [[String: Any]] = requestMessages.compactMap { message in
                guard let role = message["role"], let content = message["content"] else { return nil }
                return ["role": role, "content": content]
            }
            requestBody = [
                "model": model,
                "messages": processedMessages,
                "stream": stream,
                "options": ["temperature": temperature]
            ]
        } else {
            requestBody = [
                "model": model,
                "prompt": requestMessages.last?["content"] ?? "",
                "stream": stream,
                "options": ["temperature": temperature]
            ]
        }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        return request
    }
}
