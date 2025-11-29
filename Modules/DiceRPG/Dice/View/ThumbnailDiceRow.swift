// @copyright André Trettin

import CoreRPG
import SwiftData
import SwiftUI

struct ThumbnailDiceRow: View {
    let itemId: UUID
    
    @Environment(DiceRootModel.self) private var root
    
    var body: some View {
        let _ = Self._printChanges()
        if let die = model?.dice.first {
            ThumbnailDice(die: die)
        }
    }
    
    private var model: DiceModel? {
        root.itemController.itemSync(for: itemId)
    }
}

#Preview(traits: .mockData) {
    @Previewable @Environment(DiceRootModel.self) var root

    ThumbnailDiceRow(itemId: root.itemController.itemDataModel.items[0])
    ThumbnailDiceRow(itemId: root.itemController.itemDataModel.items[1])
}
