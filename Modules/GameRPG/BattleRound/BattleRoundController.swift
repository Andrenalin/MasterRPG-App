// @copyright André Trettin

import CharacterRPG
import CoreRPG
import DiceRPG
import Foundation
import MapRPG

/// The single owner of every Battle Round mutation. Views observe
/// `BattleRoundModel` directly for display data (via `controller.model`);
/// this controller is the only thing that manipulates it. It holds `root`
/// directly — the same shape as MapRPG's own `GameController` holding
/// `root: MapRootModel` — so every action is a real method instead of an
/// injected closure.
@MainActor
struct BattleRoundController: Sendable {
    // `unowned`, not strong: this struct is stored on `GameRoot` itself
    // (`GameRoot.battleRoundController`), so a strong `root` here is a
    // self-retain cycle that leaks every `GameRoot` once the battle window
    // is opened. Unlike MasterController/PlayerController's documented
    // strong self-cycle (kept strong because in-flight async tasks
    // outlived `unowned` teardown there), this struct holds no tasks and
    // every method is a synchronous @MainActor call reachable only while
    // `root` is alive — `unowned` breaks the cycle with no optional-chaining
    // ripple through the file. See CODE_AUDIT_Game §5.8.
    unowned let root: GameRoot

    var model: BattleRoundModel {
        root.mapRoot.mapGameControllable.battleRoundModel
    }

    /// The running battle's map id, but only while this device is the game
    /// master — every mutating method below collapses its own
    /// `isMaster`/`mapId` guard to this single computed property so a future
    /// method can't skip the authorization check by omission. See CODE_AUDIT §9.5.
    private var authorizedMapId: UUID? {
        root.gameModel.gameConfig.isMaster ? model.mapId : nil
    }

    // MARK: - Lifecycle

    @discardableResult
    func start() -> Bool {
        guard root.gameModel.gameConfig.isMaster,
              root.gameModel.masterController != nil,
              let mapId = root.mapRoot.gameControllable.gameModel.currentItemId,
              let pins = root.mapRoot.mapGameControllable.battleStartPins(itemId: mapId) else {
            return false
        }

        let playerCombatants = pins.playerPins.map { pin in
            BattleCombatant(
                pin: pin,
                sourceCharacterId: pin.characterId,
                // A player's Character is already the authoritative game
                // identity. Never clone it merely because a battle starts.
                gameCharacterId: pin.characterId,
                isPlayer: true
            )
        }
        let roomCombatants = pins.roomPins.compactMap { pin in
            root.mapRoot.mapGameControllable.makeBattleCombatant(itemId: mapId, pinId: pin.id)
        }

        root.mapRoot.mapGameControllable.clearBattleHighlights(itemId: mapId)
        guard root.mapRoot.mapGameControllable.beginBattle(
            itemId: mapId,
            playerCombatants: playerCombatants,
            roomCombatants: roomCombatants,
            initiativeOrder: model.initiativeOrder
        ) else {
            return false
        }
        broadcast(mapId: mapId)
        return true
    }

    @discardableResult
    func end() -> Bool {
        guard let mapId = authorizedMapId,
              root.mapRoot.mapGameControllable.endBattle(itemId: mapId) else {
            return false
        }
        broadcast(mapId: mapId)
        return true
    }

    // MARK: - Initiative

    @discardableResult
    func setInitiative(_ combatantId: UUID, _ value: Int?) -> Bool {
        guard let mapId = authorizedMapId else {
            return false
        }
        return root.mapRoot.mapGameControllable.setBattleInitiative(
            itemId: mapId,
            combatantId: combatantId,
            value: value
        )
    }

    @discardableResult
    func adjustInitiative(_ combatantId: UUID, _ amount: Int) -> Bool {
        guard let mapId = authorizedMapId else {
            return false
        }
        return root.mapRoot.mapGameControllable.adjustBattleInitiative(
            itemId: mapId,
            combatantId: combatantId,
            amount: amount
        )
    }

    // MARK: - Hit points

    /// The combatant's current hit points, read from its Character's chosen
    /// Hit Points entry.
    func hitPoints(for combatant: BattleCombatant) -> Int? {
        guard let characterId = combatant.gameCharacterId,
              let entryId = combatant.hitPointsEntryId else {
            return nil
        }
        return root.characterRoot.valueGameControllable.gameEntryCurrentNumber(
            characterId: characterId,
            entryId: entryId
        )
    }

