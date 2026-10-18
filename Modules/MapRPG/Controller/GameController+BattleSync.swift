// @copyright André Trettin

import CoreRPG
import Foundation
import Observation
import TableRPG
import SwiftUI
import CharacterRPG
import PhotoRPG
import os.log

// Split out of GameController+Battle.swift — see CODE_AUDIT_19 §9.23.

extension GameController {
    // MARK: - Defender / health sync

    /// The game master is the sole authority for battle state: auto-adding a
    /// newly highlighted pin as a defender, repairing the attacker highlight,
    /// and — critically — recomputing `pin.healthPercent` from each
    /// combatant's linked hit-points entry. A player's own device runs this
    /// same call chain too (e.g. `toggleHighlightPin` when *they* highlight a
    /// target), but a player only ever has an empty local `battleRoundModel`
    /// (players never receive the combatants array over the network — see
    /// `BattleRoundNetworkState`) and no local access to another Character's
    /// template, so `makeBattleCombatant` can't resolve a real combatant
    /// there. Letting the loop below run anyway used to overwrite the pin's
    /// already-correct, master-broadcast `healthPercent` with `nil` right on
    /// the player's own screen — a healthy green monster a player merely
    /// highlighted turned gray, and no highlight-only master action ever
    /// came along to correct it back. Gating the whole function on
    /// `isGameMaster` makes the master's broadcast the only thing that can
    /// ever set `pin.healthPercent`, on every device, matching "the
    /// gamemaster must overwrite the player's mappins — players should never
    /// change healthPercent."
    @MainActor
    @discardableResult
    func synchronizeBattleDefenders(itemId: UUID, isGameMaster: Bool) -> (changed: Bool, healthChanged: Bool) {
        guard isGameMaster,
              battleRoundModel.isRunning,
              battleRoundModel.mapId == itemId,
              let map = gameModel.itemData[itemId] as? MapModel else {
            return (false, false)
        }

        var repairedAttacker = false
        if let attackerPinId = battleRoundModel.activePinId,
           let attacker = map.mapPins.first(where: { $0.id == attackerPinId }),
           !attacker.isHighlighted,
           !attacker.isDead {
            repairedAttacker = updatePinState(
                itemId: itemId,
                pinId: attackerPinId,
                mutation: { $0.isHighlighted = true }
            )
        }

        let additionalDefenderPinIds = map.mapPins.compactMap { pin -> UUID? in
            guard pin.isHighlighted,
                  pin.id != battleRoundModel.activePinId,
                  battleRoundModel.combatant(pinId: pin.id) == nil else {
                return nil
            }
            return pin.id
        }
        let additionalDefenders = additionalDefenderPinIds.compactMap { pinId in
            makeBattleCombatant(itemId: itemId, pinId: pinId)
        }
        let changed = battleRoundModel.synchronize(
            pins: map.mapPins,
            additionalDefenders: additionalDefenders
        )

        // `makeBattleCombatant` never resolves ini/HP entry ids — every other
        // combatant-creation path (`beginBattle`, `addBattleCombatant`,
        // `assignCharacter`) follows it with `resolveBattleConfiguredValues`,
        // but this auto-add-on-highlight path didn't. Without this, a freshly
        // added defender's still-nil `hitPointsEntryId` reads as "unknown
        // health" in the loop right below and immediately overwrites its
        // already-correct `pin.healthPercent` with `nil` — e.g. a player
        // highlighting a healthy green monster as their target turns it gray
        // on the spot, on whichever device (master or player) just ran this.
        for defender in additionalDefenders {
            resolveBattleConfiguredValues(for: defender.id)
        }

        // Runs on every master tick while a battle is active, so a hit-points
        // entry edited on the Character sheet (outside any Map/BattleRound
        // action) still reaches the pin's health-bar border without a
        // dedicated notification path.
        // The diagnostic log fires only once a combatant's health actually
        // persists a new value, never per combatant per tick. Gameplay
        // content (pin name, computed value) is logged `.private`.
        var healthChanged = false
        for combatant in battleRoundModel.combatants {
            let health = battleHealth(for: combatant)
            let percent = health.percent
            guard combatant.pin.healthPercent != percent else { continue }
            if updatePinState(itemId: itemId, pinId: combatant.pinId, mutation: { $0.healthPercent = percent }) {
                healthChanged = true
                Logger.gameController.debug(
                    "synchronizeBattleDefenders: pin \(combatant.pin.name, privacy: .private) (\(combatant.pinId, privacy: .private)) health \(health.logDescription, privacy: .private) previouslyPersisted=\(combatant.pin.healthPercent.map { "\($0)" } ?? "nil", privacy: .private)"
                )
            }
        }
        if healthChanged {
            _ = battleRoundModel.synchronize(pins: map.mapPins)
        }

        return (repairedAttacker || changed || healthChanged, healthChanged)
    }

