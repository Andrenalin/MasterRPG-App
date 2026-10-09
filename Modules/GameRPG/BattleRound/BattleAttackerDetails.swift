// @copyright André Trettin

import MapRPG
import SwiftUI

struct BattleAttackerDetails: View {
    let combatant: BattleCombatant
    let isActive: Bool
    let controller: BattleRoundController

    var body: some View {
        VStack(alignment: .leading, spacing: BattleRoundSpacing.compact) {
            BattleAttackerStatusIcons(combatant: combatant)
            BattleActivateAttackerButton(
                combatant: combatant,
                isActive: isActive,
                controller: controller
            )
        }
        .frame(minWidth: 128, alignment: .leading)
        .padding(.top, 4)
    }
}

extension BattleAttackerDetails: Equatable {
    /// Lets `.equatable()` at its call sites skip re-diffing this leaf when
    /// an unrelated part of the same card changes. See CODE_AUDIT §7.2.
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.combatant == rhs.combatant
            && lhs.isActive == rhs.isActive
            && lhs.controller.root === rhs.controller.root
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
