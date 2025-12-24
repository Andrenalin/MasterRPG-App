// @copyright André Trettin

import CoreRPG
import DiceRPG
import PhotoRPG
import SwiftUI

struct InlineRowViewer: View, Equatable {
    let source: ItemRowModel
    
    @Environment(CharacterRootModel.self) private var root
    
    var body: some View {
        if source.typeId == .photo {
            root.photoRoot.viewController.photoRow(root: root.photoRoot, for: source.itemId)
        }
        
        if source.typeId == .dice {
            root.diceRoot.viewController.viewDice(root: root.diceRoot, with: source.itemId, for: ResultCategory(source: source))
        }
    }
    
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.source == rhs.source
    }
}

#Preview(traits: .mockData) {
    InlineRowViewer(source: ItemRowModel(itemId: MockData.previewId, typeId: .photo))
}
