// @copyright André Trettin

import CoreRPG
import SwiftUI

struct DetailRootView: View {
    let root: AudioRootModel
    let model: AudioModel

    var body: some View {
        DetailListView(root: root, model: model, folderListController: root.folderListController)
            .detailInspectorModifier(root: root.rootController)
        // deactivated for now - maybe later not needed amymore
//            .folderNavigationResetTask(navigationModel: root.navigationModel, itemId: model.id)
            .onChange(of: root.navigationModel.triggerSpaceAction) {
                guard root.navigationModel.triggerSpaceAction else { return }
                root.navigationModel.triggerSpaceAction = false
                root.audioController.togglePlay(id: model.id)
            }
    }
}

#Preview(traits: .mockData) {
    @Previewable @Environment(AudioRootModel.self) var root
    ManagedNavigationStack {
        DetailRootView(root: root, model: root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items.first ?? AudioModel.previewId))
            .preferredColorScheme(.dark)
    }
}
