import CoreData
import Foundation

enum LocalChatSearch {
    static func matchingIDs(
        for query: String,
        in context: NSManagedObjectContext
    ) throws -> Set<UUID> {
        guard !query.isEmpty else { return [] }

        let metadataRequest = NSFetchRequest<ChatEntity>(entityName: "ChatEntity")
        metadataRequest.predicate = NSCompoundPredicate(orPredicateWithSubpredicates: [
            NSPredicate(format: "name CONTAINS[cd] %@", query),
            NSPredicate(format: "systemMessage CONTAINS[cd] %@", query),
            NSPredicate(format: "persona.name CONTAINS[cd] %@", query)
        ])

        var matchingIDs = Set(try context.fetch(metadataRequest).map(\.id))

        let messageRequest = NSFetchRequest<ChatEntity>(entityName: "ChatEntity")
        messageRequest.predicate = NSPredicate(format: "ANY messages.body CONTAINS[cd] %@", query)
        matchingIDs.formUnion(try context.fetch(messageRequest).map(\.id))

        return matchingIDs
    }
}
