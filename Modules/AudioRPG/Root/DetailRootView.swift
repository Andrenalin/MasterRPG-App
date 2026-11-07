// @copyright André Trettin

import CoreRPG
import SwiftUI

struct DetailRootView: View {
    let root: AudioRootModel
    let model: AudioModel

    @Environment(\.networkActions) private var networkActions
    @Environment(AppGameStateModel.self) private var appGameStateModel: AppGameStateModel?

    var body: some View {
        DetailListView(root: root, model: model, folderListController: root.folderListController)
            .detailInspectorModifier(root: root.rootController)
#if os(iOS) || os(visionOS)
            .siriTip(for: PlayAudioIntent(), storageKey: "suggest.playAudioShortcut")
#endif
            .onChange(of: root.navigationModel.triggerSpaceAction) {
                guard root.navigationModel.triggerSpaceAction else { return }
                root.navigationModel.triggerSpaceAction = false
                // The same entry point as the play buttons: a folder plays its playlist.
                root.toggleItem(id: model.id, isGameRunning: appGameStateModel?.isGameRunning == true, networkActions: networkActions)
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
