// @copyright André Trettin

import MapRPG
import CoreRPG
import SwiftUI

struct BattleRoundWindowView: View {
    let root: GameRoot

    @Environment(ScenesManager.self) private var scenesManager

    var body: some View {
        if root.gameModel.gameConfig.isMaster {
            BattleRoundView(
                model: root.battleRoundModel,
                actions: BattleRoundActionFactory.actions(
                    for: root
                ) {
                    scenesManager.dismissWindow(.battleRound)
                }
            )
            .environment(root.mapRoot)
        } else {
            ContentUnavailableView {
                Label {
                    Text("Game Master Only", bundle: .module)
                } icon: {
                    Image(systemName: "lock.fill")
                }
            } description: {
                Text("Only the game master can manage battle rounds.", bundle: .module)
            }
        }
    }
}

@MainActor
enum BattleRoundActionFactory {
    static func actions(
        for root: GameRoot,
        dismiss: @escaping @MainActor () -> Void
    ) -> BattleRoundActions {
        BattleRoundActions(
            start: {
                guard let mapId = root.mapRoot.gameControllable.gameModel.currentItemId else { return }
                _ = root.startBattleRound(
                    mapId: mapId,
                    initiativeOrder: root.battleRoundModel.initiativeOrder
                )
            },
            end: {
                guard root.endBattleRound() else { return }
                dismiss()
            },
            nextAttacker: {
                _ = root.nextBattleAttacker()
            },
            nextRound: {
                _ = root.nextBattleRound()
            },
            setInitiative: { combatantId, value in
                _ = root.setBattleInitiative(combatantId: combatantId, value: value)
            },
            adjustInitiative: { combatantId, amount in
                _ = root.adjustBattleInitiative(combatantId: combatantId, amount: amount)
            },
            setInitiativeOrder: { order in
                _ = root.setBattleInitiativeOrder(order)
            },
            moveEntries: { source, destination in
                root.moveBattleEntries(from: source, to: destination)
            },
            activateAttacker: { combatantId in
                _ = root.activateBattleAttacker(combatantId)
            },
            selectRollRecipient: { combatantId in
                _ = root.selectBattleRollRecipient(combatantId)
            },
            setDead: { combatantId, isDead in
                _ = root.setBattleCombatantDead(combatantId, isDead: isDead)
            },
            assignCharacter: { combatantId, characterId in
                _ = root.assignBattleCharacter(
                    combatantId: combatantId,
                    characterId: characterId
                )
            }
        )
    }
}
