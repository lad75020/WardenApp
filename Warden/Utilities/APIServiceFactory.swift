import Foundation
import os

class APIServiceFactory {
    private enum SessionPurpose {
        case standard
        case streaming
    }
    
    private static func makeSessionConfiguration(for purpose: SessionPurpose) -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.default
        
        // IMPORTANT: Set resource timeout to match request timeout for streaming
        // The default resource timeout is 60s, which can kill long-running streaming responses
        configuration.timeoutIntervalForRequest = AppConstants.requestTimeout
        configuration.timeoutIntervalForResource = AppConstants.requestTimeout
        
        // ENABLE waitsForConnectivity - critical for local servers like Ollama
        // Without this, the session will fail immediately if the connection isn't ready
        configuration.waitsForConnectivity = true
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        
        // Make connection limits explicit to avoid relying on undocumented defaults.
        switch purpose {
        case .standard:
            configuration.httpMaximumConnectionsPerHost = 6
        case .streaming:
            configuration.httpMaximumConnectionsPerHost = 2
        }
        
        #if DEBUG
        WardenLog.app.debug("Created URLSession configuration: purpose=\(purpose == .standard ? "standard" : "streaming"), waitsForConnectivity=true, timeoutForRequest=\(Int(AppConstants.requestTimeout))s")
        #endif
        
        return configuration
    }
    
    static let standardSession: URLSession = {
        URLSession(configuration: makeSessionConfiguration(for: .standard))
    }()
    
    static let streamingSession: URLSession = {
        URLSession(configuration: makeSessionConfiguration(for: .streaming))
    }()

    static func createAPIService(config: APIServiceConfiguration) -> APIService {
        let configName =
            AppConstants.defaultApiConfigurations[config.name.lowercased()]?.inherits ?? config.name.lowercased()

        switch configName {
        case "chatgpt":
            return ChatGPTHandler(config: config, session: standardSession, streamingSession: streamingSession)
        case "ollama":
            return OllamaHandler(config: config, session: standardSession, streamingSession: streamingSession)
        case "claude":
            return ClaudeHandler(config: config, session: standardSession, streamingSession: streamingSession)
        case "perplexity":
            return PerplexityHandler(config: config, session: standardSession, streamingSession: streamingSession)
        case "gemini":
            return GeminiHandler(config: config, session: standardSession, streamingSession: streamingSession)
        case "deepseek":
            return DeepseekHandler(config: config, session: standardSession, streamingSession: streamingSession)
        case "openrouter":
            return OpenRouterHandler(config: config, session: standardSession, streamingSession: streamingSession)
        case "mistral":
            return MistralHandler(config: config, session: standardSession, streamingSession: streamingSession)
        case "lmstudio":
            return LMStudioHandler(config: config, session: standardSession, streamingSession: streamingSession)
        case "huggingface":
            return HuggingFaceService(model: config.model)
        case "coreml":
            return CoreMLStableDiffusionHandler(config: config)
        case "coreml llm":
            return CoreMLTextGenerationService(modelPath: config.model)
        default:
            // Fall back to ChatGPT handler for unknown services
            WardenLog.app.warning(
                "Unsupported API service '\(config.name, privacy: .public)', falling back to ChatGPT-compatible handler"
            )
            return ChatGPTHandler(config: config, session: standardSession, streamingSession: streamingSession)
        }
    }
}
