// @copyright André Trettin

import CoreRPG
import Foundation
import Observation
import TableRPG
import SwiftUI
import CharacterRPG
import PhotoRPG
import os.log

extension GameController {
    @MainActor
    func battleStartPins(itemId: UUID) -> (playerPins: [MapPinModel], roomPins: [MapPinModel])? {
        guard gameModel.currentItemId == itemId,
              let map = gameModel.itemData[itemId] as? MapModel else {
            return nil
        }

        let playerPins = map.mapPins.filter { $0.isPlayer && $0.characterId != nil }
        let roomId = mapGameModel.lastActivatedRoomId(for: itemId)
            ?? map.entries.first(where: \.focused)?.id
        let room = roomId.flatMap { selectedId in
            map.entries.first { $0.id == selectedId }
        }
        let roomPins = room.map { selectedRoom in
            map.mapPins.filter { !$0.isPlayer && selectedRoom.contains($0.location) }
        } ?? []

        guard !playerPins.isEmpty || !roomPins.isEmpty else { return nil }
        return (playerPins, roomPins)
    }

    @MainActor
    @discardableResult
    func beginBattle(
        itemId: UUID,
        playerCombatants: [BattleCombatant],
        roomCombatants: [BattleCombatant],
        initiativeOrder: BattleInitiativeOrder
    ) -> Bool {
        guard let map = gameModel.itemData[itemId] as? MapModel else { return false }
        battleRoundModel.begin(
            mapId: itemId,
            players: playerCombatants,
            roomCombatants: roomCombatants,
            initiativeOrder: initiativeOrder
        )
        battleRoundSettings.initiativeOrder = initiativeOrder
        resolveBattleConfiguredValues()
        _ = battleRoundModel.synchronize(pins: map.mapPins)
        return true
    }

    @MainActor
    func startBattle(
        itemId: UUID,
        initiativeOrder: BattleInitiativeOrder
    ) -> Bool {
        guard let pins = battleStartPins(itemId: itemId) else { return false }

        let playerCombatants = pins.playerPins.map { pin in
            return BattleCombatant(
                pin: pin,
                sourceCharacterId: pin.characterId,
                // A player's Character is already the authoritative game
                // identity. Never clone it merely because a battle starts.
                gameCharacterId: pin.characterId,
                isPlayer: true
            )
        }
        let roomCombatants = pins.roomPins.compactMap { pin in
            makeBattleCombatant(itemId: itemId, pinId: pin.id)
        }

        clearBattleHighlights(itemId: itemId)
        return beginBattle(
            itemId: itemId,
            playerCombatants: playerCombatants,
            roomCombatants: roomCombatants,
            initiativeOrder: initiativeOrder
        )
    }

    @MainActor
    func makeBattleCombatant(itemId: UUID, pinId: UUID) -> BattleCombatant? {
        guard let map = gameModel.itemData[itemId] as? MapModel,
              let pinIndex = map.mapPins.firstIndex(where: { $0.id == pinId }) else {
            return nil
        }
        var pin = map.mapPins[pinIndex]
        let sourceCharacterId = pin.characterId
        let gameCharacterId: UUID?
        if pin.isPlayer {
            gameCharacterId = sourceCharacterId
        } else if let sourceCharacterId,
                  root.characterRoot.valueGameControllable.battleCharacterCopy(
                      for: sourceCharacterId
                  ) != nil {
            gameCharacterId = sourceCharacterId
        } else if let sourceCharacterId,
                  let copyId = root.characterRoot.valueGameControllable
                    .createBattleCharacterCopy(for: sourceCharacterId) {
            mapGameModel.registerBattleCharacterCopy(copyId)
            pin.characterId = copyId
            pin.timeInterval = max(
                Date.now.timeIntervalSince1970,
                pin.timeInterval.nextUp
            )
            map.mapPins[pinIndex] = pin
            gameCharacterId = copyId
        } else {
            gameCharacterId = nil
        }
        return BattleCombatant(
            pin: pin,
            sourceCharacterId: sourceCharacterId,
            gameCharacterId: gameCharacterId,
            isPlayer: pin.isPlayer
        )
    }

