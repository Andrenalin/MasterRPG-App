// @copyright André Trettin

import CoreRPG
import Foundation
import Observation
import TableRPG
import SwiftUI
import CharacterRPG
import PhotoRPG
import os.log

// The defender/health sync and the network sections live in
// GameController+BattleSync.swift (CODE_AUDIT_19 §9.23).

extension GameController {
    // MARK: - Combatant lifecycle

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

    /// The domain mutation of a battle start once the combatants are built:
    /// `BattleRoundModel.begin`, auto-resolving the configured initiative/HP
    /// entries, pin sync. The initiative order always comes from the saved
    /// setting, which is its only owner.
    @MainActor
    @discardableResult
    func beginBattle(
        itemId: UUID,
        playerCombatants: [BattleCombatant],
        roomCombatants: [BattleCombatant]
    ) -> Bool {
        guard let map = gameModel.itemData[itemId] as? MapModel else { return false }
        battleRoundModel.begin(
            mapId: itemId,
            players: playerCombatants,
            roomCombatants: roomCombatants,
            initiativeOrder: battleRoundSettings.initiativeOrder
        )
        resolveBattleConfiguredValues()
        _ = battleRoundModel.synchronize(pins: map.mapPins)
        return true
    }

    @MainActor
    func startBattle(itemId: UUID) -> Bool {
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
            roomCombatants: roomCombatants
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
            // Routed through the shared mutate-bump-write-sync helper instead
            // of hand-rolling the timestamp bump.
            guard let updatedPin = mutatedPinState(
                itemId: itemId,
                pinId: pinId,
                mutation: { $0.characterId = copyId }
            ) else {
                return nil
            }
            pin = updatedPin
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
        // Ids are captured before mutating so the loop below never indexes
        // into `map.mapPins` while `updatePinState` is rewriting it in place.
        // Routed through the shared helper instead of hand-rolling the
        // timestamp bump.
        let highlightedPinIds = map.mapPins.filter(\.isHighlighted).map(\.id)
        for pinId in highlightedPinIds {
            updatePinState(itemId: itemId, pinId: pinId) { $0.isHighlighted = false }
        }
    }

    @MainActor
    func endBattle(itemId: UUID) -> Bool {
        guard battleRoundModel.isRunning,
              battleRoundModel.mapId == itemId,
              gameModel.itemData[itemId] is MapModel else {
            return false
        }
        clearBattleHighlights(itemId: itemId)
        battleRoundModel.end()
        return true
    }

    // MARK: - Turn / initiative

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

