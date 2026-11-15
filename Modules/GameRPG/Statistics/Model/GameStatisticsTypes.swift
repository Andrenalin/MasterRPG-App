// @copyright André Trettin

import CoreRPG
import Foundation

// MARK: - Classification Enums

enum GameStatisticRole: Int16, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case unknown
    case gameMaster
    case player
    case observer
    case proxy

    var id: Self { self }

    init(gameType: GameType) {
        self = switch gameType {
        case .master: .gameMaster
        case .player: .player
        case .observer: .observer
        case .proxy: .proxy
        case .notSet, .demo: .unknown
        }
    }

    var title: String {
        switch self {
        case .unknown: String(localized: "Unknown", bundle: .module)
        case .gameMaster: String(localized: "Game Master", bundle: .module)
        case .player: String(localized: "Player", bundle: .module)
        case .observer: String(localized: "Observer", bundle: .module)
        case .proxy: String(localized: "Proxy", bundle: .module)
        }
    }

    var systemImage: String {
        switch self {
        case .unknown: "questionmark.circle"
        case .gameMaster: "crown"
        case .player: "person"
        case .observer: "eye"
        case .proxy: "arrow.triangle.branch"
        }
    }
}

enum GameStatisticSessionEndReason: Int16, Codable, Hashable, Sendable {
    case unknown
    case stopped
    case interrupted
    case connectionFailed
}

enum GameStatisticEventKind: Int16, CaseIterable, Codable, Hashable, Sendable {
    case message
    case contentShared
    case audioPlayed
    case diceRolled
    case participantJoined
    case participantLeft
    case deliveryAcknowledged
    case deliveryFailed
}

enum GameStatisticDirection: Int16, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case local
    case incoming
    case outgoing

    var id: Self { self }

    var title: String {
        switch self {
        case .local: String(localized: "Local", bundle: .module)
        case .incoming: String(localized: "Received", bundle: .module)
        case .outgoing: String(localized: "Sent", bundle: .module)
        }
    }
}

enum GameStatisticOrigin: Int16, Codable, Hashable, Sendable {
    case local
    case localNetwork
    case proxy
    case sharePlay
    case fileTransfer

    init(_ origin: GameMessageOrigin) {
        self = switch origin {
        case .direct: .localNetwork
        case .proxy: .proxy
        case .sharePlay: .sharePlay
        case .file: .fileTransfer
        }
    }
}

enum GameStatisticDiceOutcome: Int16, CaseIterable, Codable, Hashable, Sendable {
    case none
    case rolled
    case critical
    case fumble
    case notRolled

    var title: String {
        switch self {
        case .none: String(localized: "Other", bundle: .module)
        case .rolled: String(localized: "Rolled", bundle: .module)
        case .critical: String(localized: "Critical", bundle: .module)
        case .fumble: String(localized: "Fumble", bundle: .module)
        case .notRolled: String(localized: "Not rolled", bundle: .module)
        }
    }
}

enum GameStatisticsDateRange: Int, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case lastThirtyDays
    case lastSixMonths
    case lastYear
    case allTime

    var id: Self { self }

    var title: String {
        switch self {
        case .lastThirtyDays: String(localized: "30 Days", bundle: .module)
        case .lastSixMonths: String(localized: "6 Months", bundle: .module)
        case .lastYear: String(localized: "1 Year", bundle: .module)
        case .allTime: String(localized: "All Time", bundle: .module)
        }
    }

    func interval(endingAt end: Date, calendar: Calendar) -> DateInterval? {
        let start: Date?
        switch self {
        case .lastThirtyDays:
            start = calendar.date(byAdding: .day, value: -30, to: end)
        case .lastSixMonths:
            start = calendar.date(byAdding: .month, value: -6, to: end)
        case .lastYear:
            start = calendar.date(byAdding: .year, value: -1, to: end)
        case .allTime:
            return nil
        }
        return start.map { DateInterval(start: $0, end: end) }
    }
}

enum GameStatisticsGranularity: Int, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case day
    case week
    case month

    var id: Self { self }

    var title: String {
        switch self {
        case .day: String(localized: "Day", bundle: .module)
        case .week: String(localized: "Week", bundle: .module)
        case .month: String(localized: "Month", bundle: .module)
        }
    }

    var calendarComponent: Calendar.Component {
        switch self {
        case .day: .day
        case .week: .weekOfYear
        case .month: .month
        }
    }
}

