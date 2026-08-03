// @copyright André Trettin

import MapRPG
import SwiftUI

enum BattleRoundParticipantRole {
    case attacker
    case defender
}

/// One participant's full action set, shown as a submenu inside the battle
/// round row's context menu. A card always has exactly one attacker but may
/// have any number of defenders, so `BattleRoundCard` repeats this per
/// defender rather than hard-coding a fixed set of menu entries.
struct BattleRoundParticipantActionsMenu: View {
    let role: BattleRoundParticipantRole
    let presentation: BattleRoundParticipantPresentation
    let cardState: BattleRoundCardState
    let controller: BattleRoundController
    let showCharacter: @MainActor (BattleCombatant) -> Void
    let selectHitPoints: @MainActor (BattleCombatant) -> Void

    var body: some View {
        Menu {
            Button {
                cardState.openCharacter(combatant, controller: controller, showCharacter: showCharacter)
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
                selectHitPoints(combatant)
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

            if presentation.canReceiveRoll {
                Button {
                    controller.selectRollRecipient(combatant.id)
                } label: {
                    Label {
                        Text("Roll Target", bundle: .module)
                    } icon: {
                        Image(systemName: presentation.isRollRecipient ? "dice.fill" : "dice")
                    }
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

            Button(role: combatant.isDead ? nil : .destructive) {
                controller.setDead(combatant.id, !combatant.isDead)
            } label: {
                Label {
                    Text(combatant.isDead ? "Mark Alive" : "Mark Dead", bundle: .module)
                } icon: {
                    Image(systemName: combatant.isDead ? "heart.fill" : "skull.fill")
                }
            }
        } label: {
            Label {
                title
            } icon: {
                Image(systemName: combatant.isPlayer ? "person.fill" : "pawprint.fill")
            }
        }
    }

    private var combatant: BattleCombatant { presentation.combatant }

    private var canMakeActive: Bool {
        !combatant.isDead && controller.model.activeEntry?.attackerId != combatant.id
    }

    private var title: Text {
        switch role {
        case .attacker: Text("Attacker: \(combatant.name)", bundle: .module)
        case .defender: Text("Defender: \(combatant.name)", bundle: .module)
        }
    }
}
