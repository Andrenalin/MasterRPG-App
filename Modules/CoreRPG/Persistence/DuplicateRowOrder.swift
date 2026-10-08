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

    /// `objects` with the row to keep first. Call it only for rows that are duplicates of each
    /// other: the record names are looked up per call.
    static func sorted<Object: NSManagedObject>(_ objects: [Object]) -> [Object] {
        guard objects.count > 1 else { return objects }
        let names = recordNames(for: objects)
        return objects.sorted { lhs, rhs in
            precedes(key(for: lhs, names: names), key(for: rhs, names: names))
        }
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

    private static func recordNames(for objects: [NSManagedObject]) -> [NSManagedObjectID: String] {
        guard let coordinator = objects.first?.managedObjectContext?.persistentStoreCoordinator,
              let container = containers.withLock({ $0[ObjectIdentifier(coordinator)]?.container }) else { return [:] }
        // A temporary id has no record and the lookup does not accept it.
        let ids = objects.map(\.objectID).filter { !$0.isTemporaryID }
        return container.recordIDs(for: ids).mapValues(\.recordName)
    }
}
