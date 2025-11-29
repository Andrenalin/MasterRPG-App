// @copyright André Trettin

import CoreRPG
import SwiftUI

struct EntryRow: View {
    init(root: DiceRootModel, item: ItemRowTreeModel) {
        self.root = root
        self.item = item
    }
    
    let root: DiceRootModel
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
    EntryRow(root: DiceRootModel.preview, item: .preview)
        .environment(DiceRootModel.preview)
        .border(.red, width: 2)
}
