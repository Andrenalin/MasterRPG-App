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
                .compactMap { notification in
                    return localCtx.performAndWait {
                        ChangeType.allCases.compactMap { type -> ([DataType], ChangeType)? in
                            guard let changes = notification.userInfo?[type.userInfoKey] as? Set<NSManagedObjectID> else { return nil }
                            let objects = changes.filter { objectID in
                                objectID.entity == entity
                            }.compactMap { objectID in
                                localCtx.object(with: objectID) as? DataType
                            }
                            return (objects, type)
                        }
                    }
                }
                .sink { [weak self] changes in
                    self?.updateFromCloud(changes, handler: handler)
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

    func updateFromCloud(_ changes: [([DataType], ChangeType)], handler: @escaping @Sendable ([UUID], [UUID], [UUID]) -> Void) {
        var deletedIds: [UUID] = []
        var insertedIds: [UUID] = []
        var updatedIds: [UUID] = []
        guard !changes.isEmpty else { return }
        changes.forEach { objects, changeType in
            switch changeType {
            case .deleted:
                let newIds = objects.compactMap {
                    Logger.coreDataChangeObserver.debug("Deleted \($0, privacy: .public)")
                    return $0.uuid ?? UUID()
                }
                deletedIds.append(contentsOf: newIds)
            case .inserted:
                let newIds = objects.compactMap {
                    Logger.coreDataChangeObserver.debug("Inserted \($0, privacy: .public)")
                    return $0.uuid
                }
                insertedIds.append(contentsOf: newIds)
            case .updated:
                let newIds = objects.compactMap {
                    Logger.coreDataChangeObserver.debug("Updated \($0, privacy: .public)")
                    return $0.uuid
                }
                updatedIds.append(contentsOf: newIds)
            }
        }
        guard !deletedIds.isEmpty || !insertedIds.isEmpty || !updatedIds.isEmpty else { return }
        Logger.coreDataChangeObserver.debug("Handler D:\(deletedIds.count) I:\(insertedIds.count) U:\(updatedIds.count)")
        handler(deletedIds, insertedIds, updatedIds)
    }
}

private extension Logger {
    static let coreDataChangeObserver = Logger(subsystem: subsystem, category: "CoreDataChangeObserver")
}
