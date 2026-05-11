// @copyright André Trettin

import CoreRPG
import SwiftUI

struct DetailRootView: View, Equatable {
    let root: TableRootModel
    let model: TableModel

    @Environment(AppWindowSizeModel.self) private var appSizeModel

    static func == (lhs: DetailRootView, rhs: DetailRootView) -> Bool {
        lhs.model.id == rhs.model.id
    }

    var body: some View {
        DetailListView(root: root, model: model)
            .equatable()
            .detailInspectorModifier()
            .applyIf(appSizeModel.mode == .regular) {
                $0.task(id: model.id) {
                    root.navigationModel.folderItems = []
                    root.navigationModel.folderModels = [:]
                }
            }
    }
}

#Preview(traits: .mockData) {
    @Previewable @Environment(TableRootModel.self) var root
    
    ManagedNavigationStack {
        DetailRootView(root: root, model: root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items.first ?? TableModel.previewId))
            .preferredColorScheme(.dark)
    }
}
