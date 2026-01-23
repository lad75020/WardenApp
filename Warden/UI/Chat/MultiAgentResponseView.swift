import SwiftUI
import AppKit

struct MultiAgentResponseView: View {
    let responses: [MultiAgentMessageManager.AgentResponse]
    let isProcessing: Bool
    let onContinue: (MultiAgentMessageManager.AgentResponse) -> Void
    @AppStorage("chatFontSize") private var chatFontSize: Double = 14.0
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isProcessing && responses.isEmpty {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Sending to multiple AI services...")
                        .font(.system(size: chatFontSize))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            } else {
                // Column layout for responses
                HStack(alignment: .top, spacing: 12) {
                    ForEach(responses) { response in
                        AgentResponseColumn(response: response, onContinue: {
                            onContinue(response)
                        })
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .padding(.horizontal, 16)
    }
}

struct AgentResponseColumn: View {
    let response: MultiAgentMessageManager.AgentResponse
    let onContinue: () -> Void
    @AppStorage("chatFontSize") private var chatFontSize: Double = 14.0
    @State private var isExpanded = true
    @State private var isHovered = false
    
    private var serviceLogoName: String {
        "logo_\(response.serviceType)"
    }
    
    private var isGoogleImageModel: Bool {
        let service = response.serviceType.lowercased()
        let model = response.model.lowercased()
        let isGoogle = service.contains("gemini") || service.contains("google")
        let hasImageKeyword = model.contains("imagen") || model.contains("image") || model.contains("banana")
        return isGoogle && hasImageKeyword
    }

    private var googleImage: NSImage? {
        guard isGoogleImageModel else { return nil }
        guard let base64 = parseGoogleImageBase64(from: response.response) else { return nil }
        return decodeBase64ToNSImage(base64)
    }

    private func parseGoogleImageBase64(from responseString: String) -> String? {
        // Attempt to parse JSON and locate part.inlineData.data.base64 (with flexible traversal)
        guard let data = responseString.data(using: .utf8) else { return nil }
        do {
            let json = try JSONSerialization.jsonObject(with: data, options: [])
            if let found = searchForBase64(in: json, seenInlineData: false, seenData: false) {
                return stripDataURLPrefix(found)
            }
        } catch {
            // Not valid JSON; silently ignore and return nil
        }
        return nil
    }

    private func searchForBase64(in any: Any, seenInlineData: Bool, seenData: Bool) -> String? {
        if let dict = any as? [String: Any] {
            for (key, value) in dict {
                if key == "inlineData" || key == "inline_data" {
                    if let result = searchForBase64(in: value, seenInlineData: true, seenData: false) { return result }
                } else if key == "data" {
                    if seenInlineData {
                        // If value is string, return immediately
                        if let str = value as? String { return str }
                        // If value is dictionary, keep searching for base64 key
                        if let result = searchForBase64(in: value, seenInlineData: seenInlineData, seenData: true) { return result }
                    } else {
                        if let result = searchForBase64(in: value, seenInlineData: seenInlineData, seenData: true) { return result }
                    }
                } else if key == "base64", seenInlineData && seenData {
                    if let str = value as? String { return str }
                } else if key == "image_url" {
                    if let str = value as? String,
                       str.starts(with: "data:"),
                       str.contains(";base64,") {
                        if let commaIndex = str.firstIndex(of: ",") {
                            return String(str[str.index(after: commaIndex)...])
                        }
                    }
                } else {
                    if let result = searchForBase64(in: value, seenInlineData: seenInlineData, seenData: seenData) { return result }
                }
            }
        } else if let array = any as? [Any] {
            for element in array {
                if let result = searchForBase64(in: element, seenInlineData: seenInlineData, seenData: seenData) { return result }
            }
        }
        return nil
    }

    private func stripDataURLPrefix(_ base64: String) -> String {
        if let range = base64.range(of: ",") {
            let prefix = base64[..<range.lowerBound]
            if prefix.contains("base64") {
                return String(base64[range.upperBound...])
            }
        }
        return base64
    }

    private func decodeBase64ToNSImage(_ base64: String) -> NSImage? {
        guard let imgData = Data(base64Encoded: base64, options: [.ignoreUnknownCharacters]) else { return nil }
        return NSImage(data: imgData)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header with service logo and status
            HStack {
                HStack(spacing: 8) {
                    // Service logo (same as used in chat title)
                    Image(serviceLogoName)
                        .resizable()
                        .renderingMode(.template)
                        .interpolation(.high)
                        .frame(width: 16, height: 16)
                        .foregroundColor(.primary)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(response.serviceName)
                            .font(.system(size: chatFontSize - 1, weight: .medium))
                            .foregroundColor(.primary)
                        
                        Text(response.model)
                            .font(.system(size: chatFontSize - 3))
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                // Status indicator
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
            }
            
            // Progress indicator for ongoing requests
            if !response.isComplete && response.error == nil {
                HStack {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Processing...")
                        .font(.system(size: chatFontSize - 2))
                        .foregroundColor(.secondary)
                        .italic()
                }
            }
            
            Divider()
                .opacity(0.5)
            
            // Response content in scrollable area
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if let error = response.error {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundColor(.orange)
                            Text(errorMessage(for: error))
                                .font(.system(size: chatFontSize - 1))
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    } else if let image = googleImage {
                        Image(nsImage: image)
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                            )
                    } else if !response.response.isEmpty {
                        Text(response.response)
                            .font(.system(size: chatFontSize))
                            .foregroundColor(.primary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else if !response.isComplete {
                        Text("Waiting for response...")
                            .font(.system(size: chatFontSize))
                            .foregroundColor(.secondary)
                            .italic()
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(maxHeight: 400) // Limit height for better UX
            
            // Footer with Continue button and timestamp
            HStack {
                // Show Continue button only for completed successful responses
                if response.isComplete && response.error == nil && !response.response.isEmpty {
                    Button(action: {
                        onContinue()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.right.circle.fill")
                                .font(.system(size: 11))
                            Text("Continue")
                                .font(.system(size: chatFontSize - 3, weight: .medium))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(isHovered ? Color.blue.opacity(0.9) : Color.blue)
                        )
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        isHovered = hovering
                    }
                    .help("Continue conversation with this model")
                }
                
                Spacer()
                
                Text(timeString)
                    .font(.system(size: chatFontSize - 3))
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .background(cardBackgroundColor)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(borderColor, lineWidth: 1)
        )
    }
    
    private var statusColor: Color {
        if let error = response.error {
            return .red
        } else if response.isComplete {
            return .green
        } else {
            return .orange
        }
    }
    
    private var cardBackgroundColor: Color {
        Color(NSColor.textBackgroundColor)
    }
    
    private var borderColor: Color {
        if let _ = response.error {
            return .red.opacity(0.3)
        } else if response.isComplete {
            return .green.opacity(0.3)
        } else {
            return .orange.opacity(0.3)
        }
    }
    
    private var timeString: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: response.timestamp)
    }
    
    private func errorMessage(for error: APIError) -> String {
        switch error {
        case .unauthorized:
            return "Authentication failed - check API key"
        case .rateLimited:
            return "Rate limit exceeded - please wait"
        case .serverError(let message):
            return "Server error: \(message)"
        case .requestFailed(let error):
            return "Request failed: \(error.localizedDescription)"
        case .noApiService(let message):
            return message
        case .decodingFailed(let message):
            return "Decode error: \(message)"
        case .invalidResponse:
            return "Invalid response from service"
        case .unknown(let message):
            return "Unknown error: \(message)"
        }
    }
}

#Preview {
    MultiAgentResponseView(
        responses: [
            MultiAgentMessageManager.AgentResponse(
                serviceName: "OpenAI",
                serviceType: "chatgpt",
                model: "gpt-4",
                response: "This is a sample response from GPT-4. It's quite detailed and shows how the multi-agent system works.",
                isComplete: true,
                error: nil,
                timestamp: Date()
            ),
            MultiAgentMessageManager.AgentResponse(
                serviceName: "Anthropic",
                serviceType: "claude",
                model: "claude-3-sonnet",
                response: "Here's Claude's perspective on the question...",
                isComplete: false,
                error: nil,
                timestamp: Date()
            ),
            MultiAgentMessageManager.AgentResponse(
                serviceName: "Google",
                serviceType: "gemini",
                model: "gemini-pro",
                response: "",
                isComplete: true,
                error: APIError.unauthorized,
                timestamp: Date()
            )
        ],
        isProcessing: false,
        onContinue: { _ in }
    )
    .frame(width: 800, height: 500)
} 
