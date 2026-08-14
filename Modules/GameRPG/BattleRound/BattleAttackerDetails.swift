// @copyright André Trettin

import MapRPG
import SwiftUI

struct BattleAttackerDetails: View {
    let combatant: BattleCombatant
    let isActive: Bool
    let controller: BattleRoundController

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                if combatant.isPlayer {
                    Image(systemName: "person.fill")
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(Text("Player", bundle: .module))
                }
                if combatant.isDead {
                    Image(systemName: "person.slash")
                        .foregroundStyle(.red)
                        .accessibilityLabel(Text("Dead", bundle: .module))
                }
                if isActive {
                    Image(systemName: "scope")
                        .foregroundStyle(.blue)
                        .accessibilityLabel(Text("Highlighted", bundle: .module))
                }
            }

            Button(
                isActive ? "Attacker" : "Activate",
                systemImage: "scope",
                action: activateAttacker
            )
            .buttonStyle(.borderless)
            .controlSize(.small)
            .disabled(isActive || combatant.isDead)
        }
        .frame(minWidth: 128, alignment: .leading)
        .padding(.top, 4)
    }

    private func activateAttacker() {
        controller.activateAttacker(combatant.id)
    }
}

#Preview("Active attacker") {
    let controller = BattleRoundController.preview()
    let model = controller.model

    if let card = model.cardPresentations.first {
        BattleAttackerDetails(
            combatant: card.attacker.combatant,
            isActive: card.isActive,
            controller: controller
        )
        .padding()
    }
}
