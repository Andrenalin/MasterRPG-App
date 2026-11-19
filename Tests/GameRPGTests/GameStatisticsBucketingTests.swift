// @copyright André Trettin

#if canImport(Testing)
import CoreRPG
import Foundation
import Testing

@testable import GameRPG

/// CODE_AUDIT_TestGaps §5.11: the chart-point builders of `GameStatisticsController` (time
/// splits, heat map, category, dice, module, party and network points) with empty, one-event and
/// boundary input. The builders are private; they are reached through `summary`.
@Suite("Game statistics bucketing")
struct GameStatisticsBucketingTests {
    private func calendar(_ zone: String = "UTC", firstWeekday: Int = 2) throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: zone))
        calendar.firstWeekday = firstWeekday
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }

    private func date(_ iso: String) throws -> Date {
        try Date(iso, strategy: .iso8601)
    }

    private func id(_ byte: UInt8) -> UUID {
        UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, byte))
    }

    private func summary(
        sessions: [GameStatisticSessionSnapshot] = [],
        participants: [GameStatisticParticipantSnapshot] = [],
        events: [GameStatisticEventSnapshot] = [],
        granularity: GameStatisticsGranularity = .day,
        calendar: Calendar
    ) -> GameStatisticsSummary {
        var configuration = GameStatisticsDashboardConfiguration.default
        configuration.granularity = granularity
        return GameStatisticsController().summary(
            from: GameStatisticsDataSet(sessions: sessions, participants: participants, events: events),
            configuration: configuration,
            calendar: calendar
        )
    }

    // MARK: - Empty and single input

    @Test("No data gives zero totals and no points")
    func emptyDataSet() throws {
        let result = summary(calendar: try calendar())

        #expect(result.sessionCount == 0)
        #expect(result.totalDuration == 0)
        #expect(result.averageDuration == 0, "no division by zero")
        #expect(result.longestDuration == 0)
        #expect(result.largestPartySize == 0)
        #expect(result.diceRollCount == 0)
        #expect(result.activity.isEmpty)
        #expect(result.schedule.isEmpty)
        #expect(result.roles.isEmpty)
        #expect(result.characters.isEmpty)
        #expect(result.adventures.isEmpty)
        #expect(result.diceOutcomes.isEmpty)
        #expect(result.modules.isEmpty)
        #expect(result.party.isEmpty)
        #expect(result.network.isEmpty)
        #expect(result.recentSessions.isEmpty)
    }

    @Test("One session inside one hour is one activity point and one heat map cell")
    func oneSession() throws {
        let calendar = try calendar()
        let start = try date("2024-01-02T20:00:00Z") // Tuesday
        let session = GameStatisticSessionSnapshot.fixture(id: id(1), startedAt: start, duration: 1_800)

        let result = summary(sessions: [session], calendar: calendar)

        #expect(result.activity.count == 1)
        #expect(result.activity.first?.date == (try date("2024-01-02T00:00:00Z")))
        #expect(result.activity.first?.duration == 1_800)
        #expect(result.activity.first?.sessionCount == 1)
        #expect(result.schedule.count == 1)
        #expect(result.schedule.first?.weekday == 3, "Tuesday")
        #expect(result.schedule.first?.hour == 20)
        #expect(result.schedule.first?.duration == 1_800)
    }

    // MARK: - Counted sessions

    @Test("A game counts from exactly 15 minutes, not below, and never as an observer or proxy")
    func countedSessionBoundary() throws {
        let calendar = try calendar()
        let start = try date("2024-01-02T20:00:00Z")
        let just = GameStatisticSessionSnapshot.fixture(id: id(1), startedAt: start, duration: 900)
        let short = GameStatisticSessionSnapshot.fixture(id: id(2), startedAt: start, duration: 899)
        let observer = GameStatisticSessionSnapshot.fixture(id: id(3), startedAt: start, duration: 3_600, role: .observer)
        let proxy = GameStatisticSessionSnapshot.fixture(id: id(4), startedAt: start, duration: 3_600, role: .proxy)

        let result = summary(sessions: [just, short, observer, proxy], calendar: calendar)

        #expect(result.sessionCount == 1)
        #expect(result.totalDuration == 900)
        #expect(result.recentSessions.map(\.id) == [just.id])
    }

    @Test("The recent sessions are the ten newest, newest first")
    func recentSessionsAreCapped() throws {
        let calendar = try calendar()
        let start = try date("2024-01-01T10:00:00Z")
        let sessions = (0..<12).map { index in
            GameStatisticSessionSnapshot.fixture(id: id(UInt8(index + 1)), startedAt: start.addingTimeInterval(Double(index) * 86_400), duration: 1_800)
        }

        let result = summary(sessions: sessions, calendar: calendar)

        #expect(result.sessionCount == 12)
        #expect(result.recentSessions.count == 10)
        #expect(result.recentSessions.first?.id == id(12))
        #expect(result.recentSessions.last?.id == id(3))
    }

    // MARK: - Time splits

    @Test("A game over midnight is split between the two days")
    func splitAtMidnight() throws {
        let calendar = try calendar()
        let start = try date("2024-01-01T23:30:00Z")
        let session = GameStatisticSessionSnapshot.fixture(id: id(1), startedAt: start, duration: 3_600)

        let result = summary(sessions: [session], granularity: .day, calendar: calendar)

        #expect(result.activity.map(\.duration) == [1_800, 1_800])
        #expect(result.activity.map(\.sessionCount) == [1, 0], "the game counts for the day it started")
    }

    @Test("A game that ends exactly at midnight adds no empty bucket for the next day")
    func endsAtMidnight() throws {
        let calendar = try calendar()
        let start = try date("2024-01-01T23:00:00Z")
        let session = GameStatisticSessionSnapshot.fixture(id: id(1), startedAt: start, duration: 3_600)

        let result = summary(sessions: [session], granularity: .day, calendar: calendar)

        #expect(result.activity.count == 1)
        #expect(result.activity.first?.duration == 3_600)
    }

    @Test("A game over a month end is split by month")
    func splitAtMonthEnd() throws {
        let calendar = try calendar()
        let start = try date("2024-01-31T23:00:00Z")
        let session = GameStatisticSessionSnapshot.fixture(id: id(1), startedAt: start, duration: 7_200)

        let result = summary(sessions: [session], granularity: .month, calendar: calendar)

        #expect(result.activity.map(\.duration) == [3_600, 3_600])
        #expect(result.activity.first?.date == (try date("2024-01-01T00:00:00Z")))
        #expect(result.activity.last?.date == (try date("2024-02-01T00:00:00Z")))
    }

    @Test("A game over the turn of a week is split at the week start of the calendar")
    func splitAtWeekStart() throws {
        let monday = try calendar(firstWeekday: 2)
        let sunday = try calendar(firstWeekday: 1)
        let start = try date("2024-01-07T23:30:00Z") // Sunday evening
        let session = GameStatisticSessionSnapshot.fixture(id: id(1), startedAt: start, duration: 3_600)

        let mondayWeeks = summary(sessions: [session], granularity: .week, calendar: monday)
        let sundayWeeks = summary(sessions: [session], granularity: .week, calendar: sunday)

        #expect(mondayWeeks.activity.map(\.duration) == [1_800, 1_800], "weeks start on Monday: Sunday 23:30 ends a week")
        #expect(sundayWeeks.activity.map(\.duration) == [3_600], "weeks start on Sunday: the whole game is in one")
    }

    @Test("Two games on one day add up in that day's bucket")
    func gamesOnOneDayAddUp() throws {
        let calendar = try calendar()
        let first = GameStatisticSessionSnapshot.fixture(id: id(1), startedAt: try date("2024-01-02T10:00:00Z"), duration: 3_600)
        let second = GameStatisticSessionSnapshot.fixture(id: id(2), startedAt: try date("2024-01-02T20:00:00Z"), duration: 1_800)

        let result = summary(sessions: [first, second], granularity: .day, calendar: calendar)

        #expect(result.activity.count == 1)
        #expect(result.activity.first?.duration == 5_400)
        #expect(result.activity.first?.sessionCount == 2)
    }

    @Test("A game that ends before it starts adds no time")
    func negativeIntervalAddsNothing() throws {
        let calendar = try calendar()
        let start = try date("2024-01-02T20:00:00Z")
        // Counted by its stored duration, but its end lies before its start.
        let broken = GameStatisticSessionSnapshot(
            id: id(1), startedAt: start, endedAt: start.addingTimeInterval(-600), duration: 1_800, role: .player,
            localName: "P", characterId: nil, characterName: "", adventureId: nil, adventureTitle: "",
            masterName: "", maxParticipantCount: 2
        )

        let result = summary(sessions: [broken], calendar: calendar)

        #expect(result.activity.allSatisfy { $0.duration == 0 })
        #expect(result.schedule.isEmpty)
    }

    // MARK: - Heat map

    @Test("The heat map splits at each hour and sorts by weekday, then hour")
    func heatMapSplitsByHour() throws {
        let calendar = try calendar()
        let start = try date("2024-01-02T22:30:00Z") // Tuesday
        let session = GameStatisticSessionSnapshot.fixture(id: id(1), startedAt: start, duration: 7_200)

        let result = summary(sessions: [session], calendar: calendar)

        #expect(result.schedule.map(\.weekday) == [3, 3, 4])
        #expect(result.schedule.map(\.hour) == [22, 23, 0])
        #expect(result.schedule.map(\.duration) == [1_800, 3_600, 1_800])
    }

    @Test("Games in the same weekday and hour on different weeks share a cell")
    func heatMapSharesCells() throws {
        let calendar = try calendar()
        let first = GameStatisticSessionSnapshot.fixture(id: id(1), startedAt: try date("2024-01-02T20:00:00Z"), duration: 1_800)
        let second = GameStatisticSessionSnapshot.fixture(id: id(2), startedAt: try date("2024-01-09T20:15:00Z"), duration: 1_800)

        let result = summary(sessions: [first, second], calendar: calendar)

        let cell = result.schedule.first { $0.weekday == 3 && $0.hour == 20 }
        #expect(cell?.duration == 3_600)
    }

    @Test("The heat map follows the time zone of the calendar")
    func heatMapUsesTheLocalZone() throws {
        let berlin = try calendar("Europe/Berlin")
        let start = try date("2024-01-02T23:30:00Z") // 00:30 Wednesday in Berlin
        let session = GameStatisticSessionSnapshot.fixture(id: id(1), startedAt: start, duration: 1_800)

        let result = summary(sessions: [session], calendar: berlin)

        #expect(result.schedule.first?.weekday == 4)
        #expect(result.schedule.first?.hour == 0)
        #expect(result.activity.first?.date == (try date("2024-01-02T23:00:00Z")), "the day starts at Berlin midnight")
    }

    // MARK: - Categories

    @Test("Roles, characters and adventures add up per key and sort by time")
    func categoryPoints() throws {
        let calendar = try calendar()
        let start = try date("2024-01-02T20:00:00Z")
        let aria = id(50)
        let sessions: [GameStatisticSessionSnapshot] = [
            .fixture(id: id(1), startedAt: start, duration: 1_800, role: .player, characterId: aria, characterName: "Aria", adventureId: nil, adventureTitle: "Cellar"),
            .fixture(id: id(2), startedAt: start, duration: 3_600, role: .player, characterId: aria, characterName: "Aria", adventureId: nil, adventureTitle: "Cellar"),
            .fixture(id: id(3), startedAt: start, duration: 5_400, role: .gameMaster, characterId: nil, characterName: "", adventureId: nil, adventureTitle: "Tower")
        ]

        let result = summary(sessions: sessions, calendar: calendar)

        #expect(result.roles.count == 2)
        #expect(result.roles.map(\.value) == [5_400, 5_400], "players 1 800 + 3 600, game master 5 400")
        #expect(result.roles.map(\.count).sorted() == [1, 2])
        #expect(result.characters.count == 1, "the game master session has no character")
        #expect(result.characters.first?.title == "Aria")
        #expect(result.characters.first?.count == 2)
        #expect(result.characters.first?.value == 5_400)
        #expect(Set(result.adventures.map(\.title)) == ["Cellar", "Tower"])
        #expect(result.adventures.map(\.value) == [5_400, 5_400])
    }

    @Test("An unnamed character or adventure is grouped under its id, or a placeholder title")
    func unnamedCategories() throws {
        let calendar = try calendar()
        let start = try date("2024-01-02T20:00:00Z")
        let session = GameStatisticSessionSnapshot.fixture(
            id: id(1), startedAt: start, duration: 1_800, characterId: id(60), characterName: "", adventureId: id(61), adventureTitle: ""
        )

        let result = summary(sessions: [session], calendar: calendar)

        #expect(result.characters.first?.key == id(60).uuidString)
        #expect(result.characters.first?.title.isEmpty == false)
        #expect(result.adventures.first?.key == id(61).uuidString)
        #expect(result.adventures.first?.title.isEmpty == false)
    }

    // MARK: - Dice

    @Test("Dice outcomes leave out rolls without a result and sort by count")
    func diceOutcomePoints() throws {
        let calendar = try calendar()
        let start = try date("2024-01-02T20:00:00Z")
        let session = GameStatisticSessionSnapshot.fixture(id: id(1), startedAt: start, duration: 1_800)
        let events: [GameStatisticEventSnapshot] = [
            .fixture(id: id(10), sessionId: session.id, outcome: .fumble),
            .fixture(id: id(11), sessionId: session.id, outcome: .critical, quantity: 3),
            .fixture(id: id(12), sessionId: session.id, outcome: .none),
            .fixture(id: id(13), sessionId: session.id, outcome: .notRolled)
        ]

        let result = summary(sessions: [session], events: events, calendar: calendar)

        #expect(result.diceOutcomes.count == 2)
        #expect(result.diceOutcomes.map(\.count) == [3, 1])
        #expect(result.diceRollCount == 6, "every roll counts, also the ones without an outcome")
        #expect(result.criticalCount == 3)
        #expect(result.fumbleCount == 1)
    }

    @Test("Only the local participant's rolls count when the game recorded one")
    func onlyOwnRollsCount() throws {
        let calendar = try calendar()
        let start = try date("2024-01-02T20:00:00Z")
        let session = GameStatisticSessionSnapshot.fixture(id: id(1), startedAt: start, duration: 1_800)
        let me = id(70)
        let other = id(71)
        let participants: [GameStatisticParticipantSnapshot] = [
            .fixture(id: id(80), sessionId: session.id, participantId: me, isLocal: true),
            .fixture(id: id(81), sessionId: session.id, participantId: other, isLocal: false)
        ]
        let events: [GameStatisticEventSnapshot] = [
            .fixture(id: id(10), sessionId: session.id, direction: .outgoing, actorId: me),
            .fixture(id: id(11), sessionId: session.id, direction: .incoming, actorId: other),
            .fixture(id: id(12), sessionId: session.id, direction: .outgoing, actorId: nil)
        ]

        let result = summary(sessions: [session], participants: participants, events: events, calendar: calendar)

        #expect(result.diceRollCount == 1)
    }

    @Test("Without a recorded local participant incoming rolls are not counted")
    func withoutLocalParticipantIncomingRollsAreNot() throws {
        let calendar = try calendar()
        let start = try date("2024-01-02T20:00:00Z")
        let session = GameStatisticSessionSnapshot.fixture(id: id(1), startedAt: start, duration: 1_800)
        let events: [GameStatisticEventSnapshot] = [
            .fixture(id: id(10), sessionId: session.id, direction: .outgoing),
            .fixture(id: id(11), sessionId: session.id, direction: .local),
            .fixture(id: id(12), sessionId: session.id, direction: .incoming)
        ]

        let result = summary(sessions: [session], events: events, calendar: calendar)

        #expect(result.diceRollCount == 2)
    }

    // MARK: - Modules, party and network

    @Test("Shared content and played audio count per module, other events do not")
    func modulePoints() throws {
        let calendar = try calendar()
        let start = try date("2024-01-02T20:00:00Z")
        let session = GameStatisticSessionSnapshot.fixture(id: id(1), startedAt: start, duration: 1_800)
        let events: [GameStatisticEventSnapshot] = [
            .fixture(id: id(10), sessionId: session.id, kind: .contentShared, module: .map, outcome: .none),
            .fixture(id: id(11), sessionId: session.id, kind: .contentShared, module: .map, outcome: .none, quantity: 2),
            .fixture(id: id(12), sessionId: session.id, kind: .audioPlayed, module: .audio, outcome: .none),
            .fixture(id: id(13), sessionId: session.id, kind: .message, module: .photo, outcome: .none),
            .fixture(id: id(14), sessionId: session.id, kind: .deliveryAcknowledged, module: .pdf, outcome: .none)
        ]

        let result = summary(sessions: [session], events: events, calendar: calendar)

        #expect(result.modules.map(\.count) == [3, 1])
        #expect(result.modules.first?.key == String(NetworkModules.map.rawValue))
    }

    @Test("The party leaves out the local participant and groups by Character")
    func partyPoints() throws {
        let calendar = try calendar()
        let start = try date("2024-01-02T20:00:00Z")
        let first = GameStatisticSessionSnapshot.fixture(id: id(1), startedAt: start, duration: 1_800)
        let second = GameStatisticSessionSnapshot.fixture(id: id(2), startedAt: start, duration: 1_800)
        let hero = id(90)
        let participants: [GameStatisticParticipantSnapshot] = [
            .fixture(id: id(20), sessionId: first.id, participantId: id(91), characterId: hero, name: "Anna", characterName: "Hero", connectedDuration: 1_000),
            .fixture(id: id(21), sessionId: second.id, participantId: id(92), characterId: hero, name: "Anna", characterName: "Hero", connectedDuration: 500),
            .fixture(id: id(22), sessionId: first.id, participantId: id(93), characterId: nil, name: "Ben", characterName: "", connectedDuration: 200),
            .fixture(id: id(23), sessionId: first.id, participantId: id(94), name: "Me", connectedDuration: 9_999, isLocal: true)
        ]

        let result = summary(sessions: [first, second], participants: participants, calendar: calendar)

        #expect(result.party.count == 2)
        #expect(result.party.first?.title == "Hero")
        #expect(result.party.first?.value == 1_500)
        #expect(result.party.first?.count == 2)
        #expect(result.party.last?.title == "Ben", "without a Character the player's name is the title")
        #expect(result.party.last?.key == id(93).uuidString)
    }

    @Test("The network points group by origin with the event count and the bytes")
    func networkPoints() throws {
        let calendar = try calendar()
        let start = try date("2024-01-02T20:00:00Z")
        let session = GameStatisticSessionSnapshot.fixture(id: id(1), startedAt: start, duration: 1_800)
        let events: [GameStatisticEventSnapshot] = [
            .fixture(id: id(10), sessionId: session.id, origin: .localNetwork, payloadByteCount: 100),
            .fixture(id: id(11), sessionId: session.id, origin: .localNetwork, payloadByteCount: 50),
            .fixture(id: id(12), sessionId: session.id, origin: .sharePlay, payloadByteCount: 1_000)
        ]

        let result = summary(sessions: [session], events: events, calendar: calendar)

        #expect(result.network.map(\.count) == [2, 1])
        #expect(result.network.first?.value == 150)
        #expect(result.network.last?.value == 1_000)
        #expect(result.payloadByteCount == 1_150)
    }

    @Test("Events and participants of a game that does not count are left out")
    func uncountedSessionsLeaveNoTrace() throws {
        let calendar = try calendar()
        let start = try date("2024-01-02T20:00:00Z")
        let short = GameStatisticSessionSnapshot.fixture(id: id(1), startedAt: start, duration: 60)
        let events: [GameStatisticEventSnapshot] = [.fixture(id: id(10), sessionId: short.id, kind: .contentShared, module: .map, outcome: .none)]
        let participants: [GameStatisticParticipantSnapshot] = [.fixture(id: id(20), sessionId: short.id)]

        let result = summary(sessions: [short], participants: participants, events: events, calendar: calendar)

        #expect(result.modules.isEmpty)
        #expect(result.network.isEmpty)
        #expect(result.party.isEmpty)
        #expect(result.payloadByteCount == 0)
    }
}
#endif