    /// The one place the initiative order changes. The setting is saved even
    /// when no battle has run yet in this session, so the next battle starts
    /// with it; the model's copy follows so the current turn list re-sorts.
    @MainActor
    @discardableResult
    func setBattleInitiativeOrder(_ order: BattleInitiativeOrder) -> Bool {
        let settingChanged = battleRoundSettings.initiativeOrder != order
        if settingChanged {
            battleRoundSettings.initiativeOrder = order
        }
        let modelChanged = battleRoundModel.setInitiativeOrder(order)
        return settingChanged || modelChanged
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
    /// surprise round is still being prepared. A pin that was highlighted
    /// first is already on the roster as a target; it keeps that combatant
    /// (and its Character copy) and gains its own turn.
    @MainActor
    func addBattleCombatant(itemId: UUID, pinId: UUID) -> Bool {
        guard battleRoundModel.mapId == itemId,
              battleRoundModel.canAddCombatant(pinId: pinId),
              let combatant = battleRoundModel.combatant(pinId: pinId)
                ?? makeBattleCombatant(itemId: itemId, pinId: pinId),
              battleRoundModel.addCombatant(combatant) else {
            return false
        }
        resolveBattleConfiguredValues(for: combatant.id)
        return true
    }

    /// The "Add Pin to Battle Round" action: like `addBattleCombatant`, but in any round of the
    /// running battle, not only while the surprise round is prepared.
    @MainActor
    func joinBattle(itemId: UUID, pinId: UUID) -> Bool {
        guard battleRoundModel.canJoinBattle(pinId: pinId, on: itemId),
              let combatant = battleRoundModel.combatant(pinId: pinId)
                ?? makeBattleCombatant(itemId: itemId, pinId: pinId),
              battleRoundModel.joinCombatant(combatant) else {
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

    // MARK: - Rolls & value entries

    @MainActor
    func addBattleRoll(
        itemId: UUID,
        combatantId: UUID,
        total: Int,
        expression: String?,
        outcome: BattleRollOutcome? = nil
    ) -> Bool {
        guard battleRoundModel.mapId == itemId else { return false }
        return battleRoundModel.addRoll(
            combatantId: combatantId,
            total: total,
            expression: expression,
            outcome: outcome
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
              combatant.isDead != isDead else {
            return false
        }
        return setPinDead(itemId: itemId, pinId: combatant.pinId, isDead: isDead)
    }

    /// The one "mark dead / alive" operation, shared by the battle card
    /// (`setBattleCombatantDead`) and the map and 3D-table pin menus
    /// (`toggleDeadPin`). Outside a battle it only writes the pin's flag. For
    /// a combatant of a running battle it also does the battle bookkeeping,
    /// so the card, the turn skipping and the other attackers' target lists
    /// do not keep the stale state.
    ///
    /// A game-master action: every caller is gated on the master role.
    @MainActor
    func setPinDead(itemId: UUID, pinId: UUID, isDead: Bool) -> Bool {
        guard updatePinState(itemId: itemId, pinId: pinId, mutation: { pin in
            pin.isDead = isDead
        }) else {
            return false
        }
        guard battleRoundModel.isRunning,
              battleRoundModel.mapId == itemId,
              let combatant = battleRoundModel.combatant(pinId: pinId) else {
            return true
        }
        // A dead combatant must drop out of every attacker's target list
        // immediately, not linger highlighted until the next manual toggle.
        // `BattleRoundModel+Turns.swift`'s `synchronize(pins:)` derives each
        // entry's `defenderIds` purely from `pin.isHighlighted`, so clearing
        // the flag here is sufficient to remove it network-wide and to reset
        // any attacker whose `rollRecipientCombatantId` pointed at it.
        if isDead {
            _ = updatePinState(itemId: itemId, pinId: pinId, mutation: { pin in
                pin.isHighlighted = false
            })
            // `synchronize(pins:)` below only updates the active entry; the other
            // attackers' target lists must drop it too. See CODE_AUDIT_19 §5.8.
            battleRoundModel.removeDefender(combatant.id)
        }
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

        if combatant.isPlayer {
            // Player Characters are shared game identities and must not fork
            // into an isolated monster-style runtime copy: the pin's own
            // Character is kept, and a player pin without one takes the
            // chosen Character as it is.
            sourceCharacterId = currentCharacterId ?? characterId
            gameCharacterId = sourceCharacterId
        } else if let currentCharacterId,
                  root.characterRoot.valueGameControllable.battleCharacterCopy(
                      for: currentCharacterId
                  ) != nil {
            // This token already owns a live runtime Character. Treat another
            // selection as a no-op so it cannot advance map state or fork the
            // association while the battle is running.
            return false
        } else {
            // Reached only when the token has no live runtime Character: it
            // has none at all, or the one on its pin could not be copied
            // (deleted, or the copy failed at battle start). Either way the
            // Character the game master just chose is the one to use — going
            // back to the pin's stale id made every assignment fail silently.
            guard let copyId = root.characterRoot.valueGameControllable
                .createBattleCharacterCopy(for: characterId) else {
                return false
            }
            mapGameModel.registerBattleCharacterCopy(copyId)
            sourceCharacterId = characterId
            gameCharacterId = copyId
        }

        // Routed through the shared mutate-bump-write-sync helper instead of
        // hand-rolling the timestamp bump.
        guard let updatedPin = mutatedPinState(
            itemId: itemId,
            pinId: combatant.pinId,
            mutation: { $0.characterId = gameCharacterId }
        ) else {
            return false
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
}