    @MainActor
    func clearBattleHighlights(itemId: UUID) {
        guard let map = gameModel.itemData[itemId] as? MapModel else { return }
        for index in map.mapPins.indices where map.mapPins[index].isHighlighted {
            map.mapPins[index].isHighlighted = false
            map.mapPins[index].timeInterval = max(
                Date.now.timeIntervalSince1970,
                map.mapPins[index].timeInterval.nextUp
            )
            if map.mapPins[index].isPlayer,
               let playerIndex = mapGameModel.playerPins.firstIndex(where: {
                   $0.id == map.mapPins[index].id
               }) {
                mapGameModel.playerPins[playerIndex] = map.mapPins[index]
            }
        }
    }

    @MainActor
    func endBattle(itemId: UUID) -> Bool {
        guard battleRoundModel.isRunning,
              battleRoundModel.mapId == itemId,
              let map = gameModel.itemData[itemId] as? MapModel else {
            return false
        }
        clearBattleHighlights(itemId: itemId)
        battleRoundModel.end()
        _ = battleRoundModel.synchronize(pins: map.mapPins)
        return true
    }

    @MainActor
    func setBattleInitiative(
        itemId: UUID,
        combatantId: UUID,
        value: Int?
    ) -> Bool {
        guard battleRoundModel.mapId == itemId else { return false }
        return battleRoundModel.setInitiative(value, for: combatantId)
    }

    @MainActor
    func adjustBattleInitiative(
        itemId: UUID,
        combatantId: UUID,
        amount: Int
    ) -> Bool {
        guard battleRoundModel.mapId == itemId else { return false }
        return battleRoundModel.adjustInitiative(by: amount, for: combatantId)
    }

    @MainActor
    func setBattleInitiativeOrder(
        itemId: UUID,
        order: BattleInitiativeOrder
    ) -> Bool {
        guard battleRoundModel.mapId == itemId else { return false }
        battleRoundSettings.initiativeOrder = order
        return battleRoundModel.setInitiativeOrder(order)
    }

    @MainActor
    func moveBattleEntries(from source: IndexSet, to destination: Int) {
        battleRoundModel.moveEntries(from: source, to: destination)
    }

    @MainActor
    func activateBattleAttacker(itemId: UUID, combatantId: UUID) -> Bool {
        guard battleRoundModel.mapId == itemId,
              battleRoundModel.activateAttacker(combatantId) else {
            return false
        }
        applyActiveBattleHighlights(itemId: itemId)
        return true
    }

    @MainActor
    func nextBattleAttacker(itemId: UUID) -> Bool {
        guard battleRoundModel.mapId == itemId,
              battleRoundModel.nextAttacker() else {
            return false
        }
        applyActiveBattleHighlights(itemId: itemId)
        return true
    }

    @MainActor
    func nextBattleRound(itemId: UUID) -> Bool {
        guard battleRoundModel.mapId == itemId,
              battleRoundModel.nextRound() else {
            return false
        }
        applyActiveBattleHighlights(itemId: itemId)
        return true
    }

    /// Adds a pin that was outside the initially focused room while the
    /// surprise round is still being prepared.
    @MainActor
    func addBattleCombatant(itemId: UUID, pinId: UUID) -> Bool {
        guard battleRoundModel.mapId == itemId,
              battleRoundModel.isPreparingSurprise,
              battleRoundModel.combatant(pinId: pinId) == nil,
              let combatant = makeBattleCombatant(itemId: itemId, pinId: pinId),
              battleRoundModel.addCombatant(combatant) else {
            return false
        }
        resolveBattleConfiguredValues(for: combatant.id)
        return true
    }

    /// Drops a combatant from the battle roster entirely, distinct from
    /// `setBattleCombatantDead` which only flags it. The map pin itself is
    /// untouched, so highlighting it again re-adds a fresh combatant.
    @MainActor
    func removeBattleCombatant(itemId: UUID, combatantId: UUID) -> Bool {
        guard battleRoundModel.mapId == itemId,
              battleRoundModel.removeCombatant(combatantId) else {
            return false
        }
        applyActiveBattleHighlights(itemId: itemId)
        return true
    }

    @MainActor
    func addBattleRoll(
        itemId: UUID,
        combatantId: UUID,
        total: Int,
        expression: String?
    ) -> Bool {
        guard battleRoundModel.mapId == itemId else { return false }
        return battleRoundModel.addRoll(
            combatantId: combatantId,
            total: total,
            expression: expression
        )
    }

