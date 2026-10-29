// @copyright André Trettin

import CoreData
import CoreRPG
import Foundation
import os.log

struct GameStatisticsDataController: Sendable {
    func recoverInterruptedSessions(in context: NSManagedObjectContext, at date: Date = .now) async throws {
        try await context.perform {
            let request = NSFetchRequest<RPGGameStatisticSession>(entityName: "RPGGameStatisticSession")
            request.predicate = NSPredicate(format: "isComplete == NO")
            request.fetchBatchSize = 20

            for session in try context.fetch(request) {
                let end = min(session.lastActivityAt ?? session.startedAt ?? date, date)
                session.endedAt = end
                session.lastActivityAt = end
                session.durationSeconds = max(0, end.timeIntervalSince(session.startedAt ?? end))
                session.endedReasonRaw = GameStatisticSessionEndReason.interrupted.rawValue
                session.isComplete = true
                self.closeParticipants(for: session.uuid, in: context, at: end)
            }
            try self.saveIfNeeded(context)
        }
    }

    func beginSession(_ draft: GameStatisticSessionDraft, in context: NSManagedObjectContext) async throws {
        try await context.perform {
            let session = RPGGameStatisticSession(context: context)
            session.uuid = draft.id
            session.schemaVersion = 1
            session.startedAt = draft.startedAt
            session.lastActivityAt = draft.startedAt
            session.roleRaw = draft.role.rawValue
            session.localParticipantID = draft.localParticipantId
            session.localName = draft.localName
            session.characterID = draft.characterId
            session.characterName = draft.characterName
            session.adventureID = draft.adventureId
            session.adventureTitle = draft.adventureTitle
            session.masterID = draft.masterId
            session.masterName = draft.masterName
            session.isDemo = draft.isDemo
            session.isComplete = false
            session.maxParticipantCount = Int16(clamping: draft.participants.count)

            for participantDraft in draft.participants {
                self.insertParticipant(participantDraft, sessionID: draft.id, session: session, at: draft.startedAt, in: context)
            }
            try self.saveIfNeeded(context)
        }
    }

    func checkpointSession(
        id: UUID,
        participants: [GameStatisticParticipantDraft],
        at date: Date,
        in context: NSManagedObjectContext
    ) async throws {
        try await context.perform {
            guard let session = try self.fetchSession(id: id, in: context) else { return }
            let lastActivityAt = max(session.lastActivityAt ?? date, date)
            session.lastActivityAt = lastActivityAt
            session.durationSeconds = max(
                session.durationSeconds,
                max(0, lastActivityAt.timeIntervalSince(session.startedAt ?? lastActivityAt))
            )
            session.maxParticipantCount = max(session.maxParticipantCount, Int16(clamping: participants.count))
            try self.synchronizeParticipants(participants, sessionID: id, session: session, at: date, in: context)
            try self.saveIfNeeded(context)
        }
    }

    func finishSession(
        id: UUID,
        at date: Date,
        reason: GameStatisticSessionEndReason,
        in context: NSManagedObjectContext
    ) async throws {
        try await context.perform {
            guard let session = try self.fetchSession(id: id, in: context) else { return }
            session.endedAt = date
            session.lastActivityAt = date
            session.durationSeconds = max(0, date.timeIntervalSince(session.startedAt ?? date))
            session.endedReasonRaw = reason.rawValue
            session.isComplete = true
            self.closeParticipants(for: id, in: context, at: date)
            try self.saveIfNeeded(context)
        }
    }

    func participantLeft(
        sessionID: UUID,
        participantId: UUID,
        at date: Date,
        in context: NSManagedObjectContext
    ) async throws {
        try await context.perform {
            let request = NSFetchRequest<RPGGameStatisticParticipant>(entityName: "RPGGameStatisticParticipant")
            request.predicate = NSPredicate(
                format: "sessionID == %@ AND participantID == %@",
                sessionID as NSUUID,
                participantId as NSUUID
            )
            request.fetchLimit = 1
            guard let participant = try context.fetch(request).first else { return }
            let previousActivity = participant.lastSeenAt ?? participant.lastJoinedAt
            guard participant.isConnected,
                  previousActivity.map({ date >= $0 }) ?? true
            else { return }
            self.accrueConnectedDuration(for: participant, at: date)
            participant.isConnected = false
            try self.saveIfNeeded(context)
        }
    }

