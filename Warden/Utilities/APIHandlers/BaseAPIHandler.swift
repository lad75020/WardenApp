import Foundation
import os

class BaseAPIHandler: APIService {
    let name: String
    let baseURL: URL
    internal let apiKey: String
    let model: String
    internal let session: URLSession
    internal let streamingSession: URLSession
    
    init(config: APIServiceConfiguration, session: URLSession, streamingSession: URLSession) {
        self.name = config.name
        self.baseURL = config.apiUrl
        self.apiKey = config.apiKey
        self.model = config.model
        self.session = session
        self.streamingSession = streamingSession
    }
    
    convenience init(config: APIServiceConfiguration, session: URLSession) {
        self.init(config: config, session: session, streamingSession: session)
    }
    
    // MARK: - APIService Protocol Implementation
    
    func sendMessage(
        _ requestMessages: [[String: String]],
        tools: [[String: Any]]? = nil,
        temperature: Float,
        completion: @escaping (Result<(String?, [ToolCall]?), APIError>) -> Void
    ) {
        Task {
            do {
                let result = try await sendMessage(requestMessages, tools: tools, temperature: temperature)
                completion(.success(result))
            } catch let error as APIError {
                completion(.failure(error))
            } catch {
                completion(.failure(.unknown(error.localizedDescription)))
            }
        }
    }
    
    func sendMessageStream(
    _ requestMessages: [[String: String]],
    tools: [[String: Any]]? = nil,
    temperature: Float
) async throws -> AsyncThrowingStream<(String?, [ToolCall]?), Error> {
    let request = try prepareRequest(
        requestMessages: requestMessages,
        tools: tools,
        model: model,
        temperature: 1,
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
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                log.debug("Response status: \(statusCode, privacy: .public)")
                
                // Check for HTTP errors first
                if !(200...299).contains(statusCode) {
                    let errorBody = try await self.collectResponseBody(from: stream)
                    if let errorString = String(data: errorBody, encoding: .utf8) {
                        log.error("HTTP error \(statusCode): \(errorString, privacy: .public)")
                        throw APIError.serverError("HTTP \(statusCode): \(errorString)")
                    } else {
                        throw APIError.serverError("HTTP \(statusCode)")
                    }
                }
                
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
                
                try await SSEStreamParser.parse(
                    stream: stream,
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
    
    // MARK: - Methods to be overridden by subclasses
    
    func prepareRequest(
        requestMessages: [[String: String]],
        tools: [[String: Any]]?,
        model: String,
        temperature: Float,
        stream: Bool
    ) throws -> URLRequest {
        throw APIError.noApiService("Request building not implemented for \(name)")
    }
    
    func parseJSONResponse(data: Data) -> (String?, String?, [ToolCall]?)? {
        return nil
    }
    
    func parseDeltaJSONResponse(data: Data?) -> (Bool, Error?, String?, String?, [ToolCall]?) {
        return (false, nil, nil, nil, nil)
    }
    
    func fetchModels() async throws -> [AIModel] {
        []
    }
}

private extension BaseAPIHandler {
    func collectResponseBody(from stream: URLSession.AsyncBytes, maxBytes: Int = 1_048_576) async throws -> Data {
        var data = Data()
        data.reserveCapacity(min(16_384, maxBytes))
        for try await byte in stream {
            if data.count >= maxBytes {
                break
            }
            data.append(byte)
        }
        #if DEBUG
        WardenLog.streaming.debug("Captured streaming error body: \(data.count, privacy: .public) byte(s)")
        #endif
        return data
    }
}

