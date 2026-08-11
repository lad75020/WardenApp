import SwiftUI

struct WelcomeScreen: View {
    var chatsCount: Int
    var apiServiceIsPresent: Bool
    var customUrl: Bool
    let openPreferencesView: () -> Void
    let newChat: () -> Void

    @State private var showInteractiveOnboarding = false

    private var state: WelcomeExperienceState {
        .resolve(providerCount: apiServiceIsPresent ? 1 : 0, chatCount: chatsCount, hasSelection: false)
    }

    var body: some View {
        ZStack {
            AppConstants.backgroundWindow.ignoresSafeArea()
            if showInteractiveOnboarding {
                InteractiveOnboardingView(
                    openPreferencesView: openPreferencesView,
                    newChat: newChat,
                    onComplete: { showInteractiveOnboarding = false }
                )
            } else {
                VStack(spacing: 18) {
                    Spacer()
                    Image(systemName: "shield.lefthalf.filled")
                        .font(.system(size: 52))
                        .accessibilityHidden(true)
                    Text("Welcome to Warden").font(.system(size: 28, weight: .semibold))
                    Text(message).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    controls
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .padding(40)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("welcome.container")
            }
        }
    }

    @ViewBuilder private var controls: some View {
        switch state {
        case .setupRequired:
            Button("Start interactive setup") { showInteractiveOnboarding = true }
                .accessibilityIdentifier("welcome.startSetup")
            Button("Open Settings", action: openPreferencesView)
                .accessibilityIdentifier("welcome.openSettings")
        case .readyForFirstChat:
            Button("New Chat", action: newChat).accessibilityIdentifier("welcome.newChat")
        case .readyForSelection:
            Button("New Chat", action: newChat).accessibilityIdentifier("welcome.newChat")
            Button("View setup guide") { showInteractiveOnboarding = true }
                .accessibilityIdentifier("welcome.startSetup")
        case .contentSelected:
            EmptyView()
        }
    }

    private var message: String {
        switch state {
        case .setupRequired: "Start by configuring an AI provider in Settings."
        case .readyForFirstChat: "You are connected. Start your first conversation."
        case .readyForSelection: "Select a chat from the sidebar or start a new one."
        case .contentSelected: ""
        }
    }
}