    /// Writes the current hit points into the combatant's Character for this
    /// game (a monster's battle copy, or the player's Character) and
    /// broadcasts the resulting health.
    @discardableResult
    func setHitPoints(_ combatantId: UUID, _ value: Int) -> Bool {
        guard let mapId = authorizedMapId,
              let combatant = model.combatant(id: combatantId),
              let characterId = combatant.gameCharacterId,
              let entryId = combatant.hitPointsEntryId,
              root.characterRoot.valueGameControllable.setGameEntryCurrentNumber(
                  value,
                  characterId: characterId,
                  entryId: entryId
              ) else {
            return false
        }
        broadcast(mapId: mapId)
        return true
    }

    @discardableResult
    func adjustHitPoints(_ combatantId: UUID, _ amount: Int) -> Bool {
        guard let combatant = model.combatant(id: combatantId),
              let current = hitPoints(for: combatant) else {
            return false
        }
        return setHitPoints(combatantId, current + amount)
    }

    @discardableResult
    func setInitiativeOrder(_ order: BattleInitiativeOrder) -> Bool {
        guard let mapId = authorizedMapId else {
            return false
        }
        return root.mapRoot.mapGameControllable.setBattleInitiativeOrder(
            itemId: mapId,
            order: order
        )
    }

    func moveEntries(_ source: IndexSet, _ destination: Int) {
        guard authorizedMapId != nil else { return }
        root.mapRoot.mapGameControllable.moveBattleEntries(from: source, to: destination)
    }

    // MARK: - Turn progression

    @discardableResult
    func activateAttacker(_ combatantId: UUID) -> Bool {
        guard let mapId = authorizedMapId,
              root.mapRoot.mapGameControllable.activateBattleAttacker(
                  itemId: mapId,
                  combatantId: combatantId
              ) else {
            return false
        }
        broadcast(mapId: mapId)
        return true
    }

    @discardableResult
    func nextAttacker() -> Bool {
        guard let mapId = authorizedMapId,
              root.mapRoot.mapGameControllable.nextBattleAttacker(itemId: mapId) else {
            return false
        }
        broadcast(mapId: mapId)
        return true
    }

    @discardableResult
    func nextRound() -> Bool {
        guard let mapId = authorizedMapId,
              root.mapRoot.mapGameControllable.nextBattleRound(itemId: mapId) else {
            return false
        }
        broadcast(mapId: mapId)
        return true
    }

    // MARK: - Combatant mutation

    @discardableResult
    func addCombatant(pinId: UUID) -> Bool {
        guard let mapId = authorizedMapId,
              root.mapRoot.mapGameControllable.addBattleCombatant(
                  itemId: mapId,
                  pinId: pinId
              ) else {
            return false
        }
        broadcast(mapId: mapId)
        return true
    }

    /// Removes a combatant from the battle entirely. The map pin is left
    /// alone, so highlighting it again re-adds it as a fresh combatant.
    @discardableResult
    func removeCombatant(_ combatantId: UUID) -> Bool {
        guard let mapId = authorizedMapId,
              root.mapRoot.mapGameControllable.removeBattleCombatant(
                  itemId: mapId,
                  combatantId: combatantId
              ) else {
            return false
        }
        broadcast(mapId: mapId)
        return true
    }

    // MARK: - Rolls

    @discardableResult
    func addRoll(
        combatantId: UUID,
        total: Int,
        expression: String? = nil,
        outcome: BattleRollOutcome? = nil
    ) -> Bool {
        guard let mapId = authorizedMapId else {
            return false
        }
        return root.mapRoot.mapGameControllable.addBattleRoll(
            itemId: mapId,
            combatantId: combatantId,
            total: total,
            expression: expression,
            outcome: outcome
        )
    }

    @discardableResult
    func selectRollRecipient(_ combatantId: UUID) -> Bool {
        guard let mapId = authorizedMapId else {
            return false
        }
        return root.mapRoot.mapGameControllable.selectBattleRollRecipient(
            itemId: mapId,
            combatantId: combatantId
        )
    }

