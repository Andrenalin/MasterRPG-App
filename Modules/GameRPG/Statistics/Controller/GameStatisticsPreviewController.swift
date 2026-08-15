// @copyright André Trettin

import CoreRPG
import Foundation

struct GameStatisticsPreviewController: Sendable {
    /// Cached fixture summary for the dashboard's empty-state placeholder.
    ///
    /// `GamePreviewData.referenceDate`/`.calendar` are fixed constants, so this fixture is
    /// deterministic — compute it once instead of rebuilding it (several array literals plus
    /// multiple `Calendar.date(byAdding:)` calls) on every SwiftUI re-render of the dashboard's
    /// root view, which is recreated on every parent redraw.
    static let dashboardPreviewSummary = GameStatisticsPreviewController().summary(
        referenceDate: GamePreviewData.referenceDate,
        calendar: GamePreviewData.calendar
    )

    func summary(
        referenceDate: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) -> GameStatisticsSummary {
        let activityDurations: [TimeInterval] = [
            11_700, 16_200, 9_900, 25_200, 12_600, 29_700, 18_900, 28_800
        ]
        let activitySessionCounts = [1, 1, 1, 2, 1, 2, 2, 2]
        let activity = activityDurations.enumerated().map { index, duration in
            GameStatisticTimePoint(
                date: date(daysBefore: (activityDurations.count - index - 1) * 21, referenceDate: referenceDate, calendar: calendar),
                duration: duration,
                sessionCount: activitySessionCounts[index]
            )
        }

        return GameStatisticsSummary(
            sessionCount: 12,
            totalDuration: 153_000,
            averageDuration: 12_750,
            longestDuration: 18_000,
            gameMasterDuration: 54_000,
            playerDuration: 99_000,
            diceRollCount: 537,
            criticalCount: 34,
            fumbleCount: 15,
            payloadByteCount: 98_566_144,
            activity: activity,
            schedule: schedule,
            roles: roles,
            characters: characters,
            adventures: adventures,
            diceOutcomes: diceOutcomes,
            modules: modules,
            party: party,
            network: network,
            recentSessions: recentSessions(referenceDate: referenceDate, calendar: calendar)
        )
    }

    private var schedule: [GameStatisticHeatMapPoint] {
        [
            .init(weekday: 1, hour: 14, duration: 7_200),
            .init(weekday: 1, hour: 15, duration: 10_800),
            .init(weekday: 3, hour: 19, duration: 12_600),
            .init(weekday: 3, hour: 20, duration: 14_400),
            .init(weekday: 6, hour: 19, duration: 18_000),
            .init(weekday: 6, hour: 20, duration: 21_600),
            .init(weekday: 7, hour: 14, duration: 16_200),
            .init(weekday: 7, hour: 15, duration: 19_800)
        ]
    }

    private var roles: [GameStatisticCategoryPoint] {
        [
            .init(key: "player", title: GameStatisticRole.player.title, value: 99_000, count: 8),
            .init(key: "gameMaster", title: GameStatisticRole.gameMaster.title, value: 54_000, count: 4)
        ]
    }

    private var characters: [GameStatisticCategoryPoint] {
        [
            .init(key: "aria", title: "Aria", value: 45_000, count: 4),
            .init(key: "borin", title: "Borin", value: 32_400, count: 2),
            .init(key: "mira", title: "Mira", value: 21_600, count: 2)
        ]
    }

    private var adventures: [GameStatisticCategoryPoint] {
        [
            .init(
                key: "shatteredCrown",
                title: String(localized: "The Shattered Crown", bundle: .module),
                value: 68_400,
                count: 5
            ),
            .init(
                key: "moonfallSecrets",
                title: String(localized: "Moonfall Secrets", bundle: .module),
                value: 52_200,
                count: 4
            ),
            .init(
                key: "emberkeep",
                title: String(localized: "Emberkeep", bundle: .module),
                value: 32_400,
                count: 3
            )
        ]
    }

