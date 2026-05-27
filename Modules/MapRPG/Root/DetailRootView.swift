// @copyright André Trettin

import CoreRPG
import SwiftUI

struct DetailRootView: View {
    let root: MapRootModel
    let model: MapModel

    var body: some View {
        DetailListView(root: root, model: model)
            .detailInspectorModifier(root: root.rootController)
            .folderNavigationResetTask(navigationModel: root.navigationModel, itemId: model.id)
    }
}

#Preview(traits: .mockData) {
    @Previewable @Environment(MapRootModel.self) var root
    ManagedNavigationStack {
        DetailRootView(root: root, model: root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items.first ?? MapModel.previewId))
            .preferredColorScheme(.dark)
    }
}