    // MARK: - Combatant mutation

    @discardableResult
    func setDead(_ combatantId: UUID, _ isDead: Bool) -> Bool {
        guard let mapId = authorizedMapId,
              root.mapRoot.mapGameControllable.setBattleCombatantDead(
                  itemId: mapId,
                  combatantId: combatantId,
                  isDead: isDead
              ) else {
            return false
        }
        broadcast(mapId: mapId)
        return true
    }

    @discardableResult
    func assignCharacter(_ combatantId: UUID, _ characterId: UUID) -> Bool {
        guard let mapId = authorizedMapId,
              root.mapRoot.mapGameControllable.assignBattleCharacter(
                  itemId: mapId,
                  combatantId: combatantId,
                  characterId: characterId
              ) else {
            return false
        }
        broadcast(mapId: mapId)
        return true
    }

    /// Associates a normal game dice message with the matching battle photo.
    /// Character-linked dice are exact, player rolls fall back to the
    /// sender's pin, and an unlinked master roll uses the selected
    /// non-player target.
    func recordDiceResult(
        _ diceResult: DiceResultModel,
        senderId: UUID,
        isMaster: Bool
    ) {
        guard model.isRunning else { return }
        let eligible = model.rollEligibleCombatants
        let characterId = diceResult.diceModel.resultCategory.flatMap { category in
            category.module == .value ? category.id : nil
        }
        let characterCombatant = characterId.flatMap { characterId in
            eligible.first { $0.gameCharacterId == characterId }
                ?? eligible.first { $0.sourceCharacterId == characterId }
        }
        let playerCombatant = eligible.first { combatant in
            combatant.isPlayer
                && (combatant.pinId == senderId
                    || combatant.pin.players.contains(senderId))
        }
        // `resultCategory` travels inside the network payload, set entirely
        // client-side by whoever initiated the roll — the transport layer
        // authenticates `senderId` itself, but never cross-checks this field
        // against it. Without this guard, a player could claim any other
        // combatant's `gameCharacterId`/`sourceCharacterId` (values every
        // player already sees over the wire) and have the roll attributed to
        // a combatant they don't own. The master's own local rolls are
        // already an authenticated identity by the time `isMaster` is true
        // here, so only a non-master sender needs the ownership check.
        // See CODE_AUDIT §6.1.
        let authorizedCharacterCombatant = characterCombatant.flatMap { combatant -> BattleCombatant? in
            guard isMaster
                    || (combatant.isPlayer
                        && (combatant.pinId == senderId
                            || combatant.pin.players.contains(senderId)))
            else { return nil }
            return combatant
        }
        let combatantId = authorizedCharacterCombatant?.id
            ?? (isMaster ? model.masterRollRecipientCombatantId : playerCombatant?.id)
        guard let combatantId else { return }
        _ = addRoll(
            combatantId: combatantId,
            total: diceResult.sum,
            expression: diceResult.values,
            outcome: Self.battleOutcome(of: diceResult)
        )
    }

    /// The dice module's coup is the battle's critical.
    static func battleOutcome(of diceResult: DiceResultModel) -> BattleRollOutcome? {
        switch diceResult.result {
        case .coup: .critical
        case .fumble: .fumble
        case .rolled, .notRolled: nil
        }
    }

    // MARK: - Value-entry assignment

