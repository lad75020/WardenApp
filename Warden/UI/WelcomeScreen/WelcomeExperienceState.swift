import Foundation

enum WelcomeExperienceState: Equatable {
    case setupRequired
    case readyForFirstChat
    case readyForSelection
    case contentSelected

    static func resolve(providerCount: Int, chatCount: Int, hasSelection: Bool) -> Self {
        guard !hasSelection else { return .contentSelected }
        guard max(0, providerCount) > 0 else { return .setupRequired }
        return max(0, chatCount) == 0 ? .readyForFirstChat : .readyForSelection
    }
}

enum LastOpenedChatSelection {
    static func restore(_ storedValue: String, from chatIDs: [UUID]) -> UUID? {
        guard let storedID = UUID(uuidString: storedValue), chatIDs.contains(storedID) else { return nil }
        return storedID
    }
}
