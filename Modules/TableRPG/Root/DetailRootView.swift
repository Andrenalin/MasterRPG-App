// @copyright André Trettin

import CoreRPG
import SwiftUI

struct DetailRootView: View {
    let root: TableRootModel
    let model: TableModel

    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()
        DetailListView(root: root, model: model, folderListController: root.folderListController)
            .detailInspectorModifier(root: root.rootController)
    }
}

#Preview(traits: .mockData) {
    @Previewable @Environment(TableRootModel.self) var root

    ManagedNavigationStack {
        DetailRootView(root: root, model: root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items.first ?? UUID()))
            .preferredColorScheme(.dark)
    }
}
