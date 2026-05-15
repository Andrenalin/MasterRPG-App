// @copyright André Trettin

import CoreRPG
import SwiftData
import SwiftUI

struct ThumbnailDiceRow: View, Equatable {
    let itemId: UUID
    
    @Environment(DiceRootModel.self) private var root
    
    var body: some View {
        if let die = model?.dice.first {
            ThumbnailDice(die: die, listDisplayModel: root.listDisplayModel)
        }
    }
    
    private var model: DiceModel? {
        root.itemController.itemSync(for: itemId)
    }
    
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.itemId == rhs.itemId
    }
}

#Preview(traits: .mockData) {
    @Previewable @Environment(DiceRootModel.self) var root

    ThumbnailDiceRow(itemId: root.itemController.itemDataModel.items[0])
    ThumbnailDiceRow(itemId: root.itemController.itemDataModel.items[1])
}
