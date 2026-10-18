// @copyright André Trettin

import MapRPG
import SwiftUI

/// The "make this combatant the attacker" action of a battle card. The label
/// style comes from the environment; the card shows only the icon.
struct BattleActivateAttackerButton: View {
    let combatant: BattleCombatant
    let isActive: Bool
    let controller: BattleRoundController

    var body: some View {
        Button(title, systemImage: "scope", action: activateAttacker)
            .buttonStyle(.borderless)
            .controlSize(.small)
            .disabled(isActive || combatant.isDead)
            .help(Text(title))
    }

    private var title: String {
        isActive
            ? String(localized: "Attacker", bundle: .module)
            : String(localized: "Activate", bundle: .module)
    }

    private func activateAttacker() {
        controller.activateAttacker(combatant.id)
    }
}

extension BattleActivateAttackerButton: Equatable {
    /// Lets `.equatable()` at its call sites skip re-diffing this leaf when
    /// an unrelated part of the same card changes.
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.combatant == rhs.combatant
            && lhs.isActive == rhs.isActive
            && lhs.controller.root === rhs.controller.root
    }
}

#Preview("Activate attacker") {
    let controller = BattleRoundController.preview()
    let model = controller.model

    if let card = model.cardPresentations.last {
        VStack {
            BattleActivateAttackerButton(
                combatant: card.attacker.combatant,
                isActive: card.isActive,
                controller: controller
            )
            BattleActivateAttackerButton(
                combatant: card.attacker.combatant,
                isActive: card.isActive,
                controller: controller
            )
            .labelStyle(.iconOnly)
        }
        .padding()
    }
}
