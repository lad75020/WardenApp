import CoreData
@testable import Warden

/// Isolated Core Data graph for streaming tests. It creates no API service or credential state.
@MainActor
final class InMemoryChatFixture {
    let persistence = PersistenceController(inMemory: true)
    let chat: ChatEntity

    private let epoch = Date(timeIntervalSince1970: 1_000)

    init() {
        let context = persistence.container.viewContext
        chat = ChatEntity(context: context)
        chat.id = UUID()
        chat.name = "Fixture"
        chat.createdDate = epoch
        chat.updatedDate = epoch
        chat.systemMessage = ""
        chat.gptModel = "fixture"
        chat.messages = NSOrderedSet()
        chat.requestMessages = []
    }

    @discardableResult
    func addMessage(
        _ body: String,
        own: Bool,
        id: Int64? = nil,
        timestamp: Date? = nil,
        to chat: ChatEntity? = nil
    ) -> MessageEntity {
        let destination = chat ?? self.chat
        let message = MessageEntity(context: persistence.container.viewContext)
        message.id = id ?? Int64(destination.messages.count + 1)
        message.name = own ? "user" : "assistant"
        message.body = body
        message.own = own
        message.timestamp = timestamp ?? epoch.addingTimeInterval(TimeInterval(message.id))
        destination.addToMessages(message)
        return message
    }

    @discardableResult
    func makeProject(name: String = "Fixture Project", archived: Bool = false) -> ProjectEntity {
        let project = ProjectEntity(context: persistence.container.viewContext)
        project.id = UUID()
        project.name = name
        project.isArchived = archived
        project.createdAt = epoch
        project.updatedAt = epoch
        return project
    }

    @discardableResult
    func makePersona(name: String = "Fixture Persona") -> PersonaEntity {
        let persona = PersonaEntity(context: persistence.container.viewContext)
        persona.id = UUID()
        persona.name = name
        return persona
    }

    @discardableResult
    func makeChat(
        name: String = "Fixture",
        project: ProjectEntity? = nil,
        persona: PersonaEntity? = nil,
        pinned: Bool = false,
        updatedAt: Date? = nil,
        systemInstruction: String = ""
    ) -> ChatEntity {
        let chat = ChatEntity(context: persistence.container.viewContext)
        chat.id = UUID()
        chat.name = name
        chat.createdDate = epoch
        chat.updatedDate = updatedAt ?? epoch
        chat.systemMessage = systemInstruction
        chat.gptModel = "fixture"
        chat.messages = NSOrderedSet()
        chat.requestMessages = []
        chat.project = project
        chat.persona = persona
        chat.isPinned = pinned
        return chat
    }

    func selectBranchSource(in chat: ChatEntity, messageID: Int64) -> MessageEntity? {
        chat.messagesArray.first { $0.id == messageID }
    }
}
