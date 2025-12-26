// @copyright André Trettin

import CoreRPG
import DiceRPG
import SwiftUI

struct DetailRootView: View {
    let root: TableRootModel
    let model: TableModel
    
    var body: some View {
        DetailListView(root: root, model: model)
            .detailInspectorModifier(folderListControllable: root.folderListController)
    }
}

#Preview(traits: .mockData) {
    @Previewable @Environment(TableRootModel.self) var root
    
    ManagedNavigationStack {
        DetailRootView(root: root, model: root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items.first ?? TableModel.previewId))
            .preferredColorScheme(.dark)
    }
    .setAppSizeMode()
}
