// @copyright André Trettin

#if canImport(Testing)
import CoreRPG
import Foundation
import Testing

@testable import GameRPG

@Suite("Game statistics aggregation")
struct GameStatisticsControllerTests {
    @Test("aggregates time, roles, content, dice, party, and network data")
    func aggregatesDashboardData() throws {
        // Given
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let firstStart = Date(timeIntervalSince1970: 1_704_151_800) // 2024-01-01 23:30 UTC
        let secondStart = Date(timeIntervalSince1970: 1_704_276_000) // 2024-01-03 10:00 UTC
        let adventureId = deterministicUUID(40)
        let characterId = deterministicUUID(30)
        let sessions: [GameStatisticSessionSnapshot] = [
            .fixture(
                id: deterministicUUID(1),
                startedAt: firstStart,
                duration: 7_200,
                role: .gameMaster,
                characterId: nil,
                characterName: "",
                adventureId: adventureId,
                adventureTitle: "The Long Night"
            ),
            .fixture(
                id: deterministicUUID(2),
                startedAt: secondStart,
                duration: 3_600,
                role: .player,
                characterId: characterId,
                characterName: "Aria",
                adventureId: adventureId,
                adventureTitle: "The Long Night",
                maxParticipantCount: 5
            )
        ]
        let events: [GameStatisticEventSnapshot] = [
            .fixture(id: deterministicUUID(10), sessionId: sessions[0].id, outcome: .critical, quantity: 2),
            .fixture(id: deterministicUUID(11), sessionId: sessions[1].id, outcome: .fumble),
            .fixture(
                id: deterministicUUID(12),
                sessionId: sessions[0].id,
                kind: .contentShared,
                module: .photo,
                outcome: .none,
                payloadByteCount: 512
            ),
            .fixture(
                id: deterministicUUID(13),
                sessionId: sessions[0].id,
                kind: .audioPlayed,
                origin: .sharePlay,
                module: .audio,
                outcome: .none,
                payloadByteCount: 1_024
            )
        ]
        let participants: [GameStatisticParticipantSnapshot] = [
            .fixture(id: deterministicUUID(20), sessionId: sessions[0].id, connectedDuration: 5_400),
            .fixture(id: deterministicUUID(21), sessionId: sessions[1].id, connectedDuration: 3_600)
        ]
        let dataSet = GameStatisticsDataSet(sessions: sessions, participants: participants, events: events)
        var configuration = GameStatisticsDashboardConfiguration.default
        configuration.granularity = .day

        // When
        let summary = GameStatisticsController().summary(
            from: dataSet,
            configuration: configuration,
            calendar: calendar
        )

        // Then
        #expect(summary.sessionCount == 2)
        #expect(summary.totalDuration == 10_800)
        #expect(summary.averageDuration == 5_400)
        #expect(summary.longestDuration == 7_200)
        #expect(summary.gameMasterDuration == 7_200)
        #expect(summary.playerDuration == 3_600)
        #expect(summary.diceRollCount == 3)
        #expect(summary.criticalCount == 2)
        #expect(summary.fumbleCount == 1)
        #expect(summary.payloadByteCount == 1_792)
        #expect(summary.activity.map(\.duration) == [1_800, 5_400, 3_600])
        #expect(summary.activity.map(\.sessionCount) == [1, 0, 1])
        #expect(summary.roles.count == 2)
        #expect(summary.characters.first?.title == "Aria")
        #expect(summary.characters.first?.value == 3_600)
        #expect(summary.adventures.first?.value == 10_800)
        #expect(summary.adventures.first?.count == 2)
        #expect(summary.modules.map(\.count).reduce(0, +) == 2)
        #expect(summary.party.first?.value == 9_000)
        #expect(summary.network.map(\.count).reduce(0, +) == 5)
        #expect(summary.recentSessions.first?.id == sessions[1].id)
    }

