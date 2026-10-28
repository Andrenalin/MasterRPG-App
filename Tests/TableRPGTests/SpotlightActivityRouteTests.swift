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

    /// CODE_AUDIT_Since_3.0.1 §5.6: a trashed item and its entry rows open nothing from Spotlight
    /// and are not indexed, and they come back once the item is restored.
    @Test func trashedItemAndEntryRowsAreNotOpenedOrIndexed() async throws {
        let store = try SpotlightTestStore(bundles: [CoreRPG.Resources.bundle, TableRPG.Resources.bundle])
        let sut = DataController(context: store.writeContext, token: NetworkModules.table.token)
        let itemId = UUID()
        let entry = TableEntryModel(id: UUID(), name: "One", content: "First result")
        let trashed = TableModel(id: itemId, name: "Loot", description: "", tags: [], category: .loot, displayState: DisplayStateMask.totalHidden.rawValue, tableType: .dice, diceId: nil, entries: [entry], parentId: nil)
        try sut.replaceSync(id: itemId, with: trashed)
        try await sut.save()

        let context = store.container.viewContext
        let table = try #require(try context.fetch(NSFetchRequest<RPGTable>(entityName: "RPGTable")).first)
        let entryRow = try #require(try context.fetch(NSFetchRequest<RPGTableEntry>(entityName: "RPGTableEntry")).first)
        #expect(await SpotlightActivityRoute.resolve(tapActivity(on: table), in: context) == nil)
        #expect(await SpotlightActivityRoute.resolve(tapActivity(on: entryRow), in: context) == nil)
        #expect(SpotlightActivityRoute.isTrashed(table))
        #expect(SpotlightActivityRoute.isTrashed(entryRow))

        table.displayState = 0
        #expect(!SpotlightActivityRoute.isTrashed(table))
        #expect(!SpotlightActivityRoute.isTrashed(entryRow))
        #expect(await SpotlightActivityRoute.resolve(tapActivity(on: entryRow), in: context) == SpotlightActivityRoute(module: .table, itemId: itemId, entryId: entry.id))
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
