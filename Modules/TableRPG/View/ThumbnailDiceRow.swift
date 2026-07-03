// @copyright André Trettin

import CoreRPG
import DiceRPG
import SwiftUI

struct ThumbnailDiceRow: View, Equatable {
    let itemId: UUID
    var item: TableModel? = nil

    @Environment(TableRootModel.self) private var root

    var body: some View {
        if let diceId = model.diceId {
            root.diceRoot.viewController.thumbnailRowView(for: diceId)
                .padding(.trailing, 20)
        }
    }

    private var model: TableModel {
        item ?? root.itemController.itemOrEmpty(for: itemId)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.itemId == rhs.itemId && lhs.item == rhs.item
    }
}

#Preview(traits: .mockData) {
    ThumbnailDiceRow(itemId: MockData.previewId)
}