    @Test("achievement progress is cumulative and capped")
    func evaluatesAchievements() throws {
        // Given
        var sessions: [GameStatisticSessionSnapshot] = []
        for index in 0..<10 {
            let adventureIndex = min(index, 4)
            let session = GameStatisticSessionSnapshot.fixture(
                id: deterministicUUID(UInt8(index + 1)),
                startedAt: Date(timeIntervalSince1970: 1_704_067_200 + Double(index * 86_400)),
                duration: index == 0 ? 8 * 3_600 : 4 * 3_600,
                role: .gameMaster,
                characterId: deterministicUUID(30),
                characterName: "Aria",
                adventureId: deterministicUUID(UInt8(40 + adventureIndex)),
                adventureTitle: "Adventure \(adventureIndex + 1)",
                maxParticipantCount: index == 0 ? 6 : 4
            )
            sessions.append(session)
        }
        let sharedModules: [NetworkModules] = [.photo, .map, .audio, .pdf, .space]
        var events = sharedModules.enumerated().map { index, module in
            GameStatisticEventSnapshot.fixture(
                id: deterministicUUID(UInt8(60 + index)),
                kind: .contentShared,
                module: module,
                outcome: .none
            )
        }
        events.append(.fixture(id: deterministicUUID(70), outcome: .critical, quantity: 100))
        events.append(.fixture(id: deterministicUUID(71), outcome: .fumble))
        let summary = GameStatisticsController().summary(
            from: GameStatisticsDataSet(sessions: sessions, participants: [], events: events),
            configuration: .default
        )

        // When
        let progress = Dictionary(
            uniqueKeysWithValues: GameCenterAchievementEvaluator().progress(from: summary).map {
                ($0.identifier, $0.percentComplete)
            }
        )

        // Then
        #expect(progress[GameCenterAchievementEvaluator.Identifier.firstGame] == 100)
        #expect(progress[GameCenterAchievementEvaluator.Identifier.regularAdventurer] == 100)
        #expect(progress[GameCenterAchievementEvaluator.Identifier.veteranAdventurer] == 20)
        #expect(progress[GameCenterAchievementEvaluator.Identifier.storyteller] == 100)
        let loyalHero = try #require(progress[GameCenterAchievementEvaluator.Identifier.loyalHero])
        #expect(abs(loyalHero - 44) < 0.000_001)
        #expect(progress[GameCenterAchievementEvaluator.Identifier.campaigner] == 60)
        #expect(progress[GameCenterAchievementEvaluator.Identifier.wellTravelled] == 100)
        #expect(progress[GameCenterAchievementEvaluator.Identifier.diceInitiate] == 100)
        let diceLegend = try #require(progress[GameCenterAchievementEvaluator.Identifier.diceLegend])
        #expect(abs(diceLegend - 10.1) < 0.000_001)
        #expect(progress[GameCenterAchievementEvaluator.Identifier.criticalMoment] == 100)
        #expect(progress[GameCenterAchievementEvaluator.Identifier.unluckyHero] == 100)
        #expect(progress[GameCenterAchievementEvaluator.Identifier.multimediaMaestro] == 100)
        #expect(progress[GameCenterAchievementEvaluator.Identifier.fullParty] == 100)
        #expect(progress[GameCenterAchievementEvaluator.Identifier.epicSession] == 100)
        let diceOverlord = try #require(progress[GameCenterAchievementEvaluator.Identifier.diceOverlord])
        #expect(abs(diceOverlord - 1.01) < 0.000_001)
        #expect(progress[GameCenterAchievementEvaluator.Identifier.fortunesFavorite] == 100)
        let cursedDice = try #require(progress[GameCenterAchievementEvaluator.Identifier.cursedDice])
        #expect(abs(cursedDice - 1) < 0.000_001)
        #expect(progress[GameCenterAchievementEvaluator.Identifier.bothSides] == 50)
        let hundredHourClub = try #require(progress[GameCenterAchievementEvaluator.Identifier.hundredHourClub])
        #expect(abs(hundredHourClub - 44) < 0.000_001)
        #expect(progress[GameCenterAchievementEvaluator.Identifier.grandCampaign] == 24)
    }

    @Test("games shorter than 15 minutes and their related data are excluded")
    func excludesShortGames() {
        // Given
        let shortGame = GameStatisticSessionSnapshot.fixture(
            id: deterministicUUID(80),
            duration: GameStatisticsController.minimumCountedSessionDuration - 1
        )
        let boundaryGame = GameStatisticSessionSnapshot.fixture(
            id: deterministicUUID(81),
            duration: GameStatisticsController.minimumCountedSessionDuration
        )
        let normalGame = GameStatisticSessionSnapshot.fixture(
            id: deterministicUUID(82),
            duration: 4 * 3_600,
            role: .gameMaster
        )
        let events: [GameStatisticEventSnapshot] = [
            .fixture(
                id: deterministicUUID(83),
                sessionId: shortGame.id,
                quantity: 100,
                payloadByteCount: 1_000
            ),
            .fixture(
                id: deterministicUUID(84),
                sessionId: boundaryGame.id,
                quantity: 2,
                payloadByteCount: 200
            ),
            .fixture(
                id: deterministicUUID(85),
                sessionId: normalGame.id,
                kind: .contentShared,
                module: .photo,
                outcome: .none,
                quantity: 3,
                payloadByteCount: 300
            )
        ]
        let participants: [GameStatisticParticipantSnapshot] = [
            .fixture(
                id: deterministicUUID(86),
                sessionId: shortGame.id,
                connectedDuration: shortGame.duration
            ),
            .fixture(
                id: deterministicUUID(87),
                sessionId: boundaryGame.id,
                connectedDuration: boundaryGame.duration
            ),
            .fixture(
                id: deterministicUUID(88),
                sessionId: normalGame.id,
                connectedDuration: normalGame.duration
            )
        ]

        // When
        let summary = GameStatisticsController().summary(
            from: GameStatisticsDataSet(
                sessions: [shortGame, boundaryGame, normalGame],
                participants: participants,
                events: events
            ),
            configuration: .default
        )

        // Then
        #expect(summary.sessionCount == 2)
        #expect(summary.totalDuration == 15_300)
        #expect(summary.averageDuration == 7_650)
        #expect(summary.longestDuration == 14_400)
        #expect(summary.diceRollCount == 2)
        #expect(summary.payloadByteCount == 500)
        #expect(summary.modules.map(\.count).reduce(0, +) == 3)
        #expect(summary.party.first?.value == 15_300)
        #expect(summary.network.map(\.count).reduce(0, +) == 5)
        #expect(summary.recentSessions.count == 2)
        #expect(!summary.recentSessions.contains(shortGame))
    }

