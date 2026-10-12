// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftUI

// Plain Codable/Equatable value types for the Battle Round domain, split out
// of BattleRoundModel.swift — they're unrelated to the `@Observable` class
// mechanics that live there.

public enum BattleInitiativeOrder: Int, Codable, CaseIterable, Identifiable, Sendable {
    case ascending
    case descending

    public var id: Int { rawValue }
}

public enum BattleValueKind: Equatable, Sendable {
    case initiative
    case hitPoints
}

/// A roll the dice rules flagged as special. Plain rolls carry none.
public enum BattleRollOutcome: String, Codable, Equatable, Sendable {
    case critical
    case fumble
}

public struct BattleRollResult: Identifiable, Codable, Equatable, Sendable {
    public init(
        id: UUID = UUID(),
        combatantId: UUID,
        total: Int,
        expression: String? = nil,
        outcome: BattleRollOutcome? = nil,
        timestamp: Date = .now
    ) {
        self.id = id
        self.combatantId = combatantId
        self.total = total
        self.expression = expression
        self.outcome = outcome
        self.timestamp = timestamp
    }

    public let id: UUID
    public let combatantId: UUID
    public let total: Int
    public let expression: String?
    /// Optional, so a battle state sent by an older app version still decodes.
    public let outcome: BattleRollOutcome?
    public let timestamp: Date
}

public struct BattleCombatant: Identifiable, Codable, Equatable, Sendable {
    public init(
        id: UUID = UUID(),
        pin: MapPinModel,
        sourceCharacterId: UUID?,
        gameCharacterId: UUID?,
        initiative: Int? = nil,
        initiativeEntryId: UUID? = nil,
        hitPointsEntryId: UUID? = nil,
        isPlayer: Bool? = nil
    ) {
        self.id = id
        self.pin = pin
        self.sourceCharacterId = sourceCharacterId
        self.gameCharacterId = gameCharacterId
        self.initiative = initiative
        self.initiativeEntryId = initiativeEntryId
        self.hitPointsEntryId = hitPointsEntryId
        self.isPlayer = isPlayer ?? pin.isPlayer
    }

    /// A battle-combatant id is intentionally independent from both the map
    /// pin and Character ids. Several pins may use the same Character template.
    public let id: UUID
    public internal(set) var pin: MapPinModel
    public internal(set) var sourceCharacterId: UUID?
    public internal(set) var gameCharacterId: UUID?
    public internal(set) var initiative: Int?
    public internal(set) var initiativeEntryId: UUID?
    public internal(set) var hitPointsEntryId: UUID?
    public let isPlayer: Bool

    public var pinId: UUID { pin.id }
    public var name: String { pin.name }
    public var photoId: UUID? { pin.photoId }
    public var color: Color { pin.color }
    public var isDead: Bool { pin.isDead }
    public var isHighlighted: Bool { pin.isHighlighted }
}

public struct BattleRoundEntry: Identifiable, Codable, Equatable, Sendable {
    public init(
        id: UUID = UUID(),
        attackerId: UUID,
        defenderIds: [UUID] = [],
        rolls: [BattleRollResult] = []
    ) {
        self.id = id
        self.attackerId = attackerId
        self.defenderIds = defenderIds
        self.rolls = rolls
    }

    public let id: UUID
    public let attackerId: UUID
    public internal(set) var defenderIds: [UUID]
    public internal(set) var rolls: [BattleRollResult]
}

/// The small master-authoritative state sent to every map participant. The
/// initiative table itself remains master-only; participants need only the
/// round and active pin for the shared map presentation.
public struct BattleRoundNetworkState: Codable, Equatable, Sendable, MessageMapper {
    public init(
        mapId: UUID,
        isRunning: Bool,
        roundCounter: Int,
        activePinId: UUID?,
        sequence: Int
    ) {
        self.mapId = mapId
        self.isRunning = isRunning
        self.roundCounter = roundCounter
        self.activePinId = activePinId
        self.sequence = sequence
    }

    public let mapId: UUID
    public let isRunning: Bool
    public let roundCounter: Int
    public let activePinId: UUID?
    public let sequence: Int
}
