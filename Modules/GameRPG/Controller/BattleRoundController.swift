// @copyright André Trettin

import CoreRPG
import DiceRPG
import Foundation
import MapRPG

@MainActor
extension GameRoot {
    var battleRoundModel: BattleRoundModel {
        mapRoot.mapGameControllable.battleRoundModel
    }

    @discardableResult
    func startBattleRound(
        mapId: UUID,
        initiativeOrder: BattleInitiativeOrder = .descending
    ) -> Bool {
        guard gameModel.gameConfig.isMaster,
              gameModel.masterController != nil,
              mapRoot.mapGameControllable.startBattle(
                  itemId: mapId,
                  initiativeOrder: initiativeOrder
              ) else {
            return false
        }
        broadcastBattleRound(mapId: mapId, includeMapState: true)
        return true
    }

    @discardableResult
    func endBattleRound() -> Bool {
        guard gameModel.gameConfig.isMaster,
              let mapId = battleRoundModel.mapId,
              mapRoot.mapGameControllable.endBattle(itemId: mapId) else {
            return false
        }
        broadcastBattleRound(mapId: mapId, includeMapState: true)
        return true
    }

    @discardableResult
    func setBattleInitiative(combatantId: UUID, value: Int?) -> Bool {
        guard gameModel.gameConfig.isMaster,
              let mapId = battleRoundModel.mapId else {
            return false
        }
        return mapRoot.mapGameControllable.setBattleInitiative(
            itemId: mapId,
            combatantId: combatantId,
            value: value
        )
    }

    @discardableResult
    func adjustBattleInitiative(combatantId: UUID, amount: Int) -> Bool {
        guard gameModel.gameConfig.isMaster,
              let mapId = battleRoundModel.mapId else {
            return false
        }
        return mapRoot.mapGameControllable.adjustBattleInitiative(
            itemId: mapId,
            combatantId: combatantId,
            amount: amount
        )
    }

    @discardableResult
    func setBattleInitiativeOrder(_ order: BattleInitiativeOrder) -> Bool {
        guard gameModel.gameConfig.isMaster,
              let mapId = battleRoundModel.mapId else {
            return false
        }
        return mapRoot.mapGameControllable.setBattleInitiativeOrder(
            itemId: mapId,
            order: order
        )
    }

    func moveBattleEntries(from source: IndexSet, to destination: Int) {
        guard gameModel.gameConfig.isMaster else { return }
        mapRoot.mapGameControllable.moveBattleEntries(from: source, to: destination)
    }

    @discardableResult
    func activateBattleAttacker(_ combatantId: UUID) -> Bool {
        guard gameModel.gameConfig.isMaster,
              let mapId = battleRoundModel.mapId,
              mapRoot.mapGameControllable.activateBattleAttacker(
                  itemId: mapId,
                  combatantId: combatantId
              ) else {
            return false
        }
        broadcastBattleRound(mapId: mapId, includeMapState: true)
        return true
    }

    @discardableResult
    func nextBattleAttacker() -> Bool {
        guard gameModel.gameConfig.isMaster,
              let mapId = battleRoundModel.mapId,
              mapRoot.mapGameControllable.nextBattleAttacker(itemId: mapId) else {
            return false
        }
        broadcastBattleRound(mapId: mapId, includeMapState: true)
        return true
    }

    @discardableResult
    func nextBattleRound() -> Bool {
        guard gameModel.gameConfig.isMaster,
              let mapId = battleRoundModel.mapId,
              mapRoot.mapGameControllable.nextBattleRound(itemId: mapId) else {
            return false
        }
        broadcastBattleRound(mapId: mapId, includeMapState: true)
        return true
    }

    @discardableResult
    func addBattleCombatant(pinId: UUID) -> Bool {
        guard gameModel.gameConfig.isMaster,
              let mapId = battleRoundModel.mapId,
              mapRoot.mapGameControllable.addBattleCombatant(
                  itemId: mapId,
                  pinId: pinId
              ) else {
            return false
        }
        broadcastBattleRound(mapId: mapId, includeMapState: true)
        return true
    }

    @discardableResult
    func addBattleRoll(
        combatantId: UUID,
        total: Int,
        expression: String? = nil
    ) -> Bool {
        guard gameModel.gameConfig.isMaster,
              let mapId = battleRoundModel.mapId else {
            return false
        }
        return mapRoot.mapGameControllable.addBattleRoll(
            itemId: mapId,
            combatantId: combatantId,
            total: total,
            expression: expression
        )
    }

    @discardableResult
    func selectBattleRollRecipient(_ combatantId: UUID) -> Bool {
        guard gameModel.gameConfig.isMaster,
              let mapId = battleRoundModel.mapId else {
            return false
        }
        return mapRoot.mapGameControllable.selectBattleRollRecipient(
            itemId: mapId,
            combatantId: combatantId
        )
    }

    @discardableResult
    func setBattleCombatantDead(_ combatantId: UUID, isDead: Bool) -> Bool {
        guard gameModel.gameConfig.isMaster,
              let mapId = battleRoundModel.mapId,
              mapRoot.mapGameControllable.setBattleCombatantDead(
                  itemId: mapId,
                  combatantId: combatantId,
                  isDead: isDead
              ) else {
            return false
        }
        broadcastBattleRound(mapId: mapId, includeMapState: true)
        return true
    }

    @discardableResult
    func assignBattleCharacter(combatantId: UUID, characterId: UUID) -> Bool {
        guard gameModel.gameConfig.isMaster,
              let mapId = battleRoundModel.mapId,
              mapRoot.mapGameControllable.assignBattleCharacter(
                  itemId: mapId,
                  combatantId: combatantId,
                  characterId: characterId
              ) else {
            return false
        }
        broadcastBattleRound(mapId: mapId, includeMapState: true)
        return true
    }

    /// Associates a normal game dice message with the matching battle photo.
    /// Character-linked dice are exact, player rolls fall back to the sender's
    /// pin, and an unlinked master roll uses the selected non-player target.
    func recordBattleDiceResult(
        _ diceResult: DiceResultModel,
        senderId: UUID,
        isMaster: Bool
    ) {
        guard battleRoundModel.isRunning else { return }
        let eligible = battleRoundModel.rollEligibleCombatants
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
        let combatantId = characterCombatant?.id
            ?? (isMaster ? battleRoundModel.masterRollRecipientCombatantId : playerCombatant?.id)
        guard let combatantId else { return }
        _ = addBattleRoll(
            combatantId: combatantId,
            total: diceResult.sum,
            expression: diceResult.values
        )
    }

    private func broadcastBattleRound(mapId: UUID, includeMapState: Bool) {
        #if !os(tvOS)
        gameModel.gameTableModel?.syncPawnsWithMapPins()
        #endif
        if includeMapState {
            networkActions.game(
                mapRoot.mapGameControllable.networkMapUpdate(for: mapId),
                .mapState,
                nil
            )
        }
        if let battleUpdate = mapRoot.mapGameControllable.networkBattleRoundUpdate(for: mapId) {
            networkActions.game(battleUpdate, .battleRound, nil)
        }
    }
}
