// @copyright André Trettin

import CoreData
import CoreRPG
import Foundation
import os.log

// The delete side, split out of GameStatisticsDataController.swift. See CODE_AUDIT_29 §9.9.

extension GameStatisticsDataController {
    /// Deletes all statistics. The game that is running now (`activeSessionId`) is kept, so its
    /// later events still land in a session.
    func deleteAll(keeping activeSessionId: UUID? = nil, in context: NSManagedObjectContext) async throws {
        try await context.perform {
            try self.saveIfNeeded(context)
            for (entityName, idKey) in [
                ("RPGGameStatisticEvent", "sessionID"),
                ("RPGGameStatisticParticipant", "sessionID"),
                ("RPGGameStatisticSession", "uuid")
            ] {
                let predicate = activeSessionId.map {
                    NSPredicate(format: "\(idKey) == nil OR \(idKey) != %@", $0 as NSUUID)
                }
                try self.batchDelete(entityName: entityName, predicate: predicate, in: context)
            }
            try self.saveIfNeeded(context)
        }
    }

    /// Deletes the rows in the store with one batch request, not one fetched object at a time
    /// (months of events stalled "Delete All"), and merges the deletions into `context`. An
    /// in-memory store (tests) has no batch requests and deletes the fetched objects.
    /// Must run on `context`'s queue. See CODE_AUDIT_29 §7.1.
    private func batchDelete(entityName: String, predicate: NSPredicate?, in context: NSManagedObjectContext) throws {
        let isInMemory = context.persistentStoreCoordinator?.persistentStores.contains { $0.type == NSInMemoryStoreType } ?? true
        guard !isInMemory else {
            let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
            request.fetchBatchSize = CoreDataFetchLimits.batchSize
            request.predicate = predicate
            try context.fetch(request).forEach(context.delete)
            return
        }
        let fetch = NSFetchRequest<NSFetchRequestResult>(entityName: entityName)
        fetch.predicate = predicate
        let request = NSBatchDeleteRequest(fetchRequest: fetch)
        request.resultType = .resultTypeObjectIDs
        let result = try context.execute(request) as? NSBatchDeleteResult
        let deletedIds = result?.result as? [NSManagedObjectID] ?? []
        guard !deletedIds.isEmpty else { return }
        NSManagedObjectContext.mergeChanges(fromRemoteContextSave: [NSDeletedObjectsKey: deletedIds], into: [context])
    }

    /// Removes completed games that ran for less than `duration` seconds or were played in one of
    /// `roles`; events and participants go with them through the cascade rules.
    func deleteSessions(
        shorterThan duration: TimeInterval,
        orRoles roles: Set<GameStatisticRole>,
        in context: NSManagedObjectContext
    ) async throws {
        try await context.perform {
            let request = NSFetchRequest<RPGGameStatisticSession>(entityName: "RPGGameStatisticSession")
            request.predicate = NSPredicate(
                format: "isComplete == YES AND (durationSeconds < %f OR roleRaw IN %@)",
                duration,
                roles.map(\.rawValue)
            )
            request.fetchBatchSize = 100
            try context.fetch(request).forEach(context.delete)
            try self.saveIfNeeded(context)
        }
    }

    func deleteSessions(ids: Set<UUID>, in context: NSManagedObjectContext) async throws {
        guard !ids.isEmpty else { return }
        try await context.perform {
            let request = NSFetchRequest<RPGGameStatisticSession>(entityName: "RPGGameStatisticSession")
            request.predicate = NSPredicate(format: "uuid IN %@", ids.map { $0 as NSUUID })
            try context.fetch(request).forEach(context.delete)
            try self.saveIfNeeded(context)
        }
    }
}
