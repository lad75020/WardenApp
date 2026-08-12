import Combine
import Foundation

/// Transient stream state owned by one conversation rather than a SwiftUI view instance.
@MainActor
final class ChatStreamingSession: ObservableObject {
    enum Phase: Equatable {
        case idle
        case starting
        case streaming
        case cancelling
        case finishing
        case failed
    }

    let conversationID: UUID
    @Published private(set) var requestID: UUID?
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var visibleAssistantText = ""
    @Published private(set) var terminalErrorDescription: String?

    private var finalizationClaimed = false
    private var acceptedAssistantText = ""
    private var pendingVisibleText = ""

    init(conversationID: UUID) {
        self.conversationID = conversationID
    }

    func begin(requestID: UUID) {
        self.requestID = requestID
        finalizationClaimed = false
        acceptedAssistantText = ""
        pendingVisibleText = ""
        visibleAssistantText = ""
        terminalErrorDescription = nil
        phase = .starting
    }

    @discardableResult
    func append(_ chunk: String, requestID: UUID) -> Bool {
        guard !chunk.isEmpty, self.requestID == requestID, !finalizationClaimed, phase != .cancelling else {
            return false
        }
        phase = .streaming
        acceptedAssistantText.append(contentsOf: chunk)
        pendingVisibleText.append(contentsOf: chunk)
        return true
    }

    /// Publishes accepted chunks in order. Keeping the accepted and visible buffers separate
    /// lets the transport remain responsive without forcing SwiftUI to render every byte.
    func publishPending(requestID: UUID, force: Bool = false) {
        guard self.requestID == requestID, !finalizationClaimed, !pendingVisibleText.isEmpty else { return }
        visibleAssistantText.append(contentsOf: pendingVisibleText)
        pendingVisibleText = ""
    }

    func finalText(requestID: UUID) -> String? {
        guard self.requestID == requestID else { return nil }
        publishPending(requestID: requestID, force: true)
        return acceptedAssistantText
    }

    @discardableResult
    func cancel(requestID: UUID) -> Bool {
        guard self.requestID == requestID, !finalizationClaimed, phase != .cancelling else { return false }
        phase = .cancelling
        // The accepted buffer remains available for one partial-response finalization,
        // but the view must acknowledge Stop without waiting for transport teardown.
        visibleAssistantText = ""
        pendingVisibleText = ""
        return true
    }

    @discardableResult
    func claimFinalization(requestID: UUID) -> Bool {
        guard self.requestID == requestID, !finalizationClaimed else { return false }
        finalizationClaimed = true
        phase = .finishing
        return true
    }

    func finish(requestID: UUID, errorDescription: String? = nil) {
        guard self.requestID == requestID else { return }
        terminalErrorDescription = errorDescription
        self.requestID = nil
        phase = errorDescription == nil ? .idle : .failed
        visibleAssistantText = ""
        acceptedAssistantText = ""
        pendingVisibleText = ""
    }

    func isCurrent(requestID: UUID) -> Bool {
        self.requestID == requestID && !finalizationClaimed && phase != .cancelling
    }

    func acceptsContinuation(requestID: UUID) -> Bool {
        self.requestID == requestID && phase == .finishing
    }

    func invalidate() {
        requestID = nil
        finalizationClaimed = true
        visibleAssistantText = ""
        acceptedAssistantText = ""
        pendingVisibleText = ""
        terminalErrorDescription = nil
        phase = .idle
    }
}

/// Recognizes attachment opening tags when a transport splits them across arbitrary chunks.
struct AttachmentMarkerDetector {
    private static let markers = ["<image-uuid>", "<file-uuid>"]
    private var suffix = ""

    mutating func consume(_ chunk: String) -> Bool {
        let combined = suffix + chunk
        let found = Self.markers.contains { combined.contains($0) }
        suffix = String(combined.suffix((Self.markers.map(\.count).max() ?? 1) - 1))
        return found
    }
}

@MainActor
final class ChatStreamingSessionRegistry {
    static let shared = ChatStreamingSessionRegistry()
    private var sessions: [UUID: ChatStreamingSession] = [:]

    func session(for conversationID: UUID) -> ChatStreamingSession {
        if let session = sessions[conversationID] { return session }
        let session = ChatStreamingSession(conversationID: conversationID)
        sessions[conversationID] = session
        return session
    }

    func invalidate(conversationID: UUID) {
        sessions[conversationID]?.invalidate()
        sessions[conversationID] = nil
    }
}
