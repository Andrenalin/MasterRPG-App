// @copyright André Trettin

import CoreData
import CoreRPG
import Foundation
import os.log

// The fetch and snapshot side, split out of GameStatisticsDataController.swift. See CODE_AUDIT_29 §9.9.

extension GameStatisticsDataController {
    func fetchDataSet(
        interval: DateInterval?,
        direction: GameStatisticDirection?,
        in context: NSManagedObjectContext
    ) async throws -> GameStatisticsDataSet {
        try await context.perform {
            let sessionRequest = NSFetchRequest<RPGGameStatisticSession>(entityName: "RPGGameStatisticSession")
            var sessionPredicates = [
                NSPredicate(format: "isComplete == YES"),
                NSPredicate(format: "isDemo == NO")
            ]
            if let interval {
                sessionPredicates.append(NSPredicate(format: "startedAt >= %@ AND startedAt <= %@", interval.start as NSDate, interval.end as NSDate))
            }
            sessionRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: sessionPredicates)
            sessionRequest.sortDescriptors = [NSSortDescriptor(key: "startedAt", ascending: false)]
            sessionRequest.fetchBatchSize = 100

            let managedSessions = try context.fetch(sessionRequest)
            let sessionIds = managedSessions.compactMap(\.uuid)
            guard !sessionIds.isEmpty else { return .empty }
            let predicateSessionIds = sessionIds.map { $0 as NSUUID }

            let participantRequest = NSFetchRequest<RPGGameStatisticParticipant>(entityName: "RPGGameStatisticParticipant")
            participantRequest.predicate = NSPredicate(format: "sessionID IN %@", predicateSessionIds)
            participantRequest.sortDescriptors = [NSSortDescriptor(key: "connectedDurationSeconds", ascending: false)]
            participantRequest.fetchBatchSize = 200

            let eventRequest = NSFetchRequest<RPGGameStatisticEvent>(entityName: "RPGGameStatisticEvent")
            var eventPredicates = [NSPredicate(format: "sessionID IN %@", predicateSessionIds)]
            if let direction {
                eventPredicates.append(NSPredicate(format: "directionRaw == %d", direction.rawValue))
            }
            eventRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: eventPredicates)
            eventRequest.sortDescriptors = [NSSortDescriptor(key: "occurredAt", ascending: true)]
            eventRequest.fetchBatchSize = CoreDataFetchLimits.batchSize

            return GameStatisticsDataSet(
                sessions: managedSessions.compactMap(Self.sessionSnapshot),
                participants: try context.fetch(participantRequest).compactMap(Self.participantSnapshot),
                events: try context.fetch(eventRequest).compactMap(Self.eventSnapshot)
            )
        }
    }

    /// Every completed, non-demo game, newest first, without the events and participants
    /// `fetchDataSet` loads for the charts.
    func fetchSessions(in context: NSManagedObjectContext) async throws -> [GameStatisticSessionSnapshot] {
        try await context.perform {
            let request = NSFetchRequest<RPGGameStatisticSession>(entityName: "RPGGameStatisticSession")
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(format: "isComplete == YES"),
                NSPredicate(format: "isDemo == NO")
            ])
            request.sortDescriptors = [NSSortDescriptor(key: "startedAt", ascending: false)]
            request.fetchBatchSize = 100
            return try context.fetch(request).compactMap(Self.sessionSnapshot)
        }
    }

    static func sessionSnapshot(_ session: RPGGameStatisticSession) -> GameStatisticSessionSnapshot? {
        guard let id = session.uuid, let startedAt = session.startedAt else { return nil }
        return GameStatisticSessionSnapshot(
            id: id,
            startedAt: startedAt,
            endedAt: session.endedAt ?? session.lastActivityAt ?? startedAt,
            duration: session.durationSeconds,
            role: GameStatisticRole(rawValue: session.roleRaw) ?? .unknown,
            localName: session.localName ?? "",
            characterId: session.characterID,
            characterName: session.characterName ?? "",
            adventureId: session.adventureID,
            adventureTitle: session.adventureTitle ?? "",
            masterName: session.masterName ?? "",
            maxParticipantCount: Int(session.maxParticipantCount)
        )
    }

    static func participantSnapshot(_ participant: RPGGameStatisticParticipant) -> GameStatisticParticipantSnapshot? {
        guard let id = participant.uuid,
              let sessionId = participant.sessionID,
              let participantId = participant.participantID
        else { return nil }
        return GameStatisticParticipantSnapshot(
            id: id,
            sessionId: sessionId,
            participantId: participantId,
            characterId: participant.characterID,
            name: participant.name ?? "",
            characterName: participant.characterName ?? "",
            role: GameStatisticRole(rawValue: participant.roleRaw) ?? .unknown,
            connectedDuration: participant.connectedDurationSeconds,
            joinCount: Int(participant.joinCount),
            isLocal: participant.isLocal
        )
    }

    static func eventSnapshot(_ event: RPGGameStatisticEvent) -> GameStatisticEventSnapshot? {
        guard let id = event.uuid,
              let sessionId = event.sessionID,
              let occurredAt = event.occurredAt
        else { return nil }
        return GameStatisticEventSnapshot(
            id: id,
            sessionId: sessionId,
            occurredAt: occurredAt,
            kind: GameStatisticEventKind(rawValue: event.kindRaw) ?? .message,
            direction: GameStatisticDirection(rawValue: event.directionRaw) ?? .local,
            origin: GameStatisticOrigin(rawValue: event.originRaw) ?? .local,
            actorName: event.actorName ?? "",
            actorId: event.actorID,
            module: NetworkModules(rawValue: Int(event.moduleRaw)) ?? .none,
            outcome: GameStatisticDiceOutcome(rawValue: event.outcomeRaw) ?? .none,
            quantity: Int(event.quantity),
            numericValue: event.numericValue,
            payloadByteCount: event.payloadByteCount,
            success: event.success
        )
    }
}
