// @copyright André Trettin

import AndrenalinKit
import SwiftUI

struct EntryRow: View {
    init(root: DiceRoot, item: ItemRowTreeModel) {
        self.root = root
        self.item = item
    }
    
    let root: DiceRoot
    let item: ItemRowTreeModel
    
    @Environment(\.showGame) private var showGame
    @Environment(\.networkActions) private var networkActions
    
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Button {
                    withAnimation { root.gameController.rollDice(itemId: item.model.itemId, networkActions: networkActions) }
                } label: {
                    Image(systemName: root.itemController.itemDataModel.networkModule.icon)
                }
                
                if showGame && !root.gameController.isFocusedDice(itemId: item.model.itemId) {
                    Spacer()
                    
                    Button {
                        withAnimation { root.gameController.gameModel.focusItemIds = [item.model.itemId] }
                    } label: {
                        Image(systemName: "house")
                    }
                }
            }
            .buttonStyle(.borderedProminent)

            ScrollView(.horizontal) {
                DiceRoll(itemId: item.model.itemId)
            }
        }
    }
}

#Preview {
    EntryRow(root: DiceRoot.preview, item: .preview)
        .environment(DiceRoot.preview)
        .border(.red, width: 2)
}
