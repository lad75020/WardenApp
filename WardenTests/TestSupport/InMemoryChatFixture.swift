import CoreData
@testable import Warden

/// Isolated Core Data graph for streaming tests. It creates no API service or credential state.
@MainActor
final class InMemoryChatFixture {
    let persistence = PersistenceController(inMemory: true)
    let chat: ChatEntity

    init() {
        let context = persistence.container.viewContext
        chat = ChatEntity(context: context)
        chat.id = UUID()
        chat.name = "Fixture"
        chat.createdDate = Date()
        chat.updatedDate = Date()
        chat.systemMessage = ""
        chat.gptModel = "fixture"
        chat.messages = NSOrderedSet()
        chat.requestMessages = []
    }

    @discardableResult
    func addMessage(_ body: String, own: Bool) -> MessageEntity {
        let message = MessageEntity(context: persistence.container.viewContext)
        message.id = Int64(chat.messages.count + 1)
        message.body = body
        message.own = own
        message.timestamp = Date()
        chat.addToMessages(message)
        return message
    }
}
