// @copyright André Trettin

import CoreData
import CoreRPG
import Foundation
import os.log

struct GameStatisticsDataController: Sendable {
    /// How long an unfinished session must have been idle before launch recovery completes it.
    /// The statistics sync between a user's devices, so an open session may be a game another
    /// device is playing right now; completing it from here would end that game's statistics (and
    /// the prune would delete it again if it is short). A session of this device that was cut off
    /// is recovered a day later. See CODE_AUDIT_22 §5.4.
    static let interruptedSessionIdleAge: TimeInterval = 24 * 60 * 60

    func recoverInterruptedSessions(
        in context: NSManagedObjectContext,
        at date: Date = .now,
        idleAge: TimeInterval = Self.interruptedSessionIdleAge
    ) async throws {
        try await context.perform {
            let request = NSFetchRequest<RPGGameStatisticSession>(entityName: "RPGGameStatisticSession")
            request.predicate = NSPredicate(format: "isComplete == NO")
            request.fetchBatchSize = 20

            for session in try context.fetch(request) {
                let lastActivity = session.lastActivityAt ?? session.startedAt ?? date
                guard date.timeIntervalSince(lastActivity) >= idleAge else { continue }
                let end = min(lastActivity, date)
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
                self.insertParticipant(participantDraft, sessionId: draft.id, session: session, at: draft.startedAt, in: context)
            }
            try self.saveIfNeeded(context)
        }
    }

    func checkpointSession(
        id: UUID,
        participants: [GameStatisticParticipantDraft],
        at date: Date,
        details: GameStatisticSessionDetails? = nil,
        advancesActivity: Bool = true,
        in context: NSManagedObjectContext
    ) async throws {
        try await context.perform {
            guard let session = try self.fetchSession(id: id, in: context) else { return }
            if let details {
                // Only fills what the session started without; a known value is never replaced.
                if session.adventureID == nil, let adventureId = details.adventureId {
                    session.adventureID = adventureId
                    session.adventureTitle = details.adventureTitle
                }
                if (session.masterName ?? "").isEmpty, !details.masterName.isEmpty {
                    session.masterID = details.masterId
                    session.masterName = details.masterName
                }
            }
            // The checkpoint of a stop only refreshes the roster and details: counting it as
            // activity would hide the idle time before the stop. See CODE_AUDIT_28 §5.17.
            let effectiveDate = advancesActivity ? date : min(date, session.lastActivityAt ?? date)
            let lastActivityAt = max(session.lastActivityAt ?? effectiveDate, effectiveDate)
            session.lastActivityAt = lastActivityAt
            session.durationSeconds = max(
                session.durationSeconds,
                max(0, lastActivityAt.timeIntervalSince(session.startedAt ?? lastActivityAt))
            )
            session.maxParticipantCount = max(session.maxParticipantCount, Int16(clamping: participants.count))
            try self.synchronizeParticipants(participants, sessionId: id, session: session, at: effectiveDate, in: context)
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
            // A stop long after the last activity (a game left open overnight) ends at that
            // activity: the idle tail was not play time. See CODE_AUDIT_28 §5.17.
            let startedAt = session.startedAt ?? date
            var end = date
            if let lastActivity = session.lastActivityAt,
               date.timeIntervalSince(lastActivity) > GameStatisticsController.idleTailLimit {
                end = max(lastActivity, startedAt)
            }
            session.endedAt = end
            session.lastActivityAt = end
            session.durationSeconds = max(0, end.timeIntervalSince(startedAt))
            session.endedReasonRaw = reason.rawValue
            session.isComplete = true
            self.closeParticipants(for: id, in: context, at: end)
            try self.saveIfNeeded(context)
        }
    }

    /// Closes a session that was still open when the next game starts, at the moment of its own
    /// last recorded activity rather than at the new game's start, so an orphan does not gain the
    /// idle time between the two games as play time. See CODE_AUDIT §5.12.
    func finishLeftoverSession(
        id: UUID,
        reason: GameStatisticSessionEndReason,
        notAfter limit: Date,
        in context: NSManagedObjectContext
    ) async throws {
        try await context.perform {
            guard let session = try self.fetchSession(id: id, in: context) else { return }
            let startedAt = session.startedAt ?? limit
            let end = min(max(session.lastActivityAt ?? startedAt, startedAt), limit)
            session.endedAt = end
            session.lastActivityAt = end
            session.durationSeconds = max(0, end.timeIntervalSince(startedAt))
            session.endedReasonRaw = reason.rawValue
            session.isComplete = true
            self.closeParticipants(for: id, in: context, at: end)
            try self.saveIfNeeded(context)
        }
    }