enum GameStatisticsMetric: Int, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case duration
    case sessions

    var id: Self { self }

    var title: String {
        switch self {
        case .duration: String(localized: "Play Time", bundle: .module)
        case .sessions: String(localized: "Games", bundle: .module)
        }
    }
}

enum GameStatisticsSection: Int, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case activity
    case schedule
    case roles
    case characters
    case adventures
    case dice
    case sharedContent
    case party
    case network

    var id: Self { self }

    var title: String {
        switch self {
        case .activity: String(localized: "Activity", bundle: .module)
        case .schedule: String(localized: "When You Play", bundle: .module)
        case .roles: String(localized: "Roles", bundle: .module)
        case .characters: String(localized: "Characters", bundle: .module)
        case .adventures: String(localized: "Adventures", bundle: .module)
        case .dice: String(localized: "Dice", bundle: .module)
        case .sharedContent: String(localized: "Shared Content", bundle: .module)
        case .party: String(localized: "Party", bundle: .module)
        case .network: String(localized: "Connection", bundle: .module)
        }
    }

    var systemImage: String {
        switch self {
        case .activity: "chart.xyaxis.line"
        case .schedule: "calendar"
        case .roles: "person.badge.key"
        case .characters: "person.crop.circle"
        case .adventures: "book.pages"
        case .dice: "dice"
        case .sharedContent: "square.and.arrow.up"
        case .party: "person.3"
        case .network: "network"
        }
    }
}

// MARK: - Dashboard Configuration

struct GameStatisticsDashboardConfiguration: Codable, Hashable, Sendable {
    var dateRange: GameStatisticsDateRange = .lastSixMonths
    var granularity: GameStatisticsGranularity = .week
    var metric: GameStatisticsMetric = .duration
    var direction: GameStatisticDirection? = nil
    var sectionOrder: [GameStatisticsSection] = GameStatisticsSection.allCases
    var hiddenSections: Set<GameStatisticsSection> = []

    static let `default` = GameStatisticsDashboardConfiguration()

    private enum CodingKeys: String, CodingKey {
        case dateRange, granularity, metric, direction, sectionOrder, hiddenSections
    }

    /// Tolerant of older and newer saved data: a missing field keeps its default, an unknown case
    /// is dropped, and a section the saved order does not know is appended. A dashboard saved by a
    /// newer version must not reset the whole configuration. See CODE_AUDIT_26 §5.86.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = GameStatisticsDashboardConfiguration()
        dateRange = (try? container.decodeIfPresent(GameStatisticsDateRange.self, forKey: .dateRange)) ?? defaults.dateRange
        granularity = (try? container.decodeIfPresent(GameStatisticsGranularity.self, forKey: .granularity)) ?? defaults.granularity
        metric = (try? container.decodeIfPresent(GameStatisticsMetric.self, forKey: .metric)) ?? defaults.metric
        direction = (try? container.decodeIfPresent(GameStatisticDirection.self, forKey: .direction)) ?? nil
        let savedOrder = ((try? container.decodeIfPresent([Int].self, forKey: .sectionOrder)) ?? nil) ?? []
        var order: [GameStatisticsSection] = []
        for raw in savedOrder {
            if let section = GameStatisticsSection(rawValue: raw), !order.contains(section) {
                order.append(section)
            }
        }
        order += GameStatisticsSection.allCases.filter { !order.contains($0) }
        sectionOrder = order
        let savedHidden = ((try? container.decodeIfPresent([Int].self, forKey: .hiddenSections)) ?? nil) ?? []
        hiddenSections = Set(savedHidden.compactMap(GameStatisticsSection.init(rawValue:)))
    }

    init(
        dateRange: GameStatisticsDateRange = .lastSixMonths,
        granularity: GameStatisticsGranularity = .week,
        metric: GameStatisticsMetric = .duration,
        direction: GameStatisticDirection? = nil,
        sectionOrder: [GameStatisticsSection] = GameStatisticsSection.allCases,
        hiddenSections: Set<GameStatisticsSection> = []
    ) {
        self.dateRange = dateRange
        self.granularity = granularity
        self.metric = metric
        self.direction = direction
        self.sectionOrder = sectionOrder
        self.hiddenSections = hiddenSections
    }

    var visibleSections: [GameStatisticsSection] {
        sectionOrder.filter { !hiddenSections.contains($0) }
    }

    /// What the dashboard shows when the selected range holds no game. A range narrower than
    /// "All Time" may simply miss the games that exist, so it says so and keeps the filters
    /// reachable; only "All Time" without a game is a dashboard that has nothing yet (the sample).
    /// See CODE_AUDIT_26 §5.19.
    var emptyState: GameStatisticsEmptyState {
        dateRange == .allTime ? .sample : .noGamesInRange
    }
}