    private var diceOutcomes: [GameStatisticCategoryPoint] {
        [
            .init(key: "rolled", title: GameStatisticDiceOutcome.rolled.title, value: 488, count: 488),
            .init(key: "critical", title: GameStatisticDiceOutcome.critical.title, value: 34, count: 34),
            .init(key: "fumble", title: GameStatisticDiceOutcome.fumble.title, value: 15, count: 15)
        ]
    }

    private var modules: [GameStatisticCategoryPoint] {
        [
            .init(key: "photo", title: NetworkModules.photo.title, value: 42, count: 42),
            .init(key: "audio", title: NetworkModules.audio.title, value: 31, count: 31),
            .init(key: "map", title: NetworkModules.map.title, value: 18, count: 18),
            .init(key: "pdf", title: NetworkModules.pdf.title, value: 11, count: 11),
            .init(key: "table", title: NetworkModules.table.title, value: 9, count: 9)
        ]
    }

    private var party: [GameStatisticCategoryPoint] {
        [
            .init(key: "borin", title: "Borin", value: 72_000, count: 6),
            .init(key: "mira", title: "Mira", value: 57_600, count: 5),
            .init(key: "nyx", title: "Nyx", value: 43_200, count: 4)
        ]
    }

    private var network: [GameStatisticCategoryPoint] {
        [
            .init(
                key: "localNetwork",
                title: String(localized: "Local Network", bundle: .module),
                value: 61_865_984,
                count: 782
            ),
            .init(key: "sharePlay", title: "SharePlay", value: 31_457_280, count: 356),
            .init(
                key: "proxy",
                title: String(localized: "Proxy", bundle: .module),
                value: 5_242_880,
                count: 52
            )
        ]
    }

    private func recentSessions(referenceDate: Date, calendar: Calendar) -> [GameStatisticSessionSnapshot] {
        [
            session(
                id: identifier(1),
                daysBefore: 2,
                duration: 15_300,
                role: .player,
                characterName: "Aria",
                adventureTitle: String(localized: "The Shattered Crown", bundle: .module),
                participantCount: 5,
                referenceDate: referenceDate,
                calendar: calendar
            ),
            session(
                id: identifier(2),
                daysBefore: 9,
                duration: 18_000,
                role: .gameMaster,
                characterName: "",
                adventureTitle: String(localized: "Moonfall Secrets", bundle: .module),
                participantCount: 6,
                referenceDate: referenceDate,
                calendar: calendar
            ),
            session(
                id: identifier(3),
                daysBefore: 16,
                duration: 11_700,
                role: .player,
                characterName: "Borin",
                adventureTitle: String(localized: "Emberkeep", bundle: .module),
                participantCount: 4,
                referenceDate: referenceDate,
                calendar: calendar
            )
        ]
    }

    private func session(
        id: UUID,
        daysBefore: Int,
        duration: TimeInterval,
        role: GameStatisticRole,
        characterName: String,
        adventureTitle: String,
        participantCount: Int,
        referenceDate: Date,
        calendar: Calendar
    ) -> GameStatisticSessionSnapshot {
        let startedAt = date(daysBefore: daysBefore, referenceDate: referenceDate, calendar: calendar)
        return GameStatisticSessionSnapshot(
            id: id,
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(duration),
            duration: duration,
            role: role,
            localName: "Alex",
            characterID: characterName.isEmpty ? nil : identifier(UInt8(daysBefore)),
            characterName: characterName,
            adventureID: identifier(UInt8(daysBefore + 32)),
            adventureTitle: adventureTitle,
            masterName: "Morgan",
            maxParticipantCount: participantCount
        )
    }

    private func date(daysBefore: Int, referenceDate: Date, calendar: Calendar) -> Date {
        calendar.date(byAdding: .day, value: -daysBefore, to: referenceDate) ?? referenceDate
    }

    private func identifier(_ finalByte: UInt8) -> UUID {
        UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, finalByte))
    }
}
