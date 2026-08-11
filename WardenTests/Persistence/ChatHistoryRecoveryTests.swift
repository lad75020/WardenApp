@testable import Warden
import CoreData
import XCTest

@MainActor
final class ChatHistoryRecoveryTests: XCTestCase {
    private static let testPersistenceController = PersistenceController(inMemory: true)
    private var persistenceController: PersistenceController!
    private var store: ChatStore!
    private var context: NSManagedObjectContext!

    override func setUp() {
        super.setUp()
        ValueTransformer.setValueTransformer(RequestMessagesTransformer(), forName: RequestMessagesTransformer.name)
        persistenceController = Self.testPersistenceController
        context = persistenceController.container.viewContext
        clearFixtureEntities()
        store = ChatStore(persistenceController: persistenceController)
    }

    override func tearDown() {
        store = nil
        context = nil
        persistenceController = nil
        super.tearDown()
    }

    func testUnavailableChatsAreRetainedByLoadAndClassified() async throws {
        let missingServiceChat = makeChat()
        let invalidServiceChat = makeChat(service: makeInvalidService())
        try context.save()

        let result = await store.loadFromCoreData()
        let backups = try result.get()

        XCTAssertEqual(backups.count, 2)
        XCTAssertEqual(store.availability(for: missingServiceChat), .missingService)
        XCTAssertEqual(store.availability(for: invalidServiceChat), .invalidService)
        XCTAssertFalse(missingServiceChat.isDeleted)
        XCTAssertFalse(invalidServiceChat.isDeleted)
    }

    func testRepairPreservesHistoryAndContext() throws {
        let project = ProjectEntity(entity: entityDescription(named: "ProjectEntity"), insertInto: context)
        project.id = UUID()
        project.name = "Project"
        project.createdAt = Date(timeIntervalSince1970: 1)
        project.updatedAt = Date(timeIntervalSince1970: 1)

        let persona = PersonaEntity(entity: entityDescription(named: "PersonaEntity"), insertInto: context)
        persona.id = UUID()
        persona.name = "Persona"

        let chat = makeChat()
        chat.project = project
        chat.persona = persona
        chat.requestMessages = [["role": "user", "content": "fixture"]]
        let message = MessageEntity(entity: entityDescription(named: "MessageEntity"), insertInto: context)
        message.id = 42
        message.name = "fixture"
        message.body = "fixture"
        message.timestamp = Date(timeIntervalSince1970: 2)
        message.own = true
        chat.addToMessages(message)
        let service = makeValidService()
        try context.save()

        let chatID = chat.id
        let messageIDs = chat.messagesArray.map(\.id)
        let requests = chat.requestMessages
        try store.repairUnavailableChat(chat, with: service)

        XCTAssertEqual(store.availability(for: chat), .available)
        XCTAssertEqual(chat.id, chatID)
        XCTAssertEqual(chat.messagesArray.map(\.id), messageIDs)
        XCTAssertEqual(chat.requestMessages, requests)
        XCTAssertTrue(chat.project === project)
        XCTAssertTrue(chat.persona === persona)
    }

    func testCandidatesExcludeInvalidServicesAndExplicitDeleteIsRequired() throws {
        let chat = makeChat()
        let validService = makeValidService()
        _ = makeInvalidService()
        try context.save()

        XCTAssertEqual(store.validRepairCandidates().map(\.objectID), [validService.objectID])
        try store.deleteUnavailableChat(chat)
        let remaining = try context.fetch(NSFetchRequest<ChatEntity>(entityName: "ChatEntity"))
        XCTAssertFalse(remaining.contains { $0.objectID == chat.objectID })
    }

    func testNoCandidateLeavesUnavailableChatUnchanged() throws {
        let chat = makeChat()
        try context.save()
        let originalID = chat.id

        XCTAssertTrue(store.validRepairCandidates().isEmpty)
        XCTAssertThrowsError(try store.repairUnavailableChat(chat, with: makeInvalidService()))
        XCTAssertEqual(chat.id, originalID)
        XCTAssertNil(chat.apiService)
        XCTAssertFalse(chat.isDeleted)
    }