enum GameStatisticsEmptyState: Sendable {
    /// No game was ever recorded: the sample dashboard explains what the statistics will show.
    case sample
    /// No game in a limited range; a wider range may have some.
    case noGamesInRange
}

// MARK: - Draft Types (Recording Input)

struct GameStatisticSessionDraft: Sendable {
    let id: UUID
    let startedAt: Date
    let role: GameStatisticRole
    let localParticipantId: UUID
    let localName: String
    let characterId: UUID?
    let characterName: String
    let adventureId: UUID?
    let adventureTitle: String
    let masterId: UUID?
    let masterName: String
    let isDemo: Bool
    let participants: [GameStatisticParticipantDraft]
}

struct GameStatisticParticipantDraft: Sendable {
    let participantId: UUID
    let characterId: UUID?
    let name: String
    let characterName: String
    let role: GameStatisticRole
    let isLocal: Bool
    let isGameMaster: Bool
}

struct GameStatisticEventDraft: Sendable {
    let id: UUID
    let sessionId: UUID
    let occurredAt: Date
    let kind: GameStatisticEventKind
    let direction: GameStatisticDirection
    let origin: GameStatisticOrigin
    let actorId: UUID?
    let actorCharacterId: UUID?
    let actorName: String
    let targetId: UUID?
    let itemId: UUID?
    let itemName: String
    let module: NetworkModules
    let messageTypeRaw: Int16
    let actionRaw: Int16
    let outcome: GameStatisticDiceOutcome
    let quantity: Int32
    let numericValue: Double
    let resultValues: String
    let checked: Bool
    let payloadByteCount: Int64
    let messageCounter: Int64
    let proxyCounter: Int64
    let dataVersion: Int32
    let success: Bool
    let deduplicationKey: String
}

// MARK: - Snapshot Types (Read Models)

struct GameStatisticSessionSnapshot: Identifiable, Hashable, Sendable {
    let id: UUID
    let startedAt: Date
    let endedAt: Date
    let duration: TimeInterval
    let role: GameStatisticRole
    let localName: String
    let characterId: UUID?
    let characterName: String
    let adventureId: UUID?
    let adventureTitle: String
    let masterName: String
    let maxParticipantCount: Int
}

struct GameStatisticParticipantSnapshot: Identifiable, Hashable, Sendable {
    let id: UUID
    let sessionId: UUID
    let participantId: UUID
    let characterId: UUID?
    let name: String
    let characterName: String
    let role: GameStatisticRole
    let connectedDuration: TimeInterval
    let joinCount: Int
    let isLocal: Bool
}

struct GameStatisticEventSnapshot: Identifiable, Hashable, Sendable {
    let id: UUID
    let sessionId: UUID
    let occurredAt: Date
    let kind: GameStatisticEventKind
    let direction: GameStatisticDirection
    let origin: GameStatisticOrigin
    let actorName: String
    /// The participant that sent the message; `nil` for events recorded without one.
    let actorId: UUID?
    let module: NetworkModules
    let outcome: GameStatisticDiceOutcome
    let quantity: Int
    let numericValue: Double
    let payloadByteCount: Int64
    let success: Bool
}

// MARK: - Chart Data Points

struct GameStatisticsDataSet: Sendable {
    let sessions: [GameStatisticSessionSnapshot]
    let participants: [GameStatisticParticipantSnapshot]
    let events: [GameStatisticEventSnapshot]

