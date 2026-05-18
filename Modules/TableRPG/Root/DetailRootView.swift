// @copyright André Trettin

import CoreRPG
import SwiftUI

struct DetailRootView: View {
    let root: TableRootModel
    let model: TableModel

    @Environment(AppWindowSizeModel.self) private var appSizeModel

    var body: some View {
        let _ = Self._printChanges()
        DetailListView(root: root, model: model)
            .detailInspectorModifier(root: root.rootController)
            .task(id: model.id) {
                if appSizeModel.mode == .regular {
                    root.navigationModel.folderItems = []
                    root.navigationModel.folderModels = [:]
                }
            }
    }
}

#Preview(traits: .mockData) {
    @Previewable @Environment(TableRootModel.self) var root
    
    ManagedNavigationStack {
        DetailRootView(root: root, model: root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items.first ?? UUID()))
            .preferredColorScheme(.dark)
    }
}
