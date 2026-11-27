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

// MARK: - Dashboard Configuration

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

/// What a player learns about the game only after joining: who runs it and which adventure it is.
/// A checkpoint fills it into a session that began before the master's state had arrived.
/// See CODE_AUDIT §5.11.
struct GameStatisticSessionDetails: Sendable {
    let masterId: UUID?
    let masterName: String
    let adventureId: UUID?
    let adventureTitle: String
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

    /// What `fetchDataSet(interval:direction:)` would load, taken from an already loaded set, so
    /// one fetch of everything serves the dashboard range and the achievements.
    /// See CODE_AUDIT_28 §7.3.
    func filtered(interval: DateInterval?, direction: GameStatisticDirection?) -> GameStatisticsDataSet {
        let keptSessions = interval.map { interval in
            sessions.filter { $0.startedAt >= interval.start && $0.startedAt <= interval.end }
        } ?? sessions
        let keptIds = Set(keptSessions.map(\.id))
        return GameStatisticsDataSet(
            sessions: keptSessions,
            participants: participants.filter { keptIds.contains($0.sessionId) },
            events: events.filter { event in
                keptIds.contains(event.sessionId) && (direction.map { event.direction == $0 } ?? true)
            }
        )
    }
}

struct GameStatisticTimePoint: Identifiable, Hashable, Sendable {
    let date: Date
    let duration: TimeInterval
    let sessionCount: Int

    var id: Date { date }

    /// The bucket a selected date falls into: the latest bucket that starts at or before it, or the
    /// first bucket for a date before all of them. See CODE_AUDIT_26 §5.89 / §10.13.
    static func bucketDate(containing selected: Date, in dates: [Date]) -> Date? {
        dates.filter { $0 <= selected }.max() ?? dates.min()
    }

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

struct GameStatisticsSummary: Equatable, Sendable {
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

extension GameStatisticSessionSnapshot {
    /// The session with its duration (and end) limited to `limit` seconds.
    func capped(to limit: TimeInterval) -> Self {
        guard duration > limit else { return self }
        return Self(
            id: id,
            startedAt: startedAt,
            endedAt: min(endedAt, startedAt.addingTimeInterval(limit)),
            duration: limit,
            role: role,
            localName: localName,
            characterId: characterId,
            characterName: characterName,
            adventureId: adventureId,
            adventureTitle: adventureTitle,
            masterName: masterName,
            maxParticipantCount: maxParticipantCount
        )
    }
}
