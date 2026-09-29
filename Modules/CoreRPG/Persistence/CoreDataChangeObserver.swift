// @copyright André Trettin

import Combine
import CoreData
import Foundation
import os.log
import Synchronization

/// Do NOT mark this `@MainActor`. `context` is frequently a private-queue background
/// context (see `CloudKitCoreDataPersistenceController`'s "background_context"), and Core
/// Data posts `didMergeChangesObjectIDsNotification` synchronously on that context's own
/// queue — not necessarily the main thread. `@MainActor` here makes the Combine closures
/// below inferred main-actor-isolated while Combine still invokes them off-thread, which
/// broke Core Data's thread confinement in practice (see git history for this file).
///
/// `observeCoreDataChanges(from:entity:handler:)` must be called once per instance: every call
/// site (one per module's `SyncDataController.init`, via `SyncDataControllable.startSyncObservation`)
/// constructs a fresh `CoreDataChangeObserver()` right before calling it, and a second call traps.
/// `observer` sits behind a `Mutex`, so the class is checked `Sendable`. See CODE_AUDIT_19 §4.1.
public final class CoreDataChangeObserver: Sendable {
    typealias DataType = (NSManagedObject & CoreDataId)

    private let observer = Mutex<Subscription?>(nil)

    public init() {}

    public func observeCoreDataChanges(from context: NSManagedObjectContext, entity: NSEntityDescription, handler: @escaping @Sendable ([UUID], [UUID], [UUID]) -> Void) {
        let localCtx = context
        // The entity's name (a `String`) crosses into the `@Sendable` closure instead of the
        // non-Sendable `NSEntityDescription`. See CODE_AUDIT_18 §3.18.
        let entityName = entity.name
        let subscription = NotificationCenter.default
            .publisher(for: NSManagedObjectContext.didMergeChangesObjectIDsNotification, object: localCtx)
            .compactMap { notification -> (deleted: [UUID], inserted: [UUID], updated: [UUID])? in
                // Pull the (Sendable) object ID sets out of the non-Sendable notification
                // before hopping onto the context's queue.
                let idsByType = ChangeType.allCases.reduce(into: [ChangeType: Set<NSManagedObjectID>]()) { result, type in
                    if let ids = notification.userInfo?[type.userInfoKey] as? Set<NSManagedObjectID> {
                        result[type] = ids
                    }
                }
                guard !idsByType.isEmpty else { return nil }

                // Resolve UUIDs inside the context's queue — NSManagedObjects must
                // never escape it; only the value-type UUIDs leave the block.
                return localCtx.performAndWait {
                    let deleted = Self.uuids(for: idsByType[.deleted], type: .deleted, context: localCtx, entityName: entityName)
                    let inserted = Self.uuids(for: idsByType[.inserted], type: .inserted, context: localCtx, entityName: entityName)
                    let updated = Self.uuids(for: idsByType[.updated], type: .updated, context: localCtx, entityName: entityName)
                    guard !deleted.isEmpty || !inserted.isEmpty || !updated.isEmpty else { return nil }
                    return (deleted, inserted, updated)
                }
            }
            .sink { deleted, inserted, updated in
                Logger.coreDataChangeObserver.debug("Handler D:\(deleted.count) I:\(inserted.count) U:\(updated.count)")
                handler(deleted, inserted, updated)
            }
        observer.withLock { observer in
            precondition(observer == nil, "observeCoreDataChanges(from:entity:handler:) must only be called once per CoreDataChangeObserver instance.")
            observer = Subscription(cancellable: subscription)
        }
    }
}

private extension CoreDataChangeObserver {
    /// The subscription captures the caller's non-Sendable `context`, so region analysis can't
    /// hand it to the `Mutex` as-is. The box is immutable and the cancellable is only cancelled
    /// (on deinit), which is thread-safe; this is the one unchecked spot left.
    struct Subscription: @unchecked Sendable {
        let cancellable: AnyCancellable
    }

    enum ChangeType: Equatable, CaseIterable {
        case inserted, deleted, updated

        var userInfoKey: String {
            switch self {
            case .inserted: return NSInsertedObjectIDsKey
            case .deleted: return NSDeletedObjectIDsKey
            case .updated: return NSUpdatedObjectIDsKey
            }
        }
    }

    /// Must run on the context's queue.
    static func uuids(for objectIDs: Set<NSManagedObjectID>?, type: ChangeType, context: NSManagedObjectContext, entityName: String?) -> [UUID] {
        guard let objectIDs else { return [] }
        return objectIDs.filter { $0.entity.name == entityName }.map { objectID in
            if let registered = context.registeredObject(for: objectID), !registered.isFault,
               let data = registered as? DataType, let uuid = data.uuid {
                return uuid
            }
            // Deleted objects may be unfulfillable faults — never fire them.
            if type != .deleted, let data = context.object(with: objectID) as? DataType, let uuid = data.uuid {
                return uuid
            }
            // The uuid is no longer resolvable (row already gone). A placeholder still
            // signals that a deletion happened; consumers diff against fetched ids.
            return UUID()
        }
    }
}

private extension Logger {
    static let coreDataChangeObserver = Logger(subsystem: subsystem, category: "CoreDataChangeObserver")
}
