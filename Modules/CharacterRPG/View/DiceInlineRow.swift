// @copyright André Trettin

import CoreRPG
import DiceRPG
import SwiftUI

struct DiceInlineRow: View, Equatable {
    let itemId: UUID
    
    @Environment(CharacterRootModel.self) private var root
    
    var body: some View {
        let _ = Self._printChanges()
        root.diceRoot.viewController.viewDice(root: root.diceRoot, with: itemId, for: ResultCategory(id: itemId, module: root.itemController.itemDataModel.networkModule))
    }
    
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.itemId == rhs.itemId
    }
}

#Preview(traits: .mockData) {
    DiceInlineRow(itemId: MockData.previewId)
}