    @Test(
        "epic-session progress reflects realistic game lengths",
        arguments: zip(
            [4.0, 6.0, 8.0, 12.0],
            [50.0, 75.0, 100.0, 100.0]
        )
    )
    func evaluatesEpicSessionProgress(durationInHours: Double, expectedProgress: Double) throws {
        // Given
        let session = GameStatisticSessionSnapshot.fixture(
            duration: durationInHours * 3_600
        )
        let summary = GameStatisticsController().summary(
            from: GameStatisticsDataSet(sessions: [session], participants: [], events: []),
            configuration: .default
        )

        // When
        let epicSession = try #require(
            GameCenterAchievementEvaluator()
                .progress(from: summary)
                .first { $0.identifier == GameCenterAchievementEvaluator.Identifier.epicSession }
        )

        // Then
        #expect(abs(epicSession.percentComplete - expectedProgress) < 0.000_001)
    }

    @Test("Map sharing counts reveals but excludes state and pin updates")
    func mapSharingCountsOnlyReveals() {
        let sender = GameSenderModel(
            id: UUID(),
            role: .master,
            name: "Master",
            characterId: nil
        )
        let masterId = sender.id
        let mapId = UUID()
        let controller = GameStatisticsController()

        func event(type: RPGMessageType, action: RPGMessageActionType) -> GameStatisticEventDraft {
            let message = GameNetworkModel(
                counter: 1,
                proxyCounter: 0,
                type: type,
                subType: action,
                masterId: masterId,
                sender: sender,
                data: NetworkCodableDataType(
                    id: mapId,
                    type: .map,
                    version: 1,
                    data: Data([1])
                )
            )
            return controller.eventDraft(
                for: message,
                sessionId: UUID(),
                localParticipantId: masterId,
                direction: .outgoing,
                origin: .local
            )
        }

        #expect(event(type: .reveal, action: .show).kind == .contentShared)
        #expect(event(type: .update, action: .mapState).kind == .message)
        #expect(event(type: .update, action: .mapPin).kind == .message)
    }

    @Test("preview data demonstrates the dashboard without persistence")
    func createsDashboardPreview() throws {
        // Given
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let referenceDate = Date(timeIntervalSince1970: 1_735_689_600)

        // When
        let summary = GameStatisticsPreviewController().summary(
            referenceDate: referenceDate,
            calendar: calendar
        )

        // Then
        #expect(summary.sessionCount == 12)
        #expect(summary.activity.count == 8)
        #expect(summary.activity.map(\.sessionCount).reduce(0, +) == summary.sessionCount)
        #expect(summary.activity.map(\.duration).reduce(0, +) == summary.totalDuration)
        #expect(summary.diceOutcomes.map(\.count).reduce(0, +) == summary.diceRollCount)
        #expect(summary.modules.count >= 4)
        #expect(summary.recentSessions.count == 3)
        #expect(summary.activity.map(\.date) == summary.activity.map(\.date).sorted())
    }

    @Test("native move offsets reorder dashboard sections")
    @MainActor
    func reordersDashboardSections() throws {
        // Given
        let suiteName = "GameStatisticsControllerTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let model = GameStatisticsModel(defaults: defaults)

        // When
        model.moveSections(fromOffsets: IndexSet(integer: 0), toOffset: 6)

        // Then
        #expect(model.configuration.sectionOrder == [
            .schedule,
            .roles,
            .characters,
            .adventures,
            .dice,
            .activity,
            .sharedContent,
            .party,
            .network
        ])

        // When
        model.moveSections(fromOffsets: IndexSet(integer: 8), toOffset: 1)

        // Then
        #expect(model.configuration.sectionOrder == [
            .schedule,
            .network,
            .roles,
            .characters,
            .adventures,
            .dice,
            .activity,
            .sharedContent,
            .party
        ])
    }

    private func deterministicUUID(_ finalByte: UInt8) -> UUID {
        UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, finalByte))
    }
}
#endif
