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
        let adventureID = deterministicUUID(40)
        let characterID = deterministicUUID(30)
        let sessions: [GameStatisticSessionSnapshot] = [
            .fixture(
                id: deterministicUUID(1),
                startedAt: firstStart,
                duration: 7_200,
                role: .gameMaster,
                characterID: nil,
                characterName: "",
                adventureID: adventureID,
                adventureTitle: "The Long Night"
            ),
            .fixture(
                id: deterministicUUID(2),
                startedAt: secondStart,
                duration: 3_600,
                role: .player,
                characterID: characterID,
                characterName: "Aria",
                adventureID: adventureID,
                adventureTitle: "The Long Night",
                maxParticipantCount: 5
            )
        ]
        let events: [GameStatisticEventSnapshot] = [
            .fixture(id: deterministicUUID(10), sessionID: sessions[0].id, outcome: .critical, quantity: 2),
            .fixture(id: deterministicUUID(11), sessionID: sessions[1].id, outcome: .fumble),
            .fixture(
                id: deterministicUUID(12),
                sessionID: sessions[0].id,
                kind: .contentShared,
                module: .photo,
                outcome: .none,
                payloadByteCount: 512
            ),
            .fixture(
                id: deterministicUUID(13),
                sessionID: sessions[0].id,
                kind: .audioPlayed,
                origin: .sharePlay,
                module: .audio,
                outcome: .none,
                payloadByteCount: 1_024
            )
        ]
        let participants: [GameStatisticParticipantSnapshot] = [
            .fixture(id: deterministicUUID(20), sessionID: sessions[0].id, connectedDuration: 5_400),
            .fixture(id: deterministicUUID(21), sessionID: sessions[1].id, connectedDuration: 3_600)
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
                duration: index == 0 ? 18_000 : 3_600,
                role: .gameMaster,
                characterID: deterministicUUID(30),
                characterName: "Aria",
                adventureID: deterministicUUID(UInt8(40 + adventureIndex)),
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
        #expect(progress[GameCenterAchievementEvaluator.Identifier.storyteller] == 100)
        let loyalHero = try #require(progress[GameCenterAchievementEvaluator.Identifier.loyalHero])
        #expect(abs(loyalHero - 56) < 0.000_001)
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

    private func deterministicUUID(_ finalByte: UInt8) -> UUID {
        UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, finalByte))
    }
}
#endif
