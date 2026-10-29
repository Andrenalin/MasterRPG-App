// @copyright André Trettin

#if canImport(Testing)
import CoreData
import Foundation
import Testing

@testable import GameRPG

@MainActor
@Suite("Game statistics persistence")
struct GameStatisticsDataControllerTests {
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
            at: startedAt.addingTimeInterval(3_600)
        )
        let dataSet = try await sut.fetchDataSet(interval: nil, direction: nil, in: store.context)

        // Then
        let persistedSession = try #require(dataSet.sessions.first)
        #expect(dataSet.sessions.count == 1)
        #expect(persistedSession.endedAt == startedAt.addingTimeInterval(900))
        #expect(persistedSession.duration == 900)
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
