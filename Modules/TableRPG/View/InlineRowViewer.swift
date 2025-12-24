// @copyright André Trettin

import CoreRPG
import DiceRPG
import SwiftUI

struct InlineRowViewer: View, Equatable {
    let source: ItemRowModel
    
    @Environment(TableRootModel.self) private var root
    
    var body: some View {
        let _ = Self._printChanges()
        if source.typeId == .dice {
            root.diceRoot.viewController.viewDice(root: root.diceRoot, with: source.itemId, for: ResultCategory(source: source))
        }
    }
    
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.source == rhs.source
    }
}

#Preview(traits: .mockData) {
    InlineRowViewer(source: ItemRowModel(itemId: MockData.previewId, typeId: .dice))
}