    @MainActor
    func selectBattleRollRecipient(itemId: UUID, combatantId: UUID) -> Bool {
        guard battleRoundModel.mapId == itemId else { return false }
        return battleRoundModel.selectRollRecipient(combatantId)
    }

    @MainActor
    func setBattleCombatantDead(
        itemId: UUID,
        combatantId: UUID,
        isDead: Bool
    ) -> Bool {
        guard battleRoundModel.mapId == itemId,
              let combatant = battleRoundModel.combatant(id: combatantId),
              combatant.isDead != isDead,
              updatePinState(itemId: itemId, pinId: combatant.pinId, mutation: { pin in
                  pin.isDead = isDead
              }) else {
            return false
        }
        // Only ever reached via `BattleRoundController.setDead`, which is
        // itself gated on `root.gameModel.gameConfig.isMaster`.
        _ = synchronizeBattleDefenders(itemId: itemId, isGameMaster: true)
        return true
    }

    /// Associates a Character with a battle token without touching the source
    /// database. Empty tokens receive an independent runtime copy. Existing
    /// player identities are reused, while non-player runtime identities are
    /// reused only when their copy is still present in Character game memory.
    @MainActor
    func assignBattleCharacter(
        itemId: UUID,
        combatantId: UUID,
        characterId: UUID
    ) -> Bool {
        guard battleRoundModel.isRunning,
              battleRoundModel.mapId == itemId,
              let combatant = battleRoundModel.combatant(id: combatantId),
              let map = gameModel.itemData[itemId] as? MapModel,
              let pinIndex = map.mapPins.firstIndex(where: { $0.id == combatant.pinId }) else {
            return false
        }

        let currentCharacterId = map.mapPins[pinIndex].characterId
        let sourceCharacterId: UUID
        let gameCharacterId: UUID

        if combatant.isPlayer, let currentCharacterId {
            // Player Characters are shared game identities and must not fork
            // into an isolated monster-style runtime copy.
            sourceCharacterId = currentCharacterId
            gameCharacterId = currentCharacterId
        } else if let currentCharacterId,
                  root.characterRoot.valueGameControllable.battleCharacterCopy(
                      for: currentCharacterId
                  ) != nil {
            // This token already owns a live runtime Character. Treat another
            // selection as a no-op so it cannot advance map state or fork the
            // association while the battle is running.
            return false
        } else {
            let source = currentCharacterId ?? characterId
            guard let copyId = root.characterRoot.valueGameControllable
                .createBattleCharacterCopy(for: source) else {
                return false
            }
            mapGameModel.registerBattleCharacterCopy(copyId)
            sourceCharacterId = source
            gameCharacterId = copyId
        }

        var updatedPin = map.mapPins[pinIndex]
        updatedPin.characterId = gameCharacterId
        updatedPin.timeInterval = max(
            Date.now.timeIntervalSince1970,
            updatedPin.timeInterval.nextUp
        )
        map.mapPins[pinIndex] = updatedPin
        if updatedPin.isPlayer,
           let playerIndex = mapGameModel.playerPins.firstIndex(where: { $0.id == updatedPin.id }) {
            mapGameModel.playerPins[playerIndex] = updatedPin
        }
        let changed = battleRoundModel.assignCharacter(
            combatantId: combatantId,
            sourceCharacterId: sourceCharacterId,
            gameCharacterId: gameCharacterId,
            pin: updatedPin
        )
        if changed {
            resolveBattleConfiguredValues(for: combatantId)
        }
        return changed
    }

    /// The orchestration (resolving the dropped/picked entry, remapping it to
    /// the combatant's own battle-copy entry by name, deriving an initiative
    /// value) lives in GameRPG's `BattleRoundController`, which is the only
    /// place that can reach `GameRoot`. This is the narrow primitive it
    /// composes to actually change `battleRoundModel`'s private state.
    @MainActor
    @discardableResult
    func setBattleValueEntry(
        itemId: UUID,
        combatantId: UUID,
        entryId: UUID?,
        kind: BattleValueKind
    ) -> Bool {
        guard battleRoundModel.mapId == itemId else { return false }
        return battleRoundModel.setValueEntry(entryId, kind: kind, for: combatantId)
    }