    /// Inserts a whole batch with one `perform` and one save, so a burst of pin/map messages
    /// costs one Core Data round trip instead of a fetch and save per message.
    /// See CODE_AUDIT_17 §7.1.
    func recordEvents(
        _ batch: [(draft: GameStatisticEventDraft, participant: GameStatisticParticipantDraft?)],
        in context: NSManagedObjectContext
    ) async throws {
        guard !batch.isEmpty else { return }
        try await context.perform {
            var sessions: [UUID: RPGGameStatisticSession] = [:]
            var seenKeys: Set<String> = []
            for (draft, participant) in batch {
                let session: RPGGameStatisticSession
                if let cached = sessions[draft.sessionId] {
                    session = cached
                } else if let fetched = try self.fetchSession(id: draft.sessionId, in: context) {
                    sessions[draft.sessionId] = fetched
                    session = fetched
                } else {
                    continue
                }
                guard !session.isComplete else {
                    Logger.statistics.debug("Skipped a statistics event of an already completed session")
                    continue
                }

                if !draft.deduplicationKey.isEmpty {
                    let scopedKey = "\(draft.sessionId.uuidString)|\(draft.deduplicationKey)"
                    guard seenKeys.insert(scopedKey).inserted else { continue }
                    let duplicateRequest = NSFetchRequest<RPGGameStatisticEvent>(entityName: "RPGGameStatisticEvent")
                    duplicateRequest.predicate = NSPredicate(
                        format: "sessionID == %@ AND deduplicationKey == %@",
                        draft.sessionId as NSUUID,
                        draft.deduplicationKey
                    )
                    duplicateRequest.fetchLimit = 1
                    guard try context.count(for: duplicateRequest) == 0 else { continue }
                }

                let event = RPGGameStatisticEvent(context: context)
                event.uuid = draft.id
                event.sessionID = draft.sessionId
                event.occurredAt = draft.occurredAt
                event.kindRaw = draft.kind.rawValue
                event.directionRaw = draft.direction.rawValue
                event.originRaw = draft.origin.rawValue
                event.actorID = draft.actorId
                event.actorCharacterID = draft.actorCharacterId
                event.actorName = draft.actorName
                event.targetID = draft.targetId
                event.itemID = draft.itemId
                event.itemName = draft.itemName
                event.moduleRaw = Int16(clamping: draft.module.rawValue)
                event.messageTypeRaw = draft.messageTypeRaw
                event.actionRaw = draft.actionRaw
                event.outcomeRaw = draft.outcome.rawValue
                event.quantity = draft.quantity
                event.numericValue = draft.numericValue
                event.resultValues = draft.resultValues
                event.checked = draft.checked
                event.payloadByteCount = draft.payloadByteCount
                event.messageCounter = draft.messageCounter
                event.proxyCounter = draft.proxyCounter
                event.dataVersion = draft.dataVersion
                event.success = draft.success
                event.deduplicationKey = draft.deduplicationKey
                event.session = session

                let lastActivityAt = max(session.lastActivityAt ?? draft.occurredAt, draft.occurredAt)
                session.lastActivityAt = lastActivityAt
                session.durationSeconds = max(
                    session.durationSeconds,
                    max(0, lastActivityAt.timeIntervalSince(session.startedAt ?? lastActivityAt))
                )
                session.transportMask |= Int32(1 << Int(draft.origin.rawValue))

                if let participant {
                    try self.synchronizeParticipants([participant], sessionID: draft.sessionId, session: session, at: draft.occurredAt, in: context)
                }
            }
            try self.saveIfNeeded(context)
        }
    }

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
            let sessionIDs = managedSessions.compactMap(\.uuid)
            guard !sessionIDs.isEmpty else { return .empty }
            let predicateSessionIDs = sessionIDs.map { $0 as NSUUID }

            let participantRequest = NSFetchRequest<RPGGameStatisticParticipant>(entityName: "RPGGameStatisticParticipant")
            participantRequest.predicate = NSPredicate(format: "sessionID IN %@", predicateSessionIDs)
            participantRequest.sortDescriptors = [NSSortDescriptor(key: "connectedDurationSeconds", ascending: false)]
            participantRequest.fetchBatchSize = 200

