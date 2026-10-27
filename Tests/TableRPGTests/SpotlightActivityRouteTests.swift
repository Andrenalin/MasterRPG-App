// @copyright André Trettin

#if canImport(Testing)
import CoreData
import CoreRPG
import CoreSpotlight
import Foundation
import Testing

@testable import TableRPG

/// CODE_AUDIT_AppIntents2 §4.1 with a real store: the Core Data Spotlight index hands the tapped
/// result back as the managed object's URI, and the item row or the entry row must resolve to the
/// item (and the entry) the app opens.
@MainActor
struct SpotlightActivityRouteTests {
    private func tapActivity(on object: NSManagedObject) -> NSUserActivity {
        let activity = NSUserActivity(activityType: CSSearchableItemActionType)
        activity.userInfo = [CSSearchableItemActivityIdentifier: object.objectID.uriRepresentation().absoluteString]
        return activity
    }

    @Test func itemAndEntryRowsResolveToTheItem() async throws {
        let store = try SpotlightTestStore(bundles: [CoreRPG.Resources.bundle, TableRPG.Resources.bundle])
        let sut = DataController(context: store.writeContext, token: NetworkModules.table.token)
        let itemId = UUID()
        let entry = TableEntryModel(id: UUID(), name: "One", content: "First result")
        let model = TableModel(id: itemId, name: "Loot", description: "", tags: [], category: .loot, displayState: 0, tableType: .dice, diceId: nil, entries: [entry], parentId: nil)
        try sut.replaceSync(id: itemId, with: model)
        try await sut.save()

        let tables = try store.container.viewContext.fetch(NSFetchRequest<RPGTable>(entityName: "RPGTable"))
        let table = try #require(tables.first)
        let itemRoute = await SpotlightActivityRoute.resolve(tapActivity(on: table), in: store.container.viewContext)
        #expect(itemRoute == SpotlightActivityRoute(module: .table, itemId: itemId, entryId: nil))

        let entries = try store.container.viewContext.fetch(NSFetchRequest<RPGTableEntry>(entityName: "RPGTableEntry"))
        let entryRow = try #require(entries.first)
        let entryRoute = await SpotlightActivityRoute.resolve(tapActivity(on: entryRow), in: store.container.viewContext)
        #expect(entryRoute == SpotlightActivityRoute(module: .table, itemId: itemId, entryId: entry.id))
    }
}

private struct SpotlightTestStore {
    let container: NSPersistentContainer
    let writeContext: NSManagedObjectContext

    @MainActor
    init(bundles: [Bundle]) throws {
        let model = try #require(NSManagedObjectModel.mergedModel(from: bundles))
        container = NSPersistentContainer(name: "SpotlightActivityRouteTests-\(UUID().uuidString)", managedObjectModel: model)
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        description.shouldAddStoreAsynchronously = false
        container.persistentStoreDescriptions = [description]
        var loadError: (any Error)?
        container.loadPersistentStores { _, error in loadError = error }
        if let loadError { throw loadError }
        writeContext = container.newBackgroundContext()
    }
}
#endif
