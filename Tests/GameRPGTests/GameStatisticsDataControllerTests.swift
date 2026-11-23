// @copyright André Trettin

#if canImport(Testing)
@preconcurrency import CoreData
import Foundation
import Testing

@testable import GameRPG

@MainActor
@Suite("Game statistics persistence")
struct GameStatisticsDataControllerTests {
    // CODE_AUDIT_28 §7.3: one fetch of everything serves the dashboard range and the achievements.
    @Test("A range cut from the whole history equals fetching that range")
    func filteredEqualsFetchedRange() async throws {
        let store = try PersistentGameStatisticsTestStore()
        let sut = GameStatisticsDataController()
        let start = Date(timeIntervalSince1970: 1_704_067_200)
        let participant = GameStatisticParticipantDraft.fixture()
        for index in 0..<2 {
            let sessionId = UUID()
            let startedAt = start.addingTimeInterval(Double(index) * 40 * 86_400)
            try await sut.beginSession(
                .fixture(id: sessionId, startedAt: startedAt, localParticipantId: participant.participantId, participants: [participant]),
                in: store.context
            )
            try await sut.recordEvents(
                [(.fixture(id: UUID(), sessionId: sessionId, occurredAt: startedAt.addingTimeInterval(60), deduplicationKey: "e\(index)"), participant)],
                in: store.context
            )
            try await sut.finishSession(id: sessionId, at: startedAt.addingTimeInterval(2_400), reason: .stopped, in: store.context)
        }
        let interval = DateInterval(start: start.addingTimeInterval(30 * 86_400), end: start.addingTimeInterval(60 * 86_400))

        let everything = try await sut.fetchDataSet(interval: nil, direction: nil, in: store.context)
        let fetched = try await sut.fetchDataSet(interval: interval, direction: nil, in: store.context)
        let cut = everything.filtered(interval: interval, direction: nil)

        #expect(everything.sessions.count == 2)
        #expect(Set(cut.sessions.map(\.id)) == Set(fetched.sessions.map(\.id)))
        #expect(Set(cut.events.map(\.id)) == Set(fetched.events.map(\.id)))
        #expect(Set(cut.participants.map(\.sessionId)) == Set(fetched.participants.map(\.sessionId)))
        #expect(cut.sessions.count == 1)
        #expect(everything.filtered(interval: nil, direction: .incoming).events.isEmpty)
    }