    /// Maps a dropped/picked value entry onto a combatant's initiative or
    /// hit-points slot. Broadcasts on an actual change (previously did not —
    /// see CODE_AUDIT_Game §5.4 — a `.hitPoints` assignment changes what
    /// `healthPercent(for:)` computes just as much as any other mutator here).
    @discardableResult
    func assignValueEntry(
        combatantId: UUID,
        sourceCharacterId: UUID,
        sourceEntryId: UUID,
        kind: BattleValueKind
    ) -> Bool {
        // authorizedMapId, not model.mapId — this mutates and (below)
        // broadcasts state; broadcast(mapId:) assumes its caller already
        // enforced the master-only invariant. See CODE_AUDIT_Game §5.4.
        guard let mapId = authorizedMapId,
              let combatant = model.combatant(id: combatantId),
              // `sourceCharacterId`/`sourceEntryId` are whatever was
              // dropped/picked, which may sit inside a nested value "group"
              // table (ValueModel.groupId) rather than directly on the
              // top-level Character. Resolve the full root-to-leaf path so
              // it can be replayed against the combatant's own battle copy.
              let path = root.characterRoot.valueGameControllable.gameEntryPath(
                  itemId: sourceCharacterId,
                  entryId: sourceEntryId
              ),
              path.rootCharacterId == combatant.sourceCharacterId,
              let gameCharacterId = combatant.gameCharacterId,
              // The battle copy's own top-level entries always get fresh ids
              // (see `ValueEntryModel.duplicate()`), so the equivalent entry
              // on the combatant's own runtime copy must be re-found by
              // replaying the same index path, verified by name at the end.
              let gameEntry = root.characterRoot.valueGameControllable.gameEntry(
                  matching: path,
                  characterId: gameCharacterId
              ) else {
            return false
        }

        let mappingChanged = root.mapRoot.mapGameControllable.setBattleValueEntry(
            itemId: mapId,
            combatantId: combatantId,
            entryId: gameEntry.id,
            kind: kind
        )
        var initiativeChanged = false
        if kind == .initiative,
           let value = root.characterRoot.valueGameControllable.gameEntryDisplayValue(
               characterId: gameCharacterId,
               entryId: gameEntry.id
           ),
           let initiative = root.mapRoot.mapGameControllable.battleInitiative(from: value) {
            initiativeChanged = setInitiative(combatantId, initiative)
        }
        let changed = mappingChanged || initiativeChanged
        // Unlike its doc comment's "never leaves the device" claim (true only
        // for the map-level mutation itself), the health-affecting case
        // (.hitPoints) needs the same broadcast every other battle mutator
        // does — otherwise players and the 2D map keep a stale health ring
        // until unrelated traffic happens to broadcast. See CODE_AUDIT_Game §5.4.
        if changed {
            broadcast(mapId: mapId)
        }
        return changed
    }

    func refreshConfiguredValues() {
        guard let mapId = authorizedMapId else { return }
        root.mapRoot.mapGameControllable.refreshBattleConfiguredValues(itemId: mapId)
        broadcast(mapId: mapId)
    }

    // MARK: - Broadcast

    /// Recomputes every combatant's `pin.healthPercent` from its linked
    /// hit-points entry before broadcasting — mirrors `RootGameMapViewer`'s
    /// own `sendMapUpdates()`, which does the same before its own mapState
    /// push. Without this, `nextAttacker()`/`nextRound()` (and every other
    /// action routed through this method) only ever updated highlights, so
    /// a defender's health ring stayed stale — correct only on the master's
    /// own 3D screen, which reads a live combatant lookup independent of
    /// this persisted field, but wrong for players and for the 2D map,
    /// which both only ever see `pin.healthPercent` as last broadcast.
    private func broadcast(mapId: UUID) {
        // Every public entry point above already guards on
        // `root.gameModel.gameConfig.isMaster` before reaching here.
        _ = root.mapRoot.mapGameControllable.synchronizeBattleDefenders(itemId: mapId, isGameMaster: true)
        #if !os(tvOS)
        root.gameModel.gameTableModel?.syncPawnsWithMapPins()
        #endif
        // While the GM paused "Share Map", the map state (room visibility, focus, pins) stays
        // private; only the battle round goes out. Resuming sends the state. See CODE_AUDIT_19 §5.7.
        if root.mapRoot.rootModel.isMapStreaming {
            root.networkActions.game(
                root.mapRoot.mapGameControllable.networkMapUpdate(for: mapId),
                .mapState,
                nil
            )
        }
        if let battleUpdate = root.mapRoot.mapGameControllable.networkBattleRoundUpdate(for: mapId) {
            root.networkActions.game(battleUpdate, .battleRound, nil)
        }
    }
}

extension BattleRoundController {
    /// `GameRoot.previewFixture()` already installs a running battle (via
    /// MapRPG's `BattleRoundPreviewData.apply(to:)`) and a master
    /// `MasterController`, so the returned controller's actions work in a
    /// live Xcode preview canvas, not just for static rendering.
    static func preview() -> BattleRoundController {
        GameRoot.previewFixture().battleRoundController
    }
}
