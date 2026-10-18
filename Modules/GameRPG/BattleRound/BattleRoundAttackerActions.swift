// @copyright André Trettin

import MapRPG
import SwiftUI

/// The attacker's actions, placed directly at the root of the battle round
/// card's context menu.
struct BattleRoundAttackerActions: View {
    let presentation: BattleRoundParticipantPresentation
    let cardState: BattleRoundCardState
    let controller: BattleRoundController
    let screenModel: BattleRoundScreenModel

    var body: some View {
        let deadToggle = BattleDeadToggle(isDead: combatant.isDead)

        Button {
            cardState.openCharacter(combatant, controller: controller, screenModel: screenModel)
        } label: {
            Label {
                Text(
                    combatant.hasCharacter ? "Open Character Sheet" : "Choose a Character",
                    bundle: .module
                )
            } icon: {
                Image(systemName: combatant.hasCharacter ? "person.text.rectangle" : "person.badge.plus")
            }
        }

        Button {
            screenModel.selectHitPoints(combatant)
        } label: {
            Label {
                Text("Choose the Hit Points value", bundle: .module)
            } icon: {
                Image(systemName: "heart.text.square")
            }
        }

        Button {
            controller.adjustInitiative(combatant.id, 1)
        } label: {
            Label {
                Text("Increase Initiative", bundle: .module)
            } icon: {
                Image(systemName: "plus")
            }
        }

        Button {
            controller.adjustInitiative(combatant.id, -1)
        } label: {
            Label {
                Text("Decrease Initiative", bundle: .module)
            } icon: {
                Image(systemName: "minus")
            }
        }

        if canMakeActive {
            Button {
                controller.activateAttacker(combatant.id)
            } label: {
                Label {
                    Text("Make Active", bundle: .module)
                } icon: {
                    Image(systemName: "scope")
                }
            }
        }

        Button(deadToggle.title, systemImage: deadToggle.systemImage, role: deadToggle.role) {
            controller.setDead(combatant.id, !combatant.isDead)
        }

        // Room combatants only: a player's token comes back automatically
        // whenever the next battle starts, not by re-highlighting a pin.
        if !combatant.isPlayer {
            Divider()

            Button(role: .destructive) {
                controller.removeCombatant(combatant.id)
            } label: {
                Label {
                    Text("Remove from Battle", bundle: .module)
                } icon: {
                    Image(systemName: "trash")
                }
            }
        }
    }

    private var combatant: BattleCombatant { presentation.combatant }

    private var canMakeActive: Bool {
        !combatant.isDead && controller.model.activeEntry?.attackerId != combatant.id
    }
}
