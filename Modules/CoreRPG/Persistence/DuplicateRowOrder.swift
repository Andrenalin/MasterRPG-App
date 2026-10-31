// @copyright André Trettin

import CloudKit
import CoreData
import Synchronization

/// Orders rows that share one logical identity (the same `uuid`, the same tag) so that every
/// device keeps the same one when it removes the others.
///
/// The repair used to keep the row with the lowest object-ID URI. That URI holds the local
/// store's UUID and a local primary key, so it differs per device: after the same package was
/// imported on two devices, each could keep its own row and delete the other's CloudKit
/// record, and the item was gone on both. The CloudKit record name of a row is the same on
/// every device, so rows are ordered by it. A row with no record yet has never left this
/// device, so it sorts last and is the one removed. See CODE_AUDIT_21 §5.7.
enum DuplicateRowOrder {
    private struct WeakContainer: Sendable {
        weak var container: RPGPersistentCloudKitContainer?
    }

    private static let containers = Mutex<[ObjectIdentifier: WeakContainer]>([:])

    /// Makes `container`'s record names available to `sorted(_:)` for rows of its stores.
    static func register(_ container: RPGPersistentCloudKitContainer) {
        containers.withLock { containers in
            containers = containers.filter { $0.value.container != nil }
            containers[ObjectIdentifier(container.persistentStoreCoordinator)] = WeakContainer(container: container)
        }
    }

    /// How often a save asks for record names before it falls back to `sorted(_:)` and looks
    /// them up itself: duplicates that appear between the lookup and the save need names again.
    static let maxLookupAttempts = 3

    /// The record names of rows, looked up ahead of `sorted(_:using:)`.
    struct RecordNames: Sendable {
        fileprivate(set) var byObjectId: [NSManagedObjectID: String] = [:]
        fileprivate(set) var lookedUp: Set<NSManagedObjectID> = []

        /// Whether every row's record name was looked up. A temporary id has no record, so it
        /// needs no lookup.
        func covers(_ objects: [NSManagedObject]) -> Bool {
            objects.allSatisfy { $0.objectID.isTemporaryID || lookedUp.contains($0.objectID) }
        }
    }

    /// The record names of the rows with `objectIds`, looked up on a utility-priority task.
    /// The lookup waits on a queue of the CloudKit container that runs at utility priority, so
    /// a thread holding the context (often the main thread) must not wait for it: ask for the
    /// names first, then call `sorted(_:using:)` with them. See `RecordNames.covers(_:)`.
    static func recordNames(for objectIds: [NSManagedObjectID]) async -> RecordNames {
        await Task.detached(priority: .utility) { lookUp(objectIds) }.value
    }

    /// `objects` with the row to keep first, from record names looked up ahead. A row the
    /// lookup did not cover counts as having no record.
    static func sorted<Object: NSManagedObject>(_ objects: [Object], using names: RecordNames) -> [Object] {
        guard objects.count > 1 else { return objects }
        return objects.sorted { lhs, rhs in
            precedes(key(for: lhs, names: names.byObjectId), key(for: rhs, names: names.byObjectId))
        }
    }

    /// `objects` with the row to keep first. Call it only for rows that are duplicates of each
    /// other: the record names are looked up per call, and the caller waits for the lookup. Where
    /// the caller can await, `recordNames(for:)` and `sorted(_:using:)` do not block.
    static func sorted<Object: NSManagedObject>(_ objects: [Object]) -> [Object] {
        guard objects.count > 1 else { return objects }
        let coordinator = objects.first?.managedObjectContext?.persistentStoreCoordinator
        return sorted(objects, using: lookUp(objects.map(\.objectID), coordinator: coordinator))
    }

    /// The same order from the three parts it is made of: has no record, record name, local URI.
    /// Separate from the Core Data lookup so the rule itself can be tested.
    static func precedes(
        _ lhs: (recordName: String?, localURI: String),
        _ rhs: (recordName: String?, localURI: String)
    ) -> Bool {
        (lhs.recordName == nil ? 1 : 0, lhs.recordName ?? "", lhs.localURI) < (rhs.recordName == nil ? 1 : 0, rhs.recordName ?? "", rhs.localURI)
    }

    private static func key(for object: NSManagedObject, names: [NSManagedObjectID: String]) -> (recordName: String?, localURI: String) {
        (names[object.objectID], object.objectID.uriRepresentation().absoluteString)
    }

    private static func lookUp(_ objectIds: [NSManagedObjectID], coordinator: NSPersistentStoreCoordinator? = nil) -> RecordNames {
        var names = RecordNames()
        // A temporary id has no record and the lookup does not accept it.
        let ids = objectIds.filter { !$0.isTemporaryID }
        names.lookedUp = Set(ids)
        guard let coordinator = coordinator ?? ids.first?.persistentStore?.persistentStoreCoordinator,
              let container = containers.withLock({ $0[ObjectIdentifier(coordinator)]?.container }) else { return names }
        names.byObjectId = container.recordIDs(for: ids).mapValues(\.recordName)
        return names
    }
}