    @MainActor
    func refreshBattleConfiguredValues(itemId: UUID) {
        guard battleRoundModel.mapId == itemId else { return }
        resolveBattleConfiguredValues(remap: true)
    }

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
           !attacker.isHighlighted {
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
        var healthChanged = false
        for combatant in battleRoundModel.combatants {
            let percent = healthPercent(for: combatant)
            Logger.gameController.debug(
                "synchronizeBattleDefenders: pin \(combatant.pin.name, privacy: .public) (\(combatant.pinId, privacy: .public)) hitPointsEntryId=\(combatant.hitPointsEntryId?.uuidString ?? "nil", privacy: .public) computed=\(percent.map { "\($0)" } ?? "nil", privacy: .public) previouslyPersisted=\(combatant.pin.healthPercent.map { "\($0)" } ?? "nil", privacy: .public)"
            )
            guard combatant.pin.healthPercent != percent else { continue }
            if updatePinState(itemId: itemId, pinId: combatant.pinId, mutation: { $0.healthPercent = percent }) {
                healthChanged = true
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
    @MainActor
    func healthPercent(for combatant: BattleCombatant) -> Double? {
        guard let gameCharacterId = combatant.gameCharacterId else {
            Logger.gameController.debug("healthPercent: pin \(combatant.pin.name, privacy: .public) has no gameCharacterId — no Character linked yet")
            return nil
        }
        guard let entryId = combatant.hitPointsEntryId else {
            Logger.gameController.debug("healthPercent: pin \(combatant.pin.name, privacy: .public) (character \(gameCharacterId, privacy: .public)) has no hitPointsEntryId resolved")
            return nil
        }
        guard let entry = root.characterRoot.valueGameControllable.gameEntry(
            characterId: gameCharacterId,
            entryId: entryId
        ) else {
            Logger.gameController.debug("healthPercent: pin \(combatant.pin.name, privacy: .public) — gameEntry(characterId:entryId:) found nothing for entryId \(entryId, privacy: .public) on character \(gameCharacterId, privacy: .public)")
            return nil
        }
        guard let baseText = entry.value.split(separator: "|").first.map(String.init) else {
            Logger.gameController.debug("healthPercent: pin \(combatant.pin.name, privacy: .public) — entry \(entry.name, privacy: .public) has an empty value")
            return nil
        }
        let valueGameControllable = root.characterRoot.valueGameControllable
        let resolvedBaseText = valueGameControllable.calculatedValue(baseText, type: .decimal)
        guard let base = resolvedBaseText.flatMap(Double.init), base > 0 else {
            Logger.gameController.debug("healthPercent: pin \(combatant.pin.name, privacy: .public) — entry \(entry.name, privacy: .public) base \(baseText, privacy: .public) resolved to \(resolvedBaseText ?? "nil", privacy: .public), not a positive number")
            return nil
        }
        let resolvedCurrentText = valueGameControllable.calculatedValue(
            entry.value.replacing("|", with: "+"),
            type: .decimal
        )
        let current = resolvedCurrentText.flatMap(Double.init) ?? base
        let percent = min(max(current / base * 100, 0), 100)
        Logger.gameController.debug(
            "healthPercent: pin \(combatant.pin.name, privacy: .public) — entry \(entry.name, privacy: .public) rawValue=\(entry.value, privacy: .public) resolvedBase=\(resolvedBaseText ?? "nil", privacy: .public) resolvedCurrent=\(resolvedCurrentText ?? "nil", privacy: .public) → base=\(base, privacy: .public) current=\(current, privacy: .public) percent=\(percent, privacy: .public)"
        )
        return percent
    }

    @MainActor
    func networkBattleRoundUpdate(for itemId: UUID) -> NetworkCodableDataType? {
        guard battleRoundModel.mapId == itemId,
              let state = battleRoundModel.networkState() else {
            return nil
        }
        let generation = networkGeneration(for: itemId)
        return NetworkCodableDataType(
            id: itemId,
            type: .map,
            version: generation.version,
            data: state.encodeData(),
            assetVersion: generation.assetVersion,
            contentVersion: generation.contentVersion
        )
    }

    @MainActor
    func applyBattleRoundUpdate(for itemId: UUID, with data: NetworkCodableDataType) -> Bool {
        let generation = networkGeneration(for: itemId)
        guard data.id == itemId,
              data.type == .map,
              gameModel.currentItemId == itemId,
              data.version == generation.version,
              data.assetVersion == generation.assetVersion,
              data.contentVersion == generation.contentVersion,
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
