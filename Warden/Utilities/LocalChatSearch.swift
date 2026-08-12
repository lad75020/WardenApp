import CoreData
import Foundation

enum LocalChatSearch {
    /// Returns results only when the completed query still matches the active query.
    /// This keeps a cancelled/background search from replacing newer local results.
    static func publishedResults(
        activeQuery: String,
        query: String,
        results: Set<UUID>
    ) -> Set<UUID> {
        activeQuery == query ? results : []
    }

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
