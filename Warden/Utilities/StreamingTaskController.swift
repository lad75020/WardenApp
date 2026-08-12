import Foundation

actor StreamingTaskController {
    static let shared = StreamingTaskController()
    private struct Entry {
        let requestID: UUID
        let task: Task<Void, Never>
    }

    private var entries: [UUID: Entry] = [:]
    private var cancelledRequests: Set<Request> = []
    private var invalidatedConversations: Set<UUID> = []

    private struct Request: Hashable {
        let conversationID: UUID
        let requestID: UUID
    }
    
    func replace(taskID: UUID, task: Task<Void, Never>) {
        replace(conversationID: taskID, requestID: taskID, task: task)
    }
    
    func cancelAndClear() {
        for entry in entries.values { entry.task.cancel() }
        entries.removeAll()
    }
    
    func clearIfCurrent(taskID: UUID) {
        clearIfCurrent(conversationID: taskID, requestID: taskID)
    }

    func replace(conversationID: UUID, requestID: UUID, task: Task<Void, Never>) {
        guard !invalidatedConversations.contains(conversationID),
              !cancelledRequests.contains(Request(conversationID: conversationID, requestID: requestID)) else {
            task.cancel()
            return
        }
        entries[conversationID]?.task.cancel()
        entries[conversationID] = Entry(requestID: requestID, task: task)
    }

    func cancel(conversationID: UUID) {
        entries[conversationID]?.task.cancel()
    }

    func cancel(conversationID: UUID, requestID: UUID) {
        cancelledRequests.insert(Request(conversationID: conversationID, requestID: requestID))
        guard entries[conversationID]?.requestID == requestID else { return }
        entries[conversationID]?.task.cancel()
    }

    func invalidate(conversationID: UUID) {
        invalidatedConversations.insert(conversationID)
        entries.removeValue(forKey: conversationID)?.task.cancel()
    }

    func isCurrent(conversationID: UUID, requestID: UUID) -> Bool {
        entries[conversationID]?.requestID == requestID
            && !invalidatedConversations.contains(conversationID)
            && !cancelledRequests.contains(Request(conversationID: conversationID, requestID: requestID))
    }

    /// Used before dispatch when the task has not necessarily registered yet.
    func shouldDispatch(conversationID: UUID, requestID: UUID) -> Bool {
        !invalidatedConversations.contains(conversationID)
            && !cancelledRequests.contains(Request(conversationID: conversationID, requestID: requestID))
    }

    func clearIfCurrent(conversationID: UUID, requestID: UUID) {
        guard entries[conversationID]?.requestID == requestID else { return }
        entries.removeValue(forKey: conversationID)
    }
}
