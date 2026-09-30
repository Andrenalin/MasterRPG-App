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
        // The diagnostic log below only fires once a combatant's health
        // actually persists a new value, not for every combatant on every
        // battle tick — see CODE_AUDIT §7.1. Gameplay content (pin name,
        // computed value) is logged `.private` rather than `.public` — see
        // CODE_AUDIT §6.3.
        var healthChanged = false
        for combatant in battleRoundModel.combatants {
            let percent = healthPercent(for: combatant)
            guard combatant.pin.healthPercent != percent else { continue }
            if updatePinState(itemId: itemId, pinId: combatant.pinId, mutation: { $0.healthPercent = percent }) {
                healthChanged = true
                Logger.gameController.debug(
                    "synchronizeBattleDefenders: pin \(combatant.pin.name, privacy: .private) (\(combatant.pinId, privacy: .private)) hitPointsEntryId=\(combatant.hitPointsEntryId?.uuidString ?? "nil", privacy: .private) computed=\(percent.map { "\($0)" } ?? "nil", privacy: .private) previouslyPersisted=\(combatant.pin.healthPercent.map { "\($0)" } ?? "nil", privacy: .private)"
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
    /// `entry.value` follows the "base|modifier" convention: the text before
    /// "|" is the maximum (100%), "base+modifier" (with the "|" replaced by
    /// "+") is the current amount. Either side may itself be, or contain, a
    /// markdown link (e.g. `[Lebenskraft](RPG://VALUES/0/<itemId>/<entryId>)`)
    /// pointing at another entry — possibly one whose own value is a further-
    /// linked formula ("KÖR+HÄ+10+LK Level+3"), several hops deep. Both sides
    /// are resolved through `calculatedValue(_:type:)`, the same link-
    /// substitution/recursion engine `gameEntryDisplayValue` runs a stored
    /// entry's own value through (and what the Battle Round roster's own HP
    /// display already relies on) — forcing `.decimal` regardless of the
    /// entry's own type, since `ValueEntryModel.canCalculate` (and so link
    /// resolution) only applies to `.number`/`.decimal` otherwise, and a
    /// `.text` hit-points entry is an easy, reasonable choice for a game
    /// master who just types a number with no reason to think the "type"
    /// picker matters here.
    // Gameplay content (pin names, entry names/values, computed percentages)
    // is logged `.private` throughout this function rather than `.public` —
    // see CODE_AUDIT §6.3.
    @MainActor
    func healthPercent(for combatant: BattleCombatant) -> Double? {
        guard let gameCharacterId = combatant.gameCharacterId else {
            Logger.gameController.debug("healthPercent: pin \(combatant.pin.name, privacy: .private) has no gameCharacterId — no Character linked yet")
            return nil
        }
        guard let entryId = combatant.hitPointsEntryId else {
            Logger.gameController.debug("healthPercent: pin \(combatant.pin.name, privacy: .private) (character \(gameCharacterId, privacy: .private)) has no hitPointsEntryId resolved")
            return nil
        }
        guard let entry = root.characterRoot.valueGameControllable.gameEntry(
            characterId: gameCharacterId,
            entryId: entryId
        ) else {
            Logger.gameController.debug("healthPercent: pin \(combatant.pin.name, privacy: .private) — gameEntry(characterId:entryId:) found nothing for entryId \(entryId, privacy: .private) on character \(gameCharacterId, privacy: .private)")
            return nil
        }
        guard let baseText = entry.value.split(separator: "|").first.map(String.init) else {
            Logger.gameController.debug("healthPercent: pin \(combatant.pin.name, privacy: .private) — entry \(entry.name, privacy: .private) has an empty value")
            return nil
        }
        let valueGameControllable = root.characterRoot.valueGameControllable
        let resolvedBaseText = valueGameControllable.calculatedValue(baseText, type: .decimal)
        guard let base = resolvedBaseText.flatMap(Double.init), base > 0 else {
            Logger.gameController.debug("healthPercent: pin \(combatant.pin.name, privacy: .private) — entry \(entry.name, privacy: .private) base \(baseText, privacy: .private) resolved to \(resolvedBaseText ?? "nil", privacy: .private), not a positive number")
            return nil
        }
        let resolvedCurrentText = valueGameControllable.calculatedValue(
            entry.value.replacing("|", with: "+"),
            type: .decimal
        )
        let current = resolvedCurrentText.flatMap(Double.init) ?? base
        let percent = min(max(current / base * 100, 0), 100)
        Logger.gameController.debug(
            "healthPercent: pin \(combatant.pin.name, privacy: .private) — entry \(entry.name, privacy: .private) rawValue=\(entry.value, privacy: .private) resolvedBase=\(resolvedBaseText ?? "nil", privacy: .private) resolvedCurrent=\(resolvedCurrentText ?? "nil", privacy: .private) → base=\(base, privacy: .private) current=\(current, privacy: .private) percent=\(percent, privacy: .private)"
        )
        return percent
    }

    // MARK: - Network apply / export

    @MainActor
    func networkBattleRoundUpdate(for itemId: UUID) -> NetworkCodableDataType? {
        guard battleRoundModel.mapId == itemId,
              let state = battleRoundModel.networkState() else {
            return nil
        }
        // See CODE_AUDIT §9.2 — shared envelope factory.
        return Self.mapNetworkData(
            id: itemId,
            generation: networkGeneration(for: itemId),
            data: state.encodeData()
        )
    }

    @MainActor
    func applyBattleRoundUpdate(for itemId: UUID, with data: NetworkCodableDataType) -> Bool {
        // See CODE_AUDIT §9.3 — shared generation-match guard, kept in sync
        // with `updatePinIfCurrentGeneration` in GameController+Pins.swift.
        // A generation mismatch here has no reconciliation of its own: the
        // caller (`PlayerController+Map.swift`'s `.battleRound` case) defers
        // and replays this exact payload once a matching `.mapState` lands —
        // see CODE_AUDIT §5.2.
        guard isCurrentGeneration(data, for: itemId),
              let state = BattleRoundNetworkState.decodeData(of: data.data),
              state.mapId == itemId else {
            return false
        }
        return battleRoundModel.applyRemoteState(state)
    }

    @MainActor
    func resetBattleRound() {
        releaseBattleCharacters(includingPlayers: true)
        mapGameModel.clearBattleCharacterCopies()
        battleRoundModel.reset()
    }
}
