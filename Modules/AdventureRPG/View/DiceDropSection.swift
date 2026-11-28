// @copyright André Trettin

import CoreRPG
import DiceRPG
import SwiftUI

/// The shared `DiceDropSelectionEditor`. See CODE_AUDIT_Edit_Save §9.6.
struct DiceDropSection: View {
    let root: AdventureRootModel
    let model: AdventureModel

    var body: some View {
        let editController = root.editController
        let itemId = model.id
        DiceDropSelectionEditor(diceRoot: root.diceRoot, selection: editController.adventureEditModel.selectionDice, diceId: model.diceId) { diceId in
            // The editor persists also during a game.
            editController.add(diceId: diceId, itemId: itemId, forceSave: true)
        }
    }
}

#Preview(traits: .mockData) {
    DiceDropSection(root: .preview, model: .preview)
}
