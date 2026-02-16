
import AppKit
import SwiftUI

struct ButtonTestApiTokenAndModel: View {
    @Binding var lampColor: Color
    var gptToken: String = ""
    var gptModel: String = AppConstants.chatGptDefaultModel
    var apiUrl: String = AppConstants.apiUrlChatCompletions
    var apiType: String = "chatgpt"
    @State var testOk: Bool = false

    @Environment(\.managedObjectContext) private var viewContext

    var body: some View {
        ButtonWithStatusIndicator(
            title: "Test API token & model",
            action: { testAPI() },
            isLoading: lampColor == .yellow,
            hasError: lampColor == .red,
            errorMessage: nil,
            successMessage: "API connection test successful",
            isSuccess: testOk
        )
    }

    private func testAPI() {
        if apiType.lowercased() == "mlx" || apiType.lowercased() == "coreml llm" {
            guard ensureSecurityScopedAccessForLocalModel() else { return }
        }

        lampColor = .yellow
        self.testOk = false

        let config = APIServiceConfig(
            name: apiType,
            apiUrl: URL(string: apiUrl)!,
            apiKey: gptToken,
            model: gptModel
        )
        let apiService = APIServiceFactory.createAPIService(config: config)
        let messageManager = MessageManager(apiService: apiService, viewContext: viewContext)
        messageManager.testAPI(model: gptModel) { result in
            DispatchQueue.main.async {
                switch result {

                case .success(_):
                    lampColor = .green
                    self.testOk = true

                case .failure(let error):
                    lampColor = .red
                    let apiError = convertToAPIError(error)
                    let errorMessage =
                        switch apiError {
                        case .requestFailed(let error): error.localizedDescription
                        case .invalidResponse: "Response is invalid"
                        case .decodingFailed(let message): message
                        case .unauthorized: "Unauthorized"
                        case .rateLimited: "Rate limited"
                        case .serverError(let message): message
                        case .unknown(let message): message
                        case .noApiService(let message): message
                        }
                    showErrorAlert(error: errorMessage)
                }
            }
        }
    }

    private func convertToAPIError(_ error: Error) -> APIError {
        // If it's already an APIError, return it as-is
        if let apiError = error as? APIError {
            return apiError
        }
        
        // Convert NSURLError to appropriate APIError
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .timedOut:
                return .requestFailed(urlError)
            case .badServerResponse:
                return .invalidResponse
            case .userAuthenticationRequired:
                return .unauthorized
            default:
                return .requestFailed(urlError)
            }
        }
        
        // For any other error types, wrap them in .unknown
        return .unknown(error.localizedDescription)
    }

    private func showErrorAlert(error: String) {
        let alert = NSAlert()
        alert.messageText = "API Connection Test Failed"
        alert.informativeText = error
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func ensureSecurityScopedAccessForLocalModel() -> Bool {
        let modelPath = resolveFirstModelPath(from: gptModel)
        if modelPath.isEmpty {
            showErrorAlert(error: "No local model folder path is configured.")
            return false
        }

        if SecurityScopedBookmarkStore.resolveBookmarkURL(for: modelPath) != nil {
            return true
        }

        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = false
        panel.title = "Select Model Folder"
        panel.message = "Warden needs access to this folder to load the MLX model."
        panel.prompt = "Grant Access"

        if panel.runModal() == .OK, let url = panel.url {
            SecurityScopedBookmarkStore.storeBookmark(for: url)
            return true
        }

        showErrorAlert(error: "Access to the model folder was not granted.")
        return false
    }

    private func resolveFirstModelPath(from raw: String) -> String {
        let first = raw
            .split(whereSeparator: { $0 == "\n" || $0 == "," || $0 == ";" })
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty }) ?? ""

        if first.hasPrefix("file://"), let url = URL(string: first) {
            return url.standardizedFileURL.path
        }

        let expanded = (first as NSString).expandingTildeInPath
        return URL(fileURLWithPath: expanded).standardizedFileURL.path
    }
}