            let eventRequest = NSFetchRequest<RPGGameStatisticEvent>(entityName: "RPGGameStatisticEvent")
            var eventPredicates = [NSPredicate(format: "sessionID IN %@", predicateSessionIDs)]
            if let direction {
                eventPredicates.append(NSPredicate(format: "directionRaw == %d", direction.rawValue))
            }
            eventRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: eventPredicates)
            eventRequest.sortDescriptors = [NSSortDescriptor(key: "occurredAt", ascending: true)]
            eventRequest.fetchBatchSize = 500

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

    func deleteAll(in context: NSManagedObjectContext) async throws {
        try await context.perform {
            for entityName in ["RPGGameStatisticEvent", "RPGGameStatisticParticipant", "RPGGameStatisticSession"] {
                let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
                request.fetchBatchSize = 500
                try context.fetch(request).forEach(context.delete)
            }
            try self.saveIfNeeded(context)
        }
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

    private func fetchSession(id: UUID, in context: NSManagedObjectContext) throws -> RPGGameStatisticSession? {
        let request = NSFetchRequest<RPGGameStatisticSession>(entityName: "RPGGameStatisticSession")
        request.predicate = NSPredicate(format: "uuid == %@", id as NSUUID)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    private func synchronizeParticipants(
        _ drafts: [GameStatisticParticipantDraft],
        sessionID: UUID,
        session: RPGGameStatisticSession,
        at date: Date,
        in context: NSManagedObjectContext
    ) throws {
        guard !drafts.isEmpty else { return }
        let participantIDs = drafts.map { $0.participantId as NSUUID }
        let request = NSFetchRequest<RPGGameStatisticParticipant>(entityName: "RPGGameStatisticParticipant")
        request.predicate = NSPredicate(
            format: "sessionID == %@ AND participantID IN %@",
            sessionID as NSUUID,
            participantIDs
        )
        var existing: [UUID: RPGGameStatisticParticipant] = [:]
        for participant in try context.fetch(request) {
            if let participantId = participant.participantID, existing[participantId] == nil {
                existing[participantId] = participant
            }
        }

        for draft in drafts {
            if let participant = existing[draft.participantId] {
                let previousActivity = participant.lastSeenAt ?? participant.lastJoinedAt
                guard previousActivity.map({ date >= $0 }) ?? true else {
                    continue
                }

                if participant.isConnected {
                    self.accrueConnectedDuration(for: participant, at: date)
                } else {
                    guard previousActivity.map({ date > $0 }) ?? true else {
                        continue
                    }
                    participant.joinCount += 1
                    participant.lastJoinedAt = date
                    participant.isConnected = true
                }
                participant.lastSeenAt = date
                participant.name = draft.name
                participant.characterID = draft.characterId
                participant.characterName = draft.characterName
                participant.roleRaw = draft.role.rawValue
                participant.isLocal = draft.isLocal
                participant.isGameMaster = draft.isGameMaster
            } else {
                insertParticipant(draft, sessionID: sessionID, session: session, at: date, in: context)
            }
        }
        session.maxParticipantCount = max(session.maxParticipantCount, Int16(clamping: drafts.count))
    }

    private func insertParticipant(
        _ draft: GameStatisticParticipantDraft,
        sessionID: UUID,
        session: RPGGameStatisticSession,
        at date: Date,
        in context: NSManagedObjectContext
    ) {
        let participant = RPGGameStatisticParticipant(context: context)
        participant.uuid = UUID()
        participant.sessionID = sessionID
        participant.participantID = draft.participantId
        participant.characterID = draft.characterId
        participant.name = draft.name
        participant.characterName = draft.characterName
        participant.roleRaw = draft.role.rawValue
        participant.firstSeenAt = date
        participant.lastJoinedAt = date
        participant.lastSeenAt = date
        participant.connectedDurationSeconds = 0
        participant.joinCount = 1
        participant.isConnected = true
        participant.isLocal = draft.isLocal
        participant.isGameMaster = draft.isGameMaster
        participant.session = session
    }

    private func closeParticipants(for sessionID: UUID?, in context: NSManagedObjectContext, at date: Date) {
        guard let sessionID else { return }
        let request = NSFetchRequest<RPGGameStatisticParticipant>(entityName: "RPGGameStatisticParticipant")
        request.predicate = NSPredicate(format: "sessionID == %@", sessionID as NSUUID)
        guard let participants = try? context.fetch(request) else { return }
        for participant in participants {
            accrueConnectedDuration(for: participant, at: date)
            participant.lastSeenAt = max(participant.lastSeenAt ?? date, date)
            participant.isConnected = false
        }
    }

    private func accrueConnectedDuration(for participant: RPGGameStatisticParticipant, at date: Date) {
        guard participant.isConnected else { return }
        let previousActivity = participant.lastSeenAt ?? participant.lastJoinedAt ?? date
        guard date >= previousActivity else { return }
        participant.connectedDurationSeconds += max(0, date.timeIntervalSince(previousActivity))
        participant.lastSeenAt = date
    }

    private func saveIfNeeded(_ context: NSManagedObjectContext) throws {
        if context.hasChanges {
            try context.save()
        }
    }

    private static func sessionSnapshot(_ session: RPGGameStatisticSession) -> GameStatisticSessionSnapshot? {
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

    private static func participantSnapshot(_ participant: RPGGameStatisticParticipant) -> GameStatisticParticipantSnapshot? {
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

    private static func eventSnapshot(_ event: RPGGameStatisticEvent) -> GameStatisticEventSnapshot? {
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
            module: NetworkModules(rawValue: Int(event.moduleRaw)) ?? .none,
            outcome: GameStatisticDiceOutcome(rawValue: event.outcomeRaw) ?? .none,
            quantity: Int(event.quantity),
            numericValue: event.numericValue,
            payloadByteCount: event.payloadByteCount,
            success: event.success
        )
    }
}
