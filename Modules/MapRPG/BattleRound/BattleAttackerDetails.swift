// @copyright André Trettin

import SwiftUI

struct BattleAttackerDetails: View {
    let combatant: BattleCombatant
    let isActive: Bool
    let actions: BattleRoundActions

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text(combatant.name)
                    .font(.headline)
                    .lineLimit(1)

                if combatant.isPlayer {
                    Image(systemName: "person.fill")
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(Text("Player", bundle: .module))
                }
                if combatant.isDead {
                    Image(systemName: "skull.fill")
                        .foregroundStyle(.red)
                        .accessibilityLabel(Text("Dead", bundle: .module))
                }
                if isActive {
                    Image(systemName: "scope")
                        .foregroundStyle(.blue)
                        .accessibilityLabel(Text("Highlighted", bundle: .module))
                }
            }

            BattleInitiativeEditor(
                combatantId: combatant.id,
                value: combatant.initiative,
                setValue: actions.setInitiative,
                adjust: actions.adjustInitiative
            )

            Button(
                isActive ? "Active Attacker" : "Make Active",
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
        actions.activateAttacker(combatant.id)
    }
}

#Preview("Active attacker") {
    let model = BattleRoundPreviewData.model()

    if let card = model.cardPresentations.first {
        BattleAttackerDetails(
            combatant: card.attacker.combatant,
            isActive: card.isActive,
            actions: .preview(model: model)
        )
        .padding()
    }
}
