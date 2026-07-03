// @copyright André Trettin

import Combine
@preconcurrency import CoreData
import Foundation
import os.log

public final class CoreDataChangeObserver: @unchecked Sendable {
    typealias DataType = (NSManagedObject & CoreDataId)

    private var observer: AnyCancellable?

    public init() {}

    public func observeCoreDataChanges(from context: NSManagedObjectContext, entity: NSEntityDescription, handler: @escaping @Sendable ([UUID], [UUID], [UUID]) -> Void) {
        let localCtx = context
        localCtx.performAndWait {
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
