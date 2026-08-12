@testable import Warden
import CoreData
import XCTest

@MainActor
final class ChatHistoryRecoveryTests: XCTestCase {
    /// Keep each isolated in-memory container alive until the test process exits.
    /// Core Data may still drain context notifications after XCTest tears down a case.
    private static var retainedPersistenceControllers: [PersistenceController] = []

    private var persistenceController: PersistenceController!
    private var store: ChatStore!
    private var context: NSManagedObjectContext!

    override func setUp() {
        super.setUp()
        ValueTransformer.setValueTransformer(RequestMessagesTransformer(), forName: RequestMessagesTransformer.name)
        persistenceController = PersistenceController(inMemory: true)
        Self.retainedPersistenceControllers.append(persistenceController)
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

    func testLocalChatSearchPredicatesMatchMetadataAndMessagesCaseAndDiacriticInsensitively() throws {
        let titleChat = makeChat()
        titleChat.name = "Résumé planning"
        titleChat.systemMessage = ""

        let systemChat = makeChat()
        systemChat.name = "System"
        systemChat.systemMessage = "Use local café instructions"

        let personaChat = makeChat()
        personaChat.name = "Persona"
        let persona = PersonaEntity(context: context)
        persona.id = UUID()
        persona.name = "Élodie"
        personaChat.persona = persona

        let messageChat = makeChat()
        messageChat.name = "Message"
        messageChat.addToMessages(makeMessage(id: 400, timestamp: 1, body: "A private SÃO PAULO note"))

        let unmatchedChat = makeChat()
        unmatchedChat.name = "Unmatched"
        try context.save()

        let matchingIDs = try LocalChatSearch.matchingIDs(for: "resume", in: context)
        XCTAssertEqual(matchingIDs, Set([titleChat.id]))

        let systemIDs = try LocalChatSearch.matchingIDs(for: "CAFE", in: context)
        XCTAssertEqual(systemIDs, Set([systemChat.id]))

        let personaIDs = try LocalChatSearch.matchingIDs(for: "elodie", in: context)
        XCTAssertEqual(personaIDs, Set([personaChat.id]))

        let messageIDs = try LocalChatSearch.matchingIDs(for: "sao paulo", in: context)
        XCTAssertEqual(messageIDs, Set([messageChat.id]))
        XCTAssertFalse(messageIDs.contains(unmatchedChat.id))
    }

    func testLocalChatSearchIncludesNoMessageChatsAndDoesNotPublishStaleQueryResults() throws {
        let noMessageChat = makeChat()
        noMessageChat.name = "Roadmap"
        let messageChat = makeChat()
        messageChat.addToMessages(makeMessage(id: 401, timestamp: 1, body: "Roadmap details"))
        try context.save()

        let activeIDs = try LocalChatSearch.matchingIDs(for: "roadmap", in: context)
        let staleIDs = try LocalChatSearch.matchingIDs(for: "details", in: context)

        XCTAssertEqual(activeIDs, Set([noMessageChat.id, messageChat.id]))
        XCTAssertEqual(LocalChatSearch.publishedResults(activeQuery: "roadmap", query: "details", results: staleIDs), [])
        XCTAssertEqual(LocalChatSearch.publishedResults(activeQuery: "roadmap", query: "roadmap", results: activeIDs), activeIDs)
    }

    func testPinnedProjectAndArchivedProjectPersistAcrossContextReload() throws {
        let archivedProject = ProjectEntity(context: context)
        archivedProject.id = UUID()
        archivedProject.name = "Archived"
        archivedProject.isArchived = true
        archivedProject.createdAt = Date(timeIntervalSince1970: 1)
        archivedProject.updatedAt = Date(timeIntervalSince1970: 2)

        let pinned = makeChat()
        pinned.name = "Pinned"
        pinned.isPinned = true
        pinned.updatedDate = Date(timeIntervalSince1970: 10)
        pinned.project = archivedProject
        let recent = makeChat()
        recent.name = "Recent"
        recent.updatedDate = Date(timeIntervalSince1970: 20)
        recent.project = archivedProject
        try context.save()

        context.reset()
        let reloadedProject = try XCTUnwrap(try context.fetch(ProjectEntity.fetchRequest()).first)
        let reloadedChats = try context.fetch(ChatEntity.fetchRequest()).sorted {
            $0.isPinned == $1.isPinned ? $0.updatedDate > $1.updatedDate : $0.isPinned
        }

        XCTAssertTrue(reloadedProject.isArchived)
        XCTAssertEqual(reloadedChats.map(\.name), ["Pinned", "Recent"])
        XCTAssertTrue(reloadedChats.allSatisfy { $0.project === reloadedProject })
    }

    func testProjectSummaryStateIsLocallyDerivedForLoadingEmptyAndPopulatedData() {
        XCTAssertEqual(ProjectSummaryState.derive(isLoading: true, chats: [], messageCount: 0, activeDays: 0), .loading)
        XCTAssertEqual(ProjectSummaryState.derive(isLoading: false, chats: [], messageCount: 0, activeDays: 0), .empty)
        XCTAssertEqual(
            ProjectSummaryState.derive(isLoading: false, chats: [ProjectSummaryChat(id: UUID())], messageCount: 4, activeDays: 2),
            .populated(messageCount: 4, activeDays: 2)
        )
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

@MainActor
final class ChatSharingServiceTests: XCTestCase {
    private var fixture: InMemoryChatFixture!
    private var chat: ChatEntity!
    private let service = ChatSharingService.shared

    override func setUp() {
        super.setUp()
        ValueTransformer.setValueTransformer(RequestMessagesTransformer(), forName: RequestMessagesTransformer.name)
        fixture = InMemoryChatFixture()
        chat = fixture.chat
        chat.id = UUID(uuidString: "00000000-0000-0000-0000-000000000009")!
        chat.name = "Quarterly / Planning: Notes"
        chat.createdDate = Date(timeIntervalSince1970: 10)
        chat.updatedDate = Date(timeIntervalSince1970: 20)
        chat.gptModel = "fixture-model"
        chat.systemMessage = "Follow the local instructions."
        chat.requestMessages = [["role": "user", "content": "Authorization: Bearer should-not-export"]]

        let later = fixture.addMessage("Second message", own: false)
        later.id = 2
        later.name = "assistant"
        later.timestamp = Date(timeIntervalSince1970: 30)
        later.toolCallsJson = "{\"authorization\":\"secret\"}"
        let earlier = fixture.addMessage("First message", own: true)
        earlier.id = 1
        earlier.name = "user"
        earlier.timestamp = Date(timeIntervalSince1970: 25)
    }

    func testAllFormatsIncludeFullOrderedConversationWithoutDiagnosticFields() throws {
        for format in ChatExportFormat.allCases {
            let content = service.exportRepresentation(for: chat, format: format).content
            XCTAssertTrue(content.contains("Quarterly"))
            XCTAssertTrue(content.contains("Follow the local instructions."))
            XCTAssertLessThan(try XCTUnwrap(content.range(of: "First message")?.lowerBound), try XCTUnwrap(content.range(of: "Second message")?.lowerBound))
            XCTAssertFalse(content.contains("should-not-export"))
            XCTAssertFalse(content.contains("Authorization: Bearer ***"))
            XCTAssertFalse(content.contains("\"authorization\":\"secret\""))
        }

        let jsonData = try XCTUnwrap(service.exportRepresentation(for: chat, format: .json).content.data(using: .utf8))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: jsonData) as? [String: Any])
        let messages = try XCTUnwrap(object["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.map { $0["body"] as? String }, ["First message", "Second message"])
        XCTAssertNotNil(object["metadata"])
        XCTAssertEqual(object["systemMessage"] as? String, "Follow the local instructions.")
    }

    func testSuggestedFilenameAndTemporaryFilesAreSafeAndUnique() throws {
        let representation = service.exportRepresentation(for: chat, format: .markdown)
        XCTAssertEqual(representation.suggestedFilename, "Quarterly - Planning- Notes.md")
        XCTAssertFalse(representation.suggestedFilename.contains("/"))

        let first = try service.createTemporaryFile(for: representation, format: .markdown)
        let second = try service.createTemporaryFile(for: representation, format: .markdown)
        defer {
            try? FileManager.default.removeItem(at: first)
            try? FileManager.default.removeItem(at: second)
        }
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(try String(contentsOf: first), representation.content)
    }

    func testEmptyConversationWithMissingOptionalRelationshipsExportsSafely() throws {
        chat.systemMessage = ""
        XCTAssertNil(chat.persona)
        XCTAssertNil(chat.project)
        XCTAssertNil(chat.apiService)

        for format in ChatExportFormat.allCases {
            let content = service.exportRepresentation(for: chat, format: format).content
            XCTAssertTrue(content.contains("Quarterly"))
            XCTAssertFalse(content.contains("Follow the local instructions."))
        }
    }

    func testTemporaryWriteFailureLeavesConversationUnchanged() throws {
        let representation = service.exportRepresentation(for: chat, format: .plainText)
        let originalName = chat.name
        let originalBodies = chat.messagesArray.map(\.body)
        let blocker = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data().write(to: blocker)
        defer { try? FileManager.default.removeItem(at: blocker) }

        XCTAssertThrowsError(try service.createTemporaryFile(for: representation, format: .plainText, in: blocker))
        XCTAssertEqual(chat.name, originalName)
        XCTAssertEqual(chat.messagesArray.map(\.body), originalBodies)
    }

    func testCancellingSharePickerDeletesTemporaryFileOnce() throws {
        let representation = service.exportRepresentation(for: chat, format: .markdown)
        let temporaryURL = try service.createTemporaryFile(for: representation, format: .markdown)
        var completionCount = 0
        let delegate = TemporaryShareDelegate(fileURL: temporaryURL) {
            completionCount += 1
        }
        let picker = NSSharingServicePicker(items: [temporaryURL])

        delegate.sharingServicePicker(picker, didChoose: nil)
        delegate.sharingServicePicker(picker, didChoose: nil)

        XCTAssertFalse(FileManager.default.fileExists(atPath: temporaryURL.path))
        XCTAssertEqual(completionCount, 1)
    }
}

@MainActor
final class ChatBranchingManagerTests: XCTestCase {
    private var fixture: InMemoryChatFixture!
    private var context: NSManagedObjectContext!

    override func setUp() {
        super.setUp()
        ValueTransformer.setValueTransformer(RequestMessagesTransformer(), forName: RequestMessagesTransformer.name)
        fixture = InMemoryChatFixture()
        context = fixture.persistence.container.viewContext
    }

    func testBranchingErrorsDoNotExposeUnderlyingErrorDetails() {
        let sensitiveError = NSError(
            domain: "test",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Authorization: Bearer secret-token"]
        )

        XCTAssertEqual(
            BranchingError.saveFailed(sensitiveError).localizedDescription,
            "Warden could not save the branch. Please try again."
        )
        XCTAssertEqual(
            BranchingError.messageGenerationFailed(sensitiveError).localizedDescription,
            "Warden could not generate a response for the branch. Please try again."
        )
    }

    func testBranchCopiesOnlySelectedHistoryAndPreservesSourceSettings() async throws {
        let source = fixture.chat
        source.name = "Source"
        source.temperature = 0.7
        source.top_p = 0.9
        source.behavior = "Creative"
        source.systemMessage = "Keep context"
        source.gptModel = "source-model"
        source.requestMessages = [["role": "user", "content": "First"], ["role": "assistant", "content": "Second"]]

        let project = ProjectEntity(context: context)
        project.id = UUID()
        project.name = "Project"
        project.createdAt = Date(timeIntervalSince1970: 1)
        project.updatedAt = Date(timeIntervalSince1970: 1)
        source.project = project
        let persona = PersonaEntity(context: context)
        persona.id = UUID()
        persona.name = "Persona"
        source.persona = persona
        let targetService = APIServiceEntity(context: context)
        targetService.id = UUID()
        targetService.name = "Target"
        targetService.type = "Ollama"
        targetService.url = URL(string: "http://127.0.0.1:11434")
        targetService.model = "target-model"
        targetService.addedDate = Date(timeIntervalSince1970: 1)

        let first = fixture.addMessage("First", own: true)
        first.id = 10
        first.timestamp = Date(timeIntervalSince1970: 10)
        let boundary = fixture.addMessage("Second", own: false)
        boundary.id = 20
        boundary.timestamp = Date(timeIntervalSince1970: 20)
        let later = fixture.addMessage("Third", own: true)
        later.id = 30
        later.timestamp = Date(timeIntervalSince1970: 30)
        try context.save()

        let sourceBodies = source.messagesArray.map(\.body)
        let manager = ChatBranchingManager(viewContext: context, openChat: { _ in })
        let branch = try await manager.createBranch(
            from: source,
            at: boundary,
            origin: .assistant,
            targetService: targetService,
            targetModel: "target-model",
            autoGenerate: false
        )

        XCTAssertNotEqual(branch.objectID, source.objectID)
        XCTAssertTrue(branch.parentChat === source)
        XCTAssertEqual(branch.branchSourceMessageID, boundary.id)
        XCTAssertEqual(branch.branchSourceRole, BranchOrigin.assistant.rawValue)
        XCTAssertEqual(branch.messagesArray.map(\.body), ["First", "Second"])
        XCTAssertEqual(branch.messagesArray.map(\.id), [1, 2])
        XCTAssertEqual(branch.temperature, source.temperature)
        XCTAssertEqual(branch.top_p, source.top_p)
        XCTAssertEqual(branch.behavior, source.behavior)
        XCTAssertEqual(branch.systemMessage, source.systemMessage)
        XCTAssertTrue(branch.project === project)
        XCTAssertTrue(branch.persona === persona)
        XCTAssertTrue(branch.apiService === targetService)
        XCTAssertEqual(branch.requestMessages.map { $0["content"] }, ["First", "Second"])
        XCTAssertEqual(source.messagesArray.map(\.body), sourceBodies)
        XCTAssertEqual(source.messagesArray.count, 3)
        XCTAssertEqual(later.body, "Third")
    }

    func testBranchRejectsDeletedAndMismatchedSourcesWithoutOpeningOrSaving() async throws {
        let source = fixture.chat
        let boundary = fixture.addMessage("Boundary", own: true)
        let otherChat = fixture.makeChat(name: "Other")
        let mismatched = fixture.addMessage("Other message", own: true, to: otherChat)
        let service = validService()
        try context.save()
        var opened = 0
        let manager = ChatBranchingManager(viewContext: context, openChat: { _ in opened += 1 })

        context.delete(source)
        await XCTAssertThrowsErrorAsync(try await manager.createBranch(from: source, at: boundary, origin: .assistant, targetService: service, targetModel: "fixture", autoGenerate: false)) { error in
            guard case .invalidSourceChat = error as? BranchingError else {
                return XCTFail("Expected an invalid source error")
            }
        }
        context.rollback()
        await XCTAssertThrowsErrorAsync(try await manager.createBranch(from: source, at: mismatched, origin: .assistant, targetService: service, targetModel: "fixture", autoGenerate: false)) { error in
            guard case .invalidBranchMessage = error as? BranchingError else {
                return XCTFail("Expected an invalid branch message error")
            }
        }
        XCTAssertEqual(opened, 0)
    }

    func testBranchConfigurationFailureDoesNotOpenNewSelection() async throws {
        let boundary = fixture.addMessage("Branch from me", own: true)
        let invalidService = APIServiceEntity(context: context)
        invalidService.id = UUID()
        invalidService.name = "Unavailable"
        try context.save()
        var opened = 0
        let manager = ChatBranchingManager(viewContext: context, openChat: { _ in opened += 1 })

        await XCTAssertThrowsErrorAsync(try await manager.createBranch(from: fixture.chat, at: boundary, origin: .user, targetService: invalidService, targetModel: "fixture", autoGenerate: true)) { error in
            guard case .apiConfigurationFailed = error as? BranchingError else {
                return XCTFail("Expected an API configuration error")
            }
        }
        XCTAssertEqual(opened, 0)
    }

    func testFailedBranchSaveRollsBackAndDoesNotOpenNewSelection() async throws {
        let boundary = fixture.addMessage("Boundary", own: false)
        let service = validService()
        try context.save()
        let sourceID = fixture.chat.objectID
        var opened = 0
        let manager = ChatBranchingManager(
            viewContext: context,
            save: { _ in throw FixtureSaveError.forcedFailure },
            openChat: { _ in opened += 1 }
        )

        await XCTAssertThrowsErrorAsync(try await manager.createBranch(from: fixture.chat, at: boundary, origin: .assistant, targetService: service, targetModel: "fixture", autoGenerate: false)) { error in
            guard case .saveFailed = error as? BranchingError else {
                return XCTFail("Expected a save failure")
            }
        }
        XCTAssertEqual(opened, 0)
        XCTAssertEqual(try context.fetch(ChatEntity.fetchRequest()).map(\.objectID), [sourceID])
    }

    func testSuccessfulBranchCallbackIsTheOnlySelectionChangingRoute() async throws {
        let boundary = fixture.addMessage("Boundary", own: false)
        let service = validService()
        try context.save()
        let originalSelection = fixture.chat
        var selectedChat = originalSelection
        let manager = ChatBranchingManager(viewContext: context, openChat: { branch in
            selectedChat = branch
        })

        let branch = try await manager.createBranch(from: fixture.chat, at: boundary, origin: .assistant, targetService: service, targetModel: "fixture", autoGenerate: false)

        XCTAssertNil(BranchSelectionGate.branchToOpen(after: .failure(FixtureSaveError.forcedFailure)))
        XCTAssertTrue(selectedChat === branch)
    }

    private func validService() -> APIServiceEntity {
        let service = APIServiceEntity(context: context)
        service.id = UUID()
        service.name = "Local fixture"
        service.type = "Ollama"
        service.url = URL(string: "http://127.0.0.1:11434")
        service.model = "fixture"
        service.addedDate = Date(timeIntervalSince1970: 1)
        return service
    }

    private enum FixtureSaveError: Error {
        case forcedFailure
    }
}

private func XCTAssertThrowsErrorAsync(
    _ expression: @autoclosure () async throws -> Void,
    _ verify: (Error) -> Void = { _ in },
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        try await expression()
        XCTFail("Expected an error", file: file, line: line)
    } catch {
        verify(error)
    }
}
