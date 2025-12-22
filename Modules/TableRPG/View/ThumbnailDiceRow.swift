// @copyright André Trettin

import CoreRPG
import DiceRPG
import SwiftUI

struct ThumbnailDiceRow: View, Equatable {
    let itemId: UUID
    
    @Environment(TableRootModel.self) private var root
    
    var body: some View {
        let _ = Self._printChanges()
        if let diceId = model.diceId {
            root.diceRoot.viewController.thumbnailRowView(for: diceId)
        }
    }
    
    private var model: TableModel {
        root.itemController.itemOrEmpty(for: itemId)
    }
    
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.itemId == rhs.itemId
    }
}

#Preview(traits: .mockData) {
    ThumbnailDiceRow(itemId: MockData.previewId)
}