    @Test("session lifecycle persists once and excludes disconnected time")
    func persistsSessionLifecycle() async throws {
        // Given
        let store = try PersistentGameStatisticsTestStore()
        let sut = GameStatisticsDataController()
        let startedAt = Date(timeIntervalSince1970: 1_704_067_200)
        let sessionID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1))
        let participantId = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2))
        let participant = GameStatisticParticipantDraft.fixture(participantId: participantId)
        let session = GameStatisticSessionDraft.fixture(
            id: sessionID,
            startedAt: startedAt,
            localParticipantId: participantId,
            participants: [participant]
        )
        let event = GameStatisticEventDraft.fixture(
            sessionId: sessionID,
            occurredAt: startedAt.addingTimeInterval(60)
        )

        // When
        try await sut.beginSession(session, in: store.context)
        try await sut.checkpointSession(
            id: sessionID,
            participants: [participant],
            at: startedAt.addingTimeInterval(600),
            in: store.context
        )
        try await sut.participantLeft(
            sessionID: sessionID,
            participantId: participantId,
            at: startedAt.addingTimeInterval(1_200),
            in: store.context
        )
        try await sut.checkpointSession(
            id: sessionID,
            participants: [participant],
            at: startedAt.addingTimeInterval(1_800),
            in: store.context
        )
        try await sut.recordEvents([(event, participant)], in: store.context)
        try await sut.recordEvents([(event, participant)], in: store.context)
        try await sut.finishSession(
            id: sessionID,
            at: startedAt.addingTimeInterval(2_400),
            reason: .stopped,
            in: store.context
        )
        let dataSet = try await sut.fetchDataSet(interval: nil, direction: nil, in: store.context)

        // Then
        let persistedSession = try #require(dataSet.sessions.first)
        let persistedParticipant = try #require(dataSet.participants.first)
        #expect(dataSet.sessions.count == 1)
        #expect(persistedSession.duration == 2_400)
        #expect(dataSet.events.count == 1)
        #expect(persistedParticipant.connectedDuration == 1_800)
        #expect(persistedParticipant.joinCount == 2)
    }

    @Test("unfinished sessions recover as complete")
    func recoversInterruptedSession() async throws {
        // Given
        let store = try PersistentGameStatisticsTestStore()
        let sut = GameStatisticsDataController()
        let startedAt = Date(timeIntervalSince1970: 1_704_067_200)
        let session = GameStatisticSessionDraft.fixture(startedAt: startedAt)
        try await sut.beginSession(session, in: store.context)
        try await sut.checkpointSession(
            id: session.id,
            participants: session.participants,
            at: startedAt.addingTimeInterval(900),
            in: store.context
        )

        // When
        try await sut.recoverInterruptedSessions(
            in: store.context,
            at: startedAt.addingTimeInterval(900 + GameStatisticsDataController.interruptedSessionIdleAge)
        )
        let dataSet = try await sut.fetchDataSet(interval: nil, direction: nil, in: store.context)

        // Then
        let persistedSession = try #require(dataSet.sessions.first)
        #expect(dataSet.sessions.count == 1)
        #expect(persistedSession.endedAt == startedAt.addingTimeInterval(900))
        #expect(persistedSession.duration == 900)
    }

    @Test("a session that was active recently is left open: another device may be playing it")
    func keepsRecentlyActiveSessionOpen() async throws {
        // Given
        let store = try PersistentGameStatisticsTestStore()
        let sut = GameStatisticsDataController()
        let startedAt = Date(timeIntervalSince1970: 1_704_067_200)
        let session = GameStatisticSessionDraft.fixture(startedAt: startedAt)
        try await sut.beginSession(session, in: store.context)
        try await sut.checkpointSession(
            id: session.id,
            participants: session.participants,
            at: startedAt.addingTimeInterval(900),
            in: store.context
        )

        // When
        try await sut.recoverInterruptedSessions(
            in: store.context,
            at: startedAt.addingTimeInterval(900 + GameStatisticsDataController.interruptedSessionIdleAge - 1)
        )
        let persisted = try await store.context.perform {
            let request = NSFetchRequest<RPGGameStatisticSession>(entityName: "RPGGameStatisticSession")
            return try store.context.fetch(request)
        }

        // Then
        #expect(persisted.count == 1)
        #expect(persisted.first?.isComplete == false)
    }

    @Test("completed sessions under the minimum duration are deleted with their events")
    func deletesShortSessions() async throws {
        // Given
        let store = try PersistentGameStatisticsTestStore()
        let sut = GameStatisticsDataController()
        let startedAt = Date(timeIntervalSince1970: 1_704_067_200)
        let shortId = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 11))
        let longId = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 12))
        let openId = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 13))
        let participant = GameStatisticParticipantDraft.fixture()
        for (id, duration) in [(shortId, 600.0), (longId, 900.0)] {
            try await sut.beginSession(
                .fixture(id: id, startedAt: startedAt, participants: [participant]),
                in: store.context
            )
            try await sut.recordEvents(
                [(.fixture(id: UUID(), sessionId: id, deduplicationKey: "event-\(id)"), participant)],
                in: store.context
            )
            try await sut.finishSession(
                id: id,
                at: startedAt.addingTimeInterval(duration),
                reason: .stopped,
                in: store.context
            )
        }
        try await sut.beginSession(
            .fixture(id: openId, startedAt: startedAt, participants: [participant]),
            in: store.context
        )

        // When
        try await sut.deleteSessions(shorterThan: 900, orRoles: [], in: store.context)
        let dataSet = try await sut.fetchDataSet(interval: nil, direction: nil, in: store.context)
        let openCount = try await store.context.perform {
            let request = NSFetchRequest<NSManagedObject>(entityName: "RPGGameStatisticSession")
            request.predicate = NSPredicate(format: "isComplete == NO")
            return try store.context.count(for: request)
        }

        // Then
        #expect(dataSet.sessions.map(\.id) == [longId])
        #expect(dataSet.events.map(\.sessionId) == [longId])
        #expect(openCount == 1)
    }

    @Test("a checkpoint fills the adventure and master a joining player did not know yet (CODE_AUDIT §5.11)")
    func checkpointFillsUnknownAdventureAndMaster() async throws {
        // Given: a player joined before the master's state arrived
        let store = try PersistentGameStatisticsTestStore()
        let sut = GameStatisticsDataController()
        let startedAt = Date(timeIntervalSince1970: 1_704_067_200)
        let sessionId = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 41))
        let participant = GameStatisticParticipantDraft.fixture()
        let adventureId = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 42))
        try await sut.beginSession(
            GameStatisticSessionDraft(
                id: sessionId,
                startedAt: startedAt,
                role: .player,
                localParticipantId: participant.participantId,
                localName: "Pia",
                characterId: nil,
                characterName: "",
                adventureId: nil,
                adventureTitle: "",
                masterId: nil,
                masterName: "",
                isDemo: false,
                participants: [participant]
            ),
            in: store.context
        )

        // When
        try await sut.checkpointSession(
            id: sessionId,
            participants: [participant],
            at: startedAt.addingTimeInterval(600),
            details: GameStatisticSessionDetails(masterId: nil, masterName: "Max", adventureId: adventureId, adventureTitle: "The Crypt"),
            in: store.context
        )
        try await sut.checkpointSession(
            id: sessionId,
            participants: [participant],
            at: startedAt.addingTimeInterval(1_200),
            details: GameStatisticSessionDetails(masterId: nil, masterName: "Other", adventureId: nil, adventureTitle: "Other"),
            in: store.context
        )
        try await sut.finishSession(id: sessionId, at: startedAt.addingTimeInterval(1_800), reason: .stopped, in: store.context)
        let dataSet = try await sut.fetchDataSet(interval: nil, direction: nil, in: store.context)

        // Then
        let persisted = try #require(dataSet.sessions.first)
        #expect(persisted.adventureId == adventureId)
        #expect(persisted.adventureTitle == "The Crypt")
        #expect(persisted.masterName == "Max", "a known master is never replaced")
    }

    @Test("a leftover session is closed at its own last activity, not at the next game's start")
    func leftoverSessionEndsAtItsLastActivity() async throws {
        // Given
        let store = try PersistentGameStatisticsTestStore()
        let sut = GameStatisticsDataController()
        let startedAt = Date(timeIntervalSince1970: 1_704_067_200)
        let nextGameStart = startedAt.addingTimeInterval(2 * 24 * 60 * 60)
        let sessionId = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 31))
        let participant = GameStatisticParticipantDraft.fixture()
        try await sut.beginSession(.fixture(id: sessionId, startedAt: startedAt, participants: [participant]), in: store.context)
        try await sut.checkpointSession(
            id: sessionId,
            participants: [participant],
            at: startedAt.addingTimeInterval(3_600),
            in: store.context
        )

        // When
        try await sut.finishLeftoverSession(id: sessionId, reason: .interrupted, notAfter: nextGameStart, in: store.context)
        let dataSet = try await sut.fetchDataSet(interval: nil, direction: nil, in: store.context)

        // Then
        let persisted = try #require(dataSet.sessions.first)
        #expect(persisted.duration == 3_600, "two idle days must not count as play time")
    }

    // CODE_AUDIT_28 §5.17
    @Test("a stop long after the last activity books the end at the last activity")
    func stopAfterIdleTailEndsAtLastActivity() async throws {
        let store = try PersistentGameStatisticsTestStore()
        let sut = GameStatisticsDataController()
        let startedAt = Date(timeIntervalSince1970: 1_704_067_200)
        let sessionId = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 41))
        let participant = GameStatisticParticipantDraft.fixture()
        try await sut.beginSession(.fixture(id: sessionId, startedAt: startedAt, participants: [participant]), in: store.context)
        try await sut.checkpointSession(id: sessionId, participants: [participant], at: startedAt.addingTimeInterval(3_600), in: store.context)
        // The stop's own checkpoint (roster and details) is no activity.
        try await sut.checkpointSession(
            id: sessionId,
            participants: [participant],
            at: startedAt.addingTimeInterval(10 * 3_600),
            advancesActivity: false,
            in: store.context
        )

        try await sut.finishSession(id: sessionId, at: startedAt.addingTimeInterval(10 * 3_600), reason: .stopped, in: store.context)
        let dataSet = try await sut.fetchDataSet(interval: nil, direction: nil, in: store.context)

        let persisted = try #require(dataSet.sessions.first)
        #expect(persisted.duration == 3_600, "the idle night is not play time")
    }

    @Test("a stop shortly after the last activity keeps the stop time")
    func stopWithinIdleLimitKeepsStopTime() async throws {
        let store = try PersistentGameStatisticsTestStore()
        let sut = GameStatisticsDataController()
        let startedAt = Date(timeIntervalSince1970: 1_704_067_200)
        let sessionId = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 42))
        let participant = GameStatisticParticipantDraft.fixture()
        try await sut.beginSession(.fixture(id: sessionId, startedAt: startedAt, participants: [participant]), in: store.context)
        try await sut.checkpointSession(id: sessionId, participants: [participant], at: startedAt.addingTimeInterval(3_600), in: store.context)

        try await sut.finishSession(id: sessionId, at: startedAt.addingTimeInterval(3_600 + 10 * 60), reason: .stopped, in: store.context)
        let dataSet = try await sut.fetchDataSet(interval: nil, direction: nil, in: store.context)

        #expect(try #require(dataSet.sessions.first).duration == 4_200)
    }

    @Test("completed observer and proxy sessions are deleted regardless of duration")
    func deletesUncountedRoleSessions() async throws {
        // Given
        let store = try PersistentGameStatisticsTestStore()
        let sut = GameStatisticsDataController()
        let startedAt = Date(timeIntervalSince1970: 1_704_067_200)
        let roles: [(UUID, GameStatisticRole)] = [
            (UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 21)), .player),
            (UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 22)), .gameMaster),
            (UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 23)), .observer),
            (UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 24)), .proxy)
        ]
        for (id, role) in roles {
            try await sut.beginSession(.fixture(id: id, startedAt: startedAt, role: role), in: store.context)
            try await sut.checkpointSession(id: id, participants: [], at: startedAt.addingTimeInterval(3_600), in: store.context)
            try await sut.finishSession(
                id: id,
                at: startedAt.addingTimeInterval(3_600),
                reason: .stopped,
                in: store.context
            )
        }

        // When
        try await sut.deleteSessions(shorterThan: 900, orRoles: [.observer, .proxy], in: store.context)
        let dataSet = try await sut.fetchDataSet(interval: nil, direction: nil, in: store.context)

        // Then
        #expect(Set(dataSet.sessions.map(\.id)) == Set(roles.prefix(2).map(\.0)))
    }

    @Test("deleting all statistics keeps the running game and its rows")
    func deleteAllKeepsActiveSession() async throws {
        // Given
        let store = try PersistentGameStatisticsTestStore()
        let sut = GameStatisticsDataController()
        let startedAt = Date(timeIntervalSince1970: 1_704_067_200)
        let activeId = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 21))
        let oldId = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 22))
        let participant = GameStatisticParticipantDraft.fixture()
        for id in [activeId, oldId] {
            try await sut.beginSession(.fixture(id: id, startedAt: startedAt, participants: [participant]), in: store.context)
            try await sut.recordEvents(
                [(.fixture(id: UUID(), sessionId: id, deduplicationKey: "event-\(id)"), participant)],
                in: store.context
            )
        }

        // When
        try await sut.deleteAll(keeping: activeId, in: store.context)
        let remaining = try await store.context.perform {
            try ["RPGGameStatisticSession", "RPGGameStatisticEvent", "RPGGameStatisticParticipant"].map { entityName in
                try store.context.count(for: NSFetchRequest<NSManagedObject>(entityName: entityName))
            }
        }
        let sessionIds = try await store.context.perform {
            try store.context.fetch(NSFetchRequest<RPGGameStatisticSession>(entityName: "RPGGameStatisticSession")).compactMap(\.uuid)
        }

        // Then
        #expect(sessionIds == [activeId])
        #expect(remaining == [1, 1, 1])
    }

    @Test("deleting all statistics without a running game removes everything")
    func deleteAllWithoutActiveSession() async throws {
        // Given
        let store = try PersistentGameStatisticsTestStore()
        let sut = GameStatisticsDataController()
        let participant = GameStatisticParticipantDraft.fixture()
        try await sut.beginSession(.fixture(startedAt: .now, participants: [participant]), in: store.context)

        // When
        try await sut.deleteAll(in: store.context)
        let count = try await store.context.perform {
            try store.context.count(for: NSFetchRequest<NSManagedObject>(entityName: "RPGGameStatisticSession"))
        }

        // Then
        #expect(count == 0)
    }

    @Test("after a failed save the unsaved statistics are dropped and a pending delete is undone")
    func discardsUnsavedStatistics() async throws {
        // Given
        let store = try PersistentGameStatisticsTestStore()
        let sut = GameStatisticsDataController()
        try await sut.beginSession(.fixture(startedAt: .now, participants: [.fixture()]), in: store.context)

        // When
        let result = try await store.context.perform {
            let saved = try #require(try store.context.fetch(NSFetchRequest<RPGGameStatisticSession>(entityName: "RPGGameStatisticSession")).first)
            store.context.delete(saved)
            let inserted = NSEntityDescription.insertNewObject(forEntityName: "RPGGameStatisticSession", into: store.context)
            sut.discardUnsavedStatistics(in: store.context)
            return (
                isInsertedDropped: inserted.isDeleted || inserted.isFault || !store.context.insertedObjects.contains(inserted),
                isDeleteUndone: !saved.isDeleted,
                hasPendingObjects: !(store.context.insertedObjects.isEmpty && store.context.updatedObjects.isEmpty && store.context.deletedObjects.isEmpty)
            )
        }

        // Then
        #expect(result.isInsertedDropped)
        #expect(result.isDeleteUndone)
        #expect(!result.hasPendingObjects)
    }
}

private struct PersistentGameStatisticsTestStore {
    let container: NSPersistentContainer
    let context: NSManagedObjectContext

    @MainActor
    init() throws {
        let model = try #require(NSManagedObjectModel.mergedModel(from: [GameRPG.Resources.bundle]))
        container = NSPersistentContainer(
            name: "GameStatisticsTests",
            managedObjectModel: model
        )

        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        description.shouldAddStoreAsynchronously = false
        container.persistentStoreDescriptions = [description]

        var loadError: (any Error)?
        container.loadPersistentStores { _, error in
            loadError = error
        }
        if let loadError {
            throw loadError
        }
        context = container.newBackgroundContext()
    }
}
#endif
