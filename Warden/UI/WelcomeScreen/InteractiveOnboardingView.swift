import SwiftUI

struct InteractiveOnboardingView: View {
    @State private var flow = OnboardingFlowState()
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    let openPreferencesView: () -> Void
    let newChat: () -> Void
    let onComplete: (() -> Void)?

    private let steps: [OnboardingFlowState.Step: OnboardingStep] = [
        .welcome: OnboardingStep(title: "Welcome to Warden", subtitle: "Get started with just a few steps", content: "Connect your AI provider and begin chatting.", icon: "sparkles"),
        .providerSetup: OnboardingStep(title: "Add an AI Provider", subtitle: "Connect to your favorite service", content: "Open Settings to add an AI provider. You can return to this guide afterwards.", icon: "server.rack"),
        .ready: OnboardingStep(title: "You're All Set", subtitle: "Ready to start chatting", content: "Your conversations are private and stored locally.", icon: "checkmark.circle.fill")
    ]

    var body: some View {
        let step = steps[flow.currentStep]!
        VStack(spacing: 0) {
            ProgressView(value: Double(flow.currentStep.rawValue + 1), total: Double(OnboardingFlowState.Step.allCases.count))
                .accessibilityIdentifier("onboarding.progress")
                .accessibilityLabel("Step \(flow.currentStep.rawValue + 1) of \(OnboardingFlowState.Step.allCases.count)")
                .padding(40)
            Spacer()
            VStack(spacing: 16) {
                Image(systemName: step.icon).font(.system(size: 48)).accessibilityHidden(true)
                Text(step.title).font(.system(size: 24, weight: .semibold))
                Text(step.subtitle).foregroundStyle(.secondary)
                Text(step.content).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .frame(maxWidth: 420)
            Spacer()
            HStack(spacing: 12) {
                if flow.currentStep != .welcome {
                    Button("Back") { flow.goBack() }
                        .accessibilityIdentifier("onboarding.back")
                }
                Spacer()
                if flow.currentStep == .providerSetup {
                    Button("Open Settings", action: openPreferencesView)
                        .accessibilityIdentifier("onboarding.openSettings")
                }
                if flow.currentStep != .ready {
                    Button("Next") { flow.goNext() }
                        .accessibilityIdentifier("onboarding.next")
                } else {
                    Button("Start") {
                        guard flow.consumeCompletion() else { return }
                        hasCompletedOnboarding = true
                        onComplete?()
                        newChat()
                    }
                    .accessibilityIdentifier("onboarding.start")
                    .disabled(flow.isCompleting)
                }
            }
            .padding(40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppConstants.backgroundWindow.ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("onboarding.container")
    }
}

private struct OnboardingStep {
    let title: String
    let subtitle: String
    let content: String
    let icon: String
}