    func testEmptyHistoryLoadsSafely() async throws {
        let result = await store.loadFromCoreData()
        let backups = try result.get()
        XCTAssertEqual(backups.count, 0)
    }

    func testLoadRetainsOrderedMessagesRelationshipsAndIsRepeatable() async throws {
        let service = makeValidService()
        let project = ProjectEntity(entity: entityDescription(named: "ProjectEntity"), insertInto: context)
        project.id = UUID()
        project.name = "Fixture project"
        project.createdAt = Date(timeIntervalSince1970: 1)
        project.updatedAt = Date(timeIntervalSince1970: 1)
        let persona = PersonaEntity(entity: entityDescription(named: "PersonaEntity"), insertInto: context)
        persona.id = UUID()
        persona.name = "Fixture persona"

        let olderChat = makeChat(service: service)
        olderChat.updatedDate = Date(timeIntervalSince1970: 10)
        let newerChat = makeChat(service: service)
        newerChat.updatedDate = Date(timeIntervalSince1970: 20)
        newerChat.project = project
        newerChat.persona = persona
        newerChat.addToMessages(makeMessage(id: 1, timestamp: 2))
        newerChat.addToMessages(makeMessage(id: 2, timestamp: 1))
        try context.save()

        let firstLoad = try await store.loadFromCoreData().get()
        let secondLoad = try await store.loadFromCoreData().get()

        XCTAssertEqual(firstLoad.map(\.id), [newerChat.id, olderChat.id])
        XCTAssertEqual(secondLoad.map(\.id), firstLoad.map(\.id))
        XCTAssertEqual(firstLoad.first?.messages.map(\.id), [1, 2])
        XCTAssertTrue(newerChat.project === project)
        XCTAssertTrue(newerChat.persona === persona)
        XCTAssertTrue(newerChat.apiService === service)
    }

    func testLegacyJSONImportIsIdempotentAndRetainsMissingNamedService() async throws {
        let legacyID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000017"))
        let backup = makeBackup(id: legacyID, serviceName: "Removed service")

        let firstImport = try await store.saveToCoreData(chats: [backup, backup]).get()
        let secondImport = try await store.saveToCoreData(chats: [backup]).get()
        let chats = try context.fetch(NSFetchRequest<ChatEntity>(entityName: "ChatEntity"))

        XCTAssertEqual(firstImport, 1)
        XCTAssertEqual(secondImport, 0)
        XCTAssertEqual(chats.count, 1)
        XCTAssertEqual(chats.first?.id, legacyID)
        XCTAssertNil(chats.first?.apiService)
        XCTAssertEqual(store.availability(for: try XCTUnwrap(chats.first)), .missingService)
    }

    func testFailedLegacyImportRollsBackPartialInserts() async throws {
        store = ChatStore(persistenceController: persistenceController) { _ in
            throw FixtureSaveError.forcedFailure
        }
        let legacyID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000018"))
        let backup = makeBackup(id: legacyID, serviceName: "Removed service")

        let failedImport = await store.saveToCoreData(chats: [backup])

        XCTAssertThrowsError(try failedImport.get())
        let chats = try context.fetch(NSFetchRequest<ChatEntity>(entityName: "ChatEntity"))
        XCTAssertTrue(chats.isEmpty)

        store = ChatStore(persistenceController: persistenceController)
        let retryImport = try await store.saveToCoreData(chats: [backup]).get()
        let retriedChats = try context.fetch(NSFetchRequest<ChatEntity>(entityName: "ChatEntity"))

        XCTAssertEqual(retryImport, 1)
        XCTAssertEqual(retriedChats.compactMap(\.id), [legacyID])
        XCTAssertNil(retriedChats.first?.apiService)
    }

    func testStaleSelectionDoesNotResolveOrRemoveHistory() throws {
        let chat = makeChat()
        try context.save()

        XCTAssertNil(LastOpenedChatSelection.restore(UUID().uuidString, from: [chat.id]))
        XCTAssertFalse(chat.isDeleted)
    }

