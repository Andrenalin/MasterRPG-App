// @copyright André Trettin

import CoreRPG
import DiceRPG
import SwiftData
import SwiftUI

struct ThumbnailDiceRow: View {
    let itemId: UUID
    
    @Environment(TableRootModel.self) private var root
    
    var body: some View {
        let _ = Self._printChanges()
        if let diceId = model?.diceId {
            root.diceRoot.viewController.thumbnailRowView(for: diceId)
        }
    }
    
    private var model: TableDataModel? {
        root.itemController.model(for: itemId)
    }
}

#Preview(traits: .mockData) {
    ThumbnailDiceRow(itemId: MockData.previewId)
}
