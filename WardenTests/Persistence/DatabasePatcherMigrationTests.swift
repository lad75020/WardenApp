@testable import Warden
import CoreData
import XCTest

@MainActor
final class DatabasePatcherMigrationTests: XCTestCase {
    private var controller: PersistenceController!
    private var context: NSManagedObjectContext!

    override func setUp() {
        super.setUp()
        controller = PersistenceController(inMemory: true)
        context = controller.container.viewContext
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "APIServiceMigrationCompleted")
        UserDefaults.standard.removeObject(forKey: "gptToken")
        controller = nil
        context = nil
        super.tearDown()
    }

    func testExistingConfigurationPatchIsIdempotentWithoutTouchingChatRelationshipsOrKeychain() throws {
        let apiURL = AppConstants.apiUrlChatCompletions
        let model = AppConstants.chatGptDefaultModel
        let service = APIServiceEntity(context: context)
        service.id = UUID()
        service.name = "Chat GPT"
        service.type = "chatgpt"
        service.url = try XCTUnwrap(URL(string: apiURL))
        service.model = model
        let chat = ChatEntity(context: context)
        chat.id = UUID()
        chat.name = "Retained fixture"
        chat.createdDate = .distantPast
        chat.updatedDate = .distantPast
        chat.gptModel = model
        chat.apiService = service
        try context.save()

        UserDefaults.standard.set(false, forKey: "APIServiceMigrationCompleted")
        UserDefaults.standard.set(apiURL, forKey: "apiUrl")
        UserDefaults.standard.set(model, forKey: "gptModel")
        UserDefaults.standard.set("", forKey: "gptToken")
        DatabasePatcher.migrateExistingConfiguration(context: context)
        DatabasePatcher.migrateExistingConfiguration(context: context)

        let services = try context.fetch(NSFetchRequest<APIServiceEntity>(entityName: "APIServiceEntity"))
        XCTAssertEqual(services.count, 1)
        XCTAssertTrue(chat.apiService === service)
        XCTAssertEqual(chat.gptModel, model)
        XCTAssertNil(service.tokenIdentifier)
        XCTAssertEqual(UserDefaults.standard.string(forKey: "gptToken"), "")
        XCTAssertTrue(UserDefaults.standard.bool(forKey: "APIServiceMigrationCompleted"))
    }

    func testConfigurationMigrationUsesTokenManagerAsItsOnlyKeychainBoundary() throws {
        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(
            contentsOf: sourceRoot.appendingPathComponent("Warden/Utilities/DatabasePatcher.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("TokenManager.setToken(token, for: apiServiceId.uuidString)"))
        XCTAssertFalse(source.contains("Keychain("))
        XCTAssertFalse(source.contains("TokenManager.getToken"))
        XCTAssertFalse(source.contains("TokenManager.deleteToken"))
    }
}