    func testRequestMessageTransformerRejectsMalformedDataWithoutDeletingHistory() throws {
        let chat = makeChat()
        let transformer = RequestMessagesTransformer()
        XCTAssertNil(transformer.reverseTransformedValue(Data("malformed".utf8)))
        try context.save()

        XCTAssertEqual(store.availability(for: chat), .missingService)
        XCTAssertFalse(chat.isDeleted)
    }

    func testMalformedAttachmentReferencesRemainReadOnlyAndDoNotDeleteHistory() throws {
        let chat = makeChat()
        chat.addToMessages(makeMessage(
            id: 9,
            timestamp: 1,
            body: "<file-uuid>not-a-uuid</file-uuid><image-uuid>incomplete"
        ))
        try context.save()

        let messageBody = try XCTUnwrap(chat.messagesArray.first?.body)
        XCTAssertTrue(messageBody.containsAttachment)
        XCTAssertTrue(messageBody.extractFileUUIDs().isEmpty)
        XCTAssertTrue(messageBody.extractImageUUIDs().isEmpty)
        XCTAssertFalse(chat.isDeleted)
        XCTAssertEqual(chat.messagesArray.count, 1)
    }

    func testRecoverySourcesContainNoRecoveryLogging() throws {
        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let recoveryView = try String(
            contentsOf: sourceRoot.appendingPathComponent("Warden/UI/Chat/UnavailableChatRecoveryView.swift"),
            encoding: .utf8
        )
        XCTAssertFalse(recoveryView.contains("WardenLog"))
        XCTAssertFalse(recoveryView.contains("TokenManager"))
    }

    private func makeChat(service: APIServiceEntity? = nil) -> ChatEntity {
        let chat = ChatEntity(entity: entityDescription(named: "ChatEntity"), insertInto: context)
        chat.id = UUID()
        chat.name = "Fixture"
        chat.createdDate = Date(timeIntervalSince1970: 1)
        chat.updatedDate = Date(timeIntervalSince1970: 1)
        chat.gptModel = "fixture-model"
        chat.apiService = service
        return chat
    }

    private func makeValidService() -> APIServiceEntity {
        let service = APIServiceEntity(entity: entityDescription(named: "APIServiceEntity"), insertInto: context)
        service.id = UUID()
        service.name = "Valid fixture service"
        service.type = "Ollama"
        service.url = URL(string: "http://127.0.0.1:11434")
        service.model = "fixture-model"
        service.addedDate = Date(timeIntervalSince1970: 1)
        return service
    }

    private func makeInvalidService() -> APIServiceEntity {
        let service = APIServiceEntity(entity: entityDescription(named: "APIServiceEntity"), insertInto: context)
        service.id = UUID()
        service.name = "Invalid fixture service"
        service.addedDate = Date(timeIntervalSince1970: 1)
        return service
    }

    private func makeMessage(id: Int64, timestamp: TimeInterval, body: String = "fixture") -> MessageEntity {
        let message = MessageEntity(entity: entityDescription(named: "MessageEntity"), insertInto: context)
        message.id = id
        message.name = "fixture"
        message.body = body
        message.timestamp = Date(timeIntervalSince1970: timestamp)
        message.own = true
        return message
    }

    private func makeBackup(id: UUID, serviceName: String) -> ChatBackup {
        let json = """
        {
          "id": "\(id.uuidString)",
          "messages": [],
          "requestMessages": [{"role":"user","content":"fixture"}],
          "newChat": false,
          "name": "Legacy fixture",
          "apiServiceName": "\(serviceName)",
          "apiServiceType": "Ollama"
        }
        """
        return try! JSONDecoder().decode(ChatBackup.self, from: Data(json.utf8))
    }

    private enum FixtureSaveError: Error {
        case forcedFailure
    }

    private func entityDescription(named name: String) -> NSEntityDescription {
        guard let entity = NSEntityDescription.entity(forEntityName: name, in: context) else {
            fatalError("Missing test entity description")
        }
        return entity
    }

    private func clearFixtureEntities() {
        for entity in context.persistentStoreCoordinator?.managedObjectModel.entities ?? [] {
            guard let entityName = entity.name else { continue }
            let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
            for object in (try? context.fetch(request)) ?? [] {
                context.delete(object)
            }
        }
        try? context.save()
    }
}
