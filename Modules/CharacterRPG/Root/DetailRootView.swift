// @copyright André Trettin

import CoreRPG
import SwiftUI

struct DetailRootView: View {
    let root: CharacterRootModel
    let model: ValueModel

    @Environment(AppWindowSizeModel.self) private var appSizeModel

    var body: some View {
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
    @Previewable @Environment(CharacterRootModel.self) var root
    ManagedNavigationStack {
        DetailRootView(root: root, model: root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items.first ?? ValueModel.previewId))
            .preferredColorScheme(.dark)
    }
}