    static let empty = GameStatisticsDataSet(sessions: [], participants: [], events: [])
}

struct GameStatisticTimePoint: Identifiable, Hashable, Sendable {
    let date: Date
    let duration: TimeInterval
    let sessionCount: Int

    var id: Date { date }

    func value(for metric: GameStatisticsMetric) -> Double {
        switch metric {
        case .duration: duration / 3_600
        case .sessions: Double(sessionCount)
        }
    }
}

struct GameStatisticCategoryPoint: Identifiable, Hashable, Sendable {
    let key: String
    let title: String
    let value: Double
    let count: Int

    var id: String { key }

    func value(for metric: GameStatisticsMetric) -> Double {
        switch metric {
        case .duration: value / 3_600
        case .sessions: Double(count)
        }
    }
}

struct GameStatisticHeatMapPoint: Identifiable, Hashable, Sendable {
    let weekday: Int
    let hour: Int
    let duration: TimeInterval

    var id: String { "\(weekday)-\(hour)" }
}

// MARK: - Aggregated Summary

struct GameStatisticsSummary: Sendable {
    let sessionCount: Int
    let totalDuration: TimeInterval
    let averageDuration: TimeInterval
    let longestDuration: TimeInterval
    /// Most participants in any counted game; `recentSessions` only holds the newest few.
    var largestPartySize: Int = 0
    let gameMasterDuration: TimeInterval
    let playerDuration: TimeInterval
    let diceRollCount: Int
    let criticalCount: Int
    let fumbleCount: Int
    let payloadByteCount: Int64
    let activity: [GameStatisticTimePoint]
    let schedule: [GameStatisticHeatMapPoint]
    let roles: [GameStatisticCategoryPoint]
    let characters: [GameStatisticCategoryPoint]
    let adventures: [GameStatisticCategoryPoint]
    let diceOutcomes: [GameStatisticCategoryPoint]
    let modules: [GameStatisticCategoryPoint]
    let party: [GameStatisticCategoryPoint]
    let network: [GameStatisticCategoryPoint]
    let recentSessions: [GameStatisticSessionSnapshot]

    static let empty = GameStatisticsSummary(
        sessionCount: 0,
        totalDuration: 0,
        averageDuration: 0,
        longestDuration: 0,
        gameMasterDuration: 0,
        playerDuration: 0,
        diceRollCount: 0,
        criticalCount: 0,
        fumbleCount: 0,
        payloadByteCount: 0,
        activity: [],
        schedule: [],
        roles: [],
        characters: [],
        adventures: [],
        diceOutcomes: [],
        modules: [],
        party: [],
        network: [],
        recentSessions: []
    )
}

#if DEBUG
private enum GameStatisticsFixture {
    static let sessionId = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1))
    static let participantId = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2))
    static let characterId = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3))
    static let adventureId = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 4))
    static let eventId = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 5))
    static let date = Date(timeIntervalSince1970: 1_704_067_200)
}

extension GameStatisticSessionDraft {
    static func fixture(
        id: UUID = GameStatisticsFixture.sessionId,
        startedAt: Date = GameStatisticsFixture.date,
        role: GameStatisticRole = .player,
        localParticipantId: UUID = GameStatisticsFixture.participantId,
        participants: [GameStatisticParticipantDraft] = [.fixture()]
    ) -> Self {
        Self(
            id: id,
            startedAt: startedAt,
            role: role,
            localParticipantId: localParticipantId,
            localName: "Test Player",
            characterId: GameStatisticsFixture.characterId,
            characterName: "Test Hero",
            adventureId: GameStatisticsFixture.adventureId,
            adventureTitle: "Test Adventure",
            masterId: nil,
            masterName: "Test Game Master",
            isDemo: false,
            participants: participants
        )
    }
}

extension GameStatisticParticipantDraft {
    static func fixture(
        participantId: UUID = GameStatisticsFixture.participantId,
        characterId: UUID? = GameStatisticsFixture.characterId,
        name: String = "Test Player",
        characterName: String = "Test Hero",
        role: GameStatisticRole = .player,
        isLocal: Bool = true,
        isGameMaster: Bool = false
    ) -> Self {
        Self(
            participantId: participantId,
            characterId: characterId,
            name: name,
            characterName: characterName,
            role: role,
            isLocal: isLocal,
            isGameMaster: isGameMaster
        )
    }
}

