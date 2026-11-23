// @copyright André Trettin

#if canImport(Testing)
import Foundation
import Testing

@testable import GameRPG

/// CODE_AUDIT_26 §10.13: the statistics fixes of the audit's GameRPG Views/Battle/Statistics area.
@Suite("Game statistics risks")
struct GameStatisticsRiskTests {
    // MARK: - Dashboard configuration (5.86)

    private func decode(_ json: String) throws -> GameStatisticsDashboardConfiguration {
        try JSONDecoder().decode(GameStatisticsDashboardConfiguration.self, from: Data(json.utf8))
    }

    // CODE_AUDIT_28 §7.4
    @Test("Only the date range, granularity and direction change the data key")
    func dataKeyIgnoresPresentationFields() {
        var configuration = GameStatisticsDashboardConfiguration.default
        let key = configuration.dataKey

        configuration.sectionOrder.reverse()
        configuration.hiddenSections = [.dice]
        configuration.metric = .sessions
        #expect(configuration.dataKey == key)

        configuration.granularity = .month
        #expect(configuration.dataKey != key)
    }

    @Test("A saved dashboard from an older version keeps its values and defaults the rest")
    func olderConfigurationKeepsDefaults() throws {
        let configuration = try decode(#"{"granularity":2}"#)

        #expect(configuration.granularity == .month)
        #expect(configuration.dateRange == GameStatisticsDashboardConfiguration.default.dateRange)
        #expect(configuration.sectionOrder == GameStatisticsSection.allCases)
    }

    @Test("Unknown cases are dropped and unknown sections appended instead of resetting everything")
    func newerConfigurationIsTolerated() throws {
        let configuration = try decode(#"{"metric":1,"dateRange":99,"sectionOrder":[3,999,3,0],"hiddenSections":[1,888]}"#)

        #expect(configuration.metric == .sessions)
        #expect(configuration.dateRange == GameStatisticsDashboardConfiguration.default.dateRange)
        #expect(Array(configuration.sectionOrder.prefix(2)) == [.characters, .activity])
        #expect(Set(configuration.sectionOrder) == Set(GameStatisticsSection.allCases))
        #expect(configuration.sectionOrder.count == GameStatisticsSection.allCases.count)
        #expect(configuration.hiddenSections == [.schedule])
    }

    @Test("An empty object decodes to the default configuration")
    func emptyObjectIsDefault() throws {
        #expect(try decode("{}") == .default)
    }

    @Test("A configuration survives an encode and decode")
    func configurationRoundTrips() throws {
        var configuration = GameStatisticsDashboardConfiguration.default
        configuration.granularity = .day
        configuration.hiddenSections = [.network]
        configuration.sectionOrder = GameStatisticsSection.allCases.reversed()

        let data = try JSONEncoder().encode(configuration)

        #expect(try JSONDecoder().decode(GameStatisticsDashboardConfiguration.self, from: data) == configuration)
    }

    // MARK: - Activity bucket selection (5.89)

    @Test("Every day of a week bucket selects that bucket")
    func selectionResolvesToItsBucket() {
        let monday = Date(timeIntervalSince1970: 1_704_067_200)
        let nextMonday = monday.addingTimeInterval(7 * 86_400)
        let buckets = [monday, nextMonday]

        for day in 0..<7 {
            let selected = monday.addingTimeInterval(Double(day) * 86_400 + 3_600)
            #expect(GameStatisticTimePoint.bucketDate(containing: selected, in: buckets) == monday)
        }
        #expect(GameStatisticTimePoint.bucketDate(containing: nextMonday.addingTimeInterval(86_400), in: buckets) == nextMonday)
    }

    @Test("A date before every bucket selects the first one and no buckets select none")
    func selectionOutsideBuckets() {
        let first = Date(timeIntervalSince1970: 1_704_067_200)

        #expect(GameStatisticTimePoint.bucketDate(containing: first.addingTimeInterval(-86_400), in: [first]) == first)
        #expect(GameStatisticTimePoint.bucketDate(containing: first, in: []) == nil)
    }

    // MARK: - Own rolls only (5.88)

    private func summary(participants: [GameStatisticParticipantSnapshot], events: [GameStatisticEventSnapshot]) -> GameStatisticsSummary {
        let session = GameStatisticSessionSnapshot.fixture()
        return GameStatisticsController().summary(
            from: GameStatisticsDataSet(sessions: [session], participants: participants, events: events),
            configuration: .default
        )
    }

    @Test("With a local participant, only that participant's rolls count")
    func onlyTheLocalParticipantsRollsCount() {
        let me = UUID(), other = UUID()
        let participants: [GameStatisticParticipantSnapshot] = [
            .fixture(id: UUID(), participantId: me, isLocal: true),
            .fixture(id: UUID(), participantId: other, isLocal: false)
        ]
        let events: [GameStatisticEventSnapshot] = [
            .fixture(id: UUID(), actorId: me, quantity: 2),
            .fixture(id: UUID(), direction: .incoming, actorId: other, quantity: 5),
            .fixture(id: UUID(), actorId: nil, quantity: 7)
        ]

        #expect(summary(participants: participants, events: events).diceRollCount == 2)
    }

    @Test("Without a recorded local participant, received rolls are not counted")
    func receivedRollsAreSkippedWithoutLocalParticipant() {
        let events: [GameStatisticEventSnapshot] = [
            .fixture(id: UUID(), direction: .outgoing, quantity: 3),
            .fixture(id: UUID(), direction: .incoming, quantity: 4)
        ]

        #expect(summary(participants: [], events: events).diceRollCount == 3)
    }
}
#endif
