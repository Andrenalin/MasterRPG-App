// @copyright André Trettin

import CoreRPG
import SwiftUI

struct DetailRootView: View {
    let root: CharacterRootModel
    let model: ValueModel
    
    @Environment(\.appSizeMode) private var appSizeMode
    
    var body: some View {
        DetailListView(root: root, model: model)
            .detailInspectorModifier(folderListControllable: root.folderListController)
            .applyIf(appSizeMode == .regular) {
                $0.task(id: model.id) {
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
