// @copyright André Trettin

import Combine
@preconcurrency import CoreData
import Foundation
import os.log

/// Do NOT mark this `@MainActor`. `context` is frequently a private-queue background
/// context (see `CloudKitCoreDataPersistenceController`'s "background_context"), and Core
/// Data posts `didMergeChangesObjectIDsNotification` synchronously on that context's own
/// queue — not necessarily the main thread. `@MainActor` here makes the Combine closures
/// below inferred main-actor-isolated while Combine still invokes them off-thread, which
/// broke Core Data's thread confinement in practice (see git history for this file).
///
/// `@unchecked Sendable` soundness precondition: `observeCoreDataChanges(from:entity:handler:)`
/// must be called exactly once per instance. `observer` is mutable, unsynchronized state — a
/// second call on the same instance would silently drop the first subscription's `Cancellable`
/// (with no compiler signal) rather than run two subscriptions side by side. Every current call
/// site (one per module's `SyncDataController.init`, via `SyncDataControllable.startSyncObservation`)
/// already satisfies this by constructing a fresh `CoreDataChangeObserver()` right before calling
/// it; `observeCoreDataChanges` itself enforces it defensively below. See CODE_AUDIT §3.6.
public final class CoreDataChangeObserver: @unchecked Sendable {
    typealias DataType = (NSManagedObject & CoreDataId)

    private var observer: AnyCancellable?

    public init() {}

    public func observeCoreDataChanges(from context: NSManagedObjectContext, entity: NSEntityDescription, handler: @escaping @Sendable ([UUID], [UUID], [UUID]) -> Void) {
        precondition(observer == nil, "observeCoreDataChanges(from:entity:handler:) must only be called once per CoreDataChangeObserver instance.")
        let localCtx = context
        observer = NotificationCenter.default
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
                    let deleted = Self.uuids(for: idsByType[.deleted], type: .deleted, context: localCtx, entity: entity)
                    let inserted = Self.uuids(for: idsByType[.inserted], type: .inserted, context: localCtx, entity: entity)
                    let updated = Self.uuids(for: idsByType[.updated], type: .updated, context: localCtx, entity: entity)
                    guard !deleted.isEmpty || !inserted.isEmpty || !updated.isEmpty else { return nil }
                    return (deleted, inserted, updated)
                }
            }
            .sink { deleted, inserted, updated in
                Logger.coreDataChangeObserver.debug("Handler D:\(deleted.count) I:\(inserted.count) U:\(updated.count)")
                handler(deleted, inserted, updated)
            }
    }
}

private extension CoreDataChangeObserver {
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
    static func uuids(for objectIDs: Set<NSManagedObjectID>?, type: ChangeType, context: NSManagedObjectContext, entity: NSEntityDescription) -> [UUID] {
        guard let objectIDs else { return [] }
        return objectIDs.filter { $0.entity == entity }.map { objectID in
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