    func participantLeft(
        sessionId: UUID,
        participantId: UUID,
        at date: Date,
        in context: NSManagedObjectContext
    ) async throws {
        try await context.perform {
            let request = NSFetchRequest<RPGGameStatisticParticipant>(entityName: "RPGGameStatisticParticipant")
            request.predicate = NSPredicate(
                format: "sessionID == %@ AND participantID == %@",
                sessionId as NSUUID,
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
            // The keys already stored are fetched once per session for the whole batch (one
            // `IN` fetch), instead of one count per event. See CODE_AUDIT_26 §7.50.
            let storedKeys = try self.storedDeduplicationKeys(for: batch.map(\.draft), in: context)
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
                    guard !storedKeys.contains(scopedKey) else { continue }
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
                    try self.synchronizeParticipants([participant], sessionId: draft.sessionId, session: session, at: draft.occurredAt, in: context)
                }
            }
            try self.saveIfNeeded(context)
        }
    }

    /// The `sessionId|deduplicationKey` pairs of the drafts that are already stored.
    private func storedDeduplicationKeys(
        for drafts: [GameStatisticEventDraft],
        in context: NSManagedObjectContext
    ) throws -> Set<String> {
        var keysBySession: [UUID: Set<String>] = [:]
        for draft in drafts where !draft.deduplicationKey.isEmpty {
            keysBySession[draft.sessionId, default: []].insert(draft.deduplicationKey)
        }
        var stored: Set<String> = []
        for (sessionId, keys) in keysBySession {
            let request = NSFetchRequest<NSDictionary>(entityName: "RPGGameStatisticEvent")
            request.resultType = .dictionaryResultType
            request.propertiesToFetch = ["deduplicationKey"]
            request.predicate = NSPredicate(
                format: "sessionID == %@ AND deduplicationKey IN %@",
                sessionId as NSUUID,
                Array(keys)
            )
            for row in try context.fetch(request) {
                if let key = row["deduplicationKey"] as? String {
                    stored.insert("\(sessionId.uuidString)|\(key)")
                }
            }
        }
        return stored
    }

    func fetchSession(id: UUID, in context: NSManagedObjectContext) throws -> RPGGameStatisticSession? {
        let request = NSFetchRequest<RPGGameStatisticSession>(entityName: "RPGGameStatisticSession")
        request.predicate = NSPredicate(format: "uuid == %@", id as NSUUID)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    private func synchronizeParticipants(
        _ drafts: [GameStatisticParticipantDraft],
        sessionId: UUID,
        session: RPGGameStatisticSession,
        at date: Date,
        in context: NSManagedObjectContext
    ) throws {
        guard !drafts.isEmpty else { return }
        let participantIds = drafts.map { $0.participantId as NSUUID }
        let request = NSFetchRequest<RPGGameStatisticParticipant>(entityName: "RPGGameStatisticParticipant")
        request.predicate = NSPredicate(
            format: "sessionID == %@ AND participantID IN %@",
            sessionId as NSUUID,
            participantIds
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
                insertParticipant(draft, sessionId: sessionId, session: session, at: date, in: context)
            }
        }
        session.maxParticipantCount = max(session.maxParticipantCount, Int16(clamping: drafts.count))
    }

    private func insertParticipant(
        _ draft: GameStatisticParticipantDraft,
        sessionId: UUID,
        session: RPGGameStatisticSession,
        at date: Date,
        in context: NSManagedObjectContext
    ) {
        let participant = RPGGameStatisticParticipant(context: context)
        participant.uuid = UUID()
        participant.sessionID = sessionId
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

    private func closeParticipants(for sessionId: UUID?, in context: NSManagedObjectContext, at date: Date) {
        guard let sessionId else { return }
        let request = NSFetchRequest<RPGGameStatisticParticipant>(entityName: "RPGGameStatisticParticipant")
        request.predicate = NSPredicate(format: "sessionID == %@", sessionId as NSUUID)
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

    func saveIfNeeded(_ context: NSManagedObjectContext) throws {
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            discardUnsavedStatistics(in: context)
            throw error
        }
    }

    /// After a failed save the inserted rows stay pending in the context, and the caller's retry
    /// inserts them a second time. Only the statistics objects are dropped, in case a caller hands
    /// in a context it shares with other modules (the model has its own, see
    /// `GameStatisticsModel.statisticsContext(sharing:)`).
    func discardUnsavedStatistics(in context: NSManagedObjectContext) {
        func isStatistics(_ object: NSManagedObject) -> Bool {
            object.entity.name?.hasPrefix("RPGGameStatistic") == true
        }
        for object in context.insertedObjects where isStatistics(object) {
            context.delete(object)
        }
        for object in context.updatedObjects.union(context.deletedObjects) where isStatistics(object) {
            context.refresh(object, mergeChanges: false)
        }
        // The deleted inserts stay in the change sets until the context has processed them.
        context.processPendingChanges()
    }

}
