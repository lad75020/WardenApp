import Foundation

struct OnboardingFlowState: Equatable {
    enum Step: Int, CaseIterable, Equatable {
        case welcome
        case providerSetup
        case ready
    }

    private(set) var currentStep: Step
    private(set) var isCompleting = false

    init(currentStep: Step = .welcome) {
        self.currentStep = currentStep
    }

    mutating func goNext() {
        guard let next = Step(rawValue: currentStep.rawValue + 1) else { return }
        currentStep = next
    }

    mutating func goBack() {
        guard let previous = Step(rawValue: currentStep.rawValue - 1) else { return }
        currentStep = previous
    }

    mutating func consumeCompletion() -> Bool {
        guard currentStep == .ready, !isCompleting else { return false }
        isCompleting = true
        return true
    }
}