    /// Also called directly by `MapPinView` to render a tracked combatant's
    /// pin live — reading `entry.value` here touches the same `@Observable`
    /// `ValueModel.entries` storage the Character sheet edits, so that render
    /// updates the instant the game master changes hit points, with no
    /// dependency on the periodic broadcast in `synchronizeBattleDefenders`
    /// above. A player has no combatant locally (only the master's
    /// `battleRoundModel` is ever populated with combatants — see
    /// `BattleRoundNetworkState`), so this path only ever fires for the
    /// master; players still see `pin.healthPercent`, the persisted value
    /// `synchronizeBattleDefenders`/`resolveBattleConfiguredValues` push onto
    /// the pin for the network.
    ///
    /// Runs on the render path and at least once per combatant on every
    /// sync, so it does not log. Why a value could not be computed is
    /// reported by `battleHealth(for:)`'s callers, and only when the
    /// persisted percent changes.
    @MainActor
    func healthPercent(for combatant: BattleCombatant) -> Double? {
        battleHealth(for: combatant).percent
    }

    /// The health of a combatant, or the reason it cannot be computed.
    ///
    /// `entry.value` follows the "base|modifier" convention: the base is the
    /// maximum (100%), base plus modifier the current amount. Either side
    /// may itself be, or contain, a markdown link (e.g.
    /// `[Lebenskraft](RPG://VALUES/0/<itemId>/<entryId>)`) pointing at
    /// another entry — possibly one whose own value is a further-linked
    /// formula ("KÖR+HÄ+10+LK Level+3"), several hops deep. The Character
    /// module owns that convention and resolves both numbers
    /// (`gameValueBaseAndCurrent`), through the same link engine the Battle
    /// Round roster's own HP display uses and regardless of the entry's own
    /// type — a `.text` hit-points entry is an easy, reasonable choice for a
    /// game master who just types a number.
    @MainActor
    func battleHealth(for combatant: BattleCombatant) -> BattleHealth {
        guard let gameCharacterId = combatant.gameCharacterId else {
            return .noCharacter
        }
        guard let entryId = combatant.hitPointsEntryId else {
            return .noHitPointsEntry
        }
        let valueGameControllable = root.characterRoot.valueGameControllable
        guard let entry = valueGameControllable.gameEntry(
            characterId: gameCharacterId,
            entryId: entryId
        ) else {
            return .entryNotFound(entryId)
        }
        guard let numbers = valueGameControllable.gameValueBaseAndCurrent(entry.value),
              numbers.base > 0 else {
            return .notCalculable(entryName: entry.name, value: entry.value)
        }
        return .percent(min(max(numbers.current / numbers.base * 100, 0), 100))
    }

    // MARK: - Network apply / export

    @MainActor
    func networkBattleRoundUpdate(for itemId: UUID) -> NetworkCodableDataType? {
        guard battleRoundModel.mapId == itemId,
              let state = battleRoundModel.networkState() else {
            return nil
        }
        // The shared envelope factory.
        return Self.mapNetworkData(
            id: itemId,
            generation: networkGeneration(for: itemId),
            data: state.encodeData()
        )
    }

    @MainActor
    func applyBattleRoundUpdate(for itemId: UUID, with data: NetworkCodableDataType) -> Bool {
        // The shared generation-match guard, kept in sync with
        // `updatePinIfCurrentGeneration` in GameController+Pins.swift.
        // A generation mismatch here has no reconciliation of its own: the
        // caller (`PlayerController+Map.swift`'s `.battleRound` case) defers
        // and replays this exact payload once a matching `.mapState` lands.
        guard isCurrentGeneration(data, for: itemId),
              let state = BattleRoundNetworkState.decodeData(of: data.data),
              state.mapId == itemId else {
            return false
        }
        return battleRoundModel.applyRemoteState(state)
    }

    @MainActor
    func resetBattleRound() {
        releaseBattleCharacters()
        mapGameModel.clearBattleCharacterCopies()
        battleRoundModel.reset()
    }
}

/// A combatant's health in percent of its maximum, or why there is none.
enum BattleHealth: Equatable {
    case percent(Double)
    /// No Character is linked to the token yet.
    case noCharacter
    /// The Character has no hit-points entry chosen or detected.
    case noHitPointsEntry
    /// The chosen entry no longer exists on the Character.
    case entryNotFound(UUID)
    /// The entry's base is not a positive number: free text, or a formula
    /// that does not evaluate. The card marks this next to "HP".
    case notCalculable(entryName: String, value: String)

    var percent: Double? {
        if case .percent(let percent) = self { return percent }
        return nil
    }

    /// For the diagnostic logs at the places a new value is persisted.
    /// Contains gameplay content; log it `.private`.
    var logDescription: String {
        switch self {
        case .percent(let percent):
            "percent=\(percent)"
        case .noCharacter:
            "nil (no Character linked)"
        case .noHitPointsEntry:
            "nil (no hit-points entry resolved)"
        case .entryNotFound(let entryId):
            "nil (entry \(entryId) not found on the Character)"
        case let .notCalculable(entryName, value):
            "nil (entry \(entryName) value \(value) has no positive numeric base)"
        }
    }
}
