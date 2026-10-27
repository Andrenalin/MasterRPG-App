// @copyright André Trettin

import CoreData
import Foundation

#if !os(tvOS)
import CoreSpotlight

/// Maps the activity of a tapped Core Spotlight result back to the item it names.
///
/// The Core Data index (`RpgSpotlightIndexerDelegate`) is the only one that carries entry text, and
/// its results arrive as a `CSSearchableItemActionType` activity whose identifier is the managed
/// object's URI. Entry rows resolve to their parent item and keep the entry id.
/// See CODE_AUDIT_AppIntents2 §4.1.
public struct SpotlightActivityRoute: Sendable, Equatable {
    public let module: NetworkModules
    public let itemId: UUID
    public let entryId: UUID?

    public init(module: NetworkModules, itemId: UUID, entryId: UUID? = nil) {
        self.module = module
        self.itemId = itemId
        self.entryId = entryId
    }

    /// The Core Data entity of each module's items. An entity named `<Item>Entry` is a row of that item.
    private static let itemEntities: [String: NetworkModules] = [
        "RPGAdventure": .adventure,
        "RPGAudio": .audio,
        "RPGDice": .dice,
        "RPGGenerator": .generator,
        "RPGMap": .map,
        "RPGPdf": .pdf,
        "RPGPhoto": .photo,
        "RPGRule": .rule,
        "RPGSpace": .space,
        "RPGTable": .table,
        "RPGValue": .value,
        "RPGWeather": .weather
    ]

    /// Whether `userActivity` is a tap on a Core Spotlight result.
    public static func isSpotlightActivity(_ userActivity: NSUserActivity) -> Bool {
        userActivity.activityType == CSSearchableItemActionType
    }

    /// The identifier Spotlight stored for the tapped result.
    public static func uniqueIdentifier(of userActivity: NSUserActivity) -> String? {
        userActivity.userInfo?[CSSearchableItemActivityIdentifier] as? String
    }

    /// Resolves the tapped result, or `nil` when it is not a Core Data object of this store or
    /// the object is gone.
    public static func resolve(_ userActivity: NSUserActivity, in context: NSManagedObjectContext) async -> SpotlightActivityRoute? {
        guard isSpotlightActivity(userActivity),
              let identifier = uniqueIdentifier(of: userActivity),
              let uri = URL(string: identifier),
              let coordinator = context.persistentStoreCoordinator,
              let objectId = coordinator.managedObjectID(forURIRepresentation: uri)
        else { return nil }
        return await context.perform {
            guard let object = try? context.existingObject(with: objectId) else { return nil }
            return route(for: object)
        }
    }

    /// The route of an item row or an entry row; `nil` for any other object. Run on the context's queue.
    static func route(for object: NSManagedObject) -> SpotlightActivityRoute? {
        guard let name = object.entity.name else { return nil }
        if let module = itemEntities[name] {
            guard let itemId = (object as? any CoreDataId)?.uuid else { return nil }
            return SpotlightActivityRoute(module: module, itemId: itemId, entryId: nil)
        }
        guard name.hasSuffix("Entry"),
              let module = itemEntities[String(name.dropLast("Entry".count))],
              let entryId = (object as? any CoreDataId)?.uuid,
              let parent = parent(of: object, parentEntityName: String(name.dropLast("Entry".count))),
              let itemId = (parent as? any CoreDataId)?.uuid
        else { return nil }
        return SpotlightActivityRoute(module: module, itemId: itemId, entryId: entryId)
    }

    private static func parent(of entry: NSManagedObject, parentEntityName: String) -> NSManagedObject? {
        let relationship = entry.entity.relationshipsByName.values.first {
            !$0.isToMany && $0.destinationEntity?.name == parentEntityName
        }
        guard let relationship else { return nil }
        return entry.value(forKey: relationship.name) as? NSManagedObject
    }
}
#endif
