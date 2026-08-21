// @copyright André Trettin

import CoreRPG
import SwiftUI

struct ThumbnailDiceRow: View, Equatable {
    let itemId: UUID
    var item: DiceModel? = nil

    @Environment(DiceRootModel.self) private var root

    var body: some View {
        if let die = model?.dice.first {
            ThumbnailDice(die: die)
        }
    }

    private var model: DiceModel? {
        item ?? root.itemController.itemSync(for: itemId)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.itemId == rhs.itemId && lhs.item == rhs.item
    }
}

#Preview(traits: .mockData) {
    @Previewable @Environment(DiceRootModel.self) var root

    ThumbnailDiceRow(itemId: root.itemController.itemDataModel.items[0])
    ThumbnailDiceRow(itemId: root.itemController.itemDataModel.items[1])
}
