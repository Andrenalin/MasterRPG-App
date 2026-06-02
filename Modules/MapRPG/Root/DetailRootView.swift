// @copyright André Trettin

import CoreRPG
import SwiftUI

struct DetailRootView: View {
    let root: MapRootModel
    let model: MapModel

    var body: some View {
        DetailListView(root: root, model: model, folderListController: root.folderListController)
            .detailInspectorModifier(root: root.rootController)
    }
}

#Preview(traits: .mockData) {
    @Previewable @Environment(MapRootModel.self) var root
    ManagedNavigationStack {
        DetailRootView(root: root, model: root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items.first ?? MapModel.previewId))
            .preferredColorScheme(.dark)
    }
}
