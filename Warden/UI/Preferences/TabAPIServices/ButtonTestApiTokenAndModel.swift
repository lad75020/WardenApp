import SwiftUI

struct ButtonTestApiTokenAndModel: View {
    @ObservedObject var viewModel: APIServiceDetailViewModel

    var body: some View {
        ButtonWithStatusIndicator(
            title: "Test Connection",
            action: viewModel.testConnection,
            isLoading: viewModel.isTestingConnection,
            hasError: viewModel.userNotification?.type == .error,
            errorMessage: viewModel.userNotification?.message,
            successMessage: "Service connection succeeded.",
            isSuccess: viewModel.userNotification?.type == .success
        )
        .accessibilityLabel("Test service connection")
        .accessibilityHint("Tests the current unsaved service configuration")
        .disabled(viewModel.isTestingConnection)
    }
}