extension GameStatisticEventDraft {
    static func fixture(
        id: UUID = GameStatisticsFixture.eventId,
        sessionId: UUID = GameStatisticsFixture.sessionId,
        occurredAt: Date = GameStatisticsFixture.date.addingTimeInterval(60),
        kind: GameStatisticEventKind = .diceRolled,
        outcome: GameStatisticDiceOutcome = .critical,
        deduplicationKey: String = "test-event"
    ) -> Self {
        Self(
            id: id,
            sessionId: sessionId,
            occurredAt: occurredAt,
            kind: kind,
            direction: .outgoing,
            origin: .localNetwork,
            actorId: GameStatisticsFixture.participantId,
            actorCharacterId: GameStatisticsFixture.characterId,
            actorName: "Test Hero",
            targetId: nil,
            itemId: nil,
            itemName: "",
            module: .dice,
            messageTypeRaw: 0,
            actionRaw: 0,
            outcome: outcome,
            quantity: 1,
            numericValue: 20,
            resultValues: "20",
            checked: true,
            payloadByteCount: 128,
            messageCounter: 1,
            proxyCounter: 0,
            dataVersion: 1,
            success: true,
            deduplicationKey: deduplicationKey
        )
    }
}

extension GameStatisticSessionSnapshot {
    static func fixture(
        id: UUID = GameStatisticsFixture.sessionId,
        startedAt: Date = GameStatisticsFixture.date,
        duration: TimeInterval = 3_600,
        role: GameStatisticRole = .player,
        characterId: UUID? = GameStatisticsFixture.characterId,
        characterName: String = "Test Hero",
        adventureId: UUID? = GameStatisticsFixture.adventureId,
        adventureTitle: String = "Test Adventure",
        maxParticipantCount: Int = 4
    ) -> Self {
        Self(
            id: id,
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(duration),
            duration: duration,
            role: role,
            localName: "Test Player",
            characterId: characterId,
            characterName: characterName,
            adventureId: adventureId,
            adventureTitle: adventureTitle,
            masterName: "Test Game Master",
            maxParticipantCount: maxParticipantCount
        )
    }
}

extension GameStatisticParticipantSnapshot {
    static func fixture(
        id: UUID = GameStatisticsFixture.participantId,
        sessionId: UUID = GameStatisticsFixture.sessionId,
        participantId: UUID = GameStatisticsFixture.participantId,
        characterId: UUID? = GameStatisticsFixture.characterId,
        name: String = "Remote Player",
        characterName: String = "Remote Hero",
        connectedDuration: TimeInterval = 3_600,
        isLocal: Bool = false
    ) -> Self {
        Self(
            id: id,
            sessionId: sessionId,
            participantId: participantId,
            characterId: characterId,
            name: name,
            characterName: characterName,
            role: .player,
            connectedDuration: connectedDuration,
            joinCount: 1,
            isLocal: isLocal
        )
    }
}

extension GameStatisticEventSnapshot {
    static func fixture(
        id: UUID = GameStatisticsFixture.eventId,
        sessionId: UUID = GameStatisticsFixture.sessionId,
        kind: GameStatisticEventKind = .diceRolled,
        direction: GameStatisticDirection = .outgoing,
        origin: GameStatisticOrigin = .localNetwork,
        actorId: UUID? = GameStatisticsFixture.participantId,
        module: NetworkModules = .dice,
        outcome: GameStatisticDiceOutcome = .critical,
        quantity: Int = 1,
        payloadByteCount: Int64 = 128
    ) -> Self {
        Self(
            id: id,
            sessionId: sessionId,
            occurredAt: GameStatisticsFixture.date.addingTimeInterval(60),
            kind: kind,
            direction: direction,
            origin: origin,
            actorName: "Test Hero",
            actorId: actorId,
            module: module,
            outcome: outcome,
            quantity: quantity,
            numericValue: 20,
            payloadByteCount: payloadByteCount,
            success: true
        )
    }
}
#endif
