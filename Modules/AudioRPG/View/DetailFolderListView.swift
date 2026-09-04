// @copyright André Trettin

import CoreRPG
import SwiftUI

#Preview(traits: .mockData) {
    @Previewable @Environment(AudioRootModel.self) var root
    DetailFolderListView(root: root, model: root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items[0]), folderListController: root.folderListController)
}

struct DetailFolderListView: View {
    let root: AudioRootModel
    let model: AudioModel
    let folderListController: FolderListController
    var isSubFolder: Bool = false

    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()

        // See `ItemDetailRootView.bottomOverlayBar`'s own doc for why this
        // is a parameter on it rather than chained on here — CODE_AUDIT_10
        // §9.11.
        ItemDetailRootView(
            root: root.rootController,
            detailListController: folderListController,
            selectedModel: model,
            configuration: .init(isSubFolder: isSubFolder),
            linkTypes: EmptyLinkTransferable.self,
            showsBottomOverlayBar: !usesPhoneTabAccessory,
            bottomOverlayBarHeight: 80
        ) {
            AudioPlayerBarView()
                .padding()
        } editor: {
            DetailEditorView(root: root, model: model)
        }
        .openFileWindowOverlay(root.openFileWindowModel) { itemId, dismiss in
            root.viewController.viewer(
                root: root,
                itemId: itemId,
                configuration: ViewerConfiguration(closeButton: true),
                dismissAction: dismiss
            )
        }
    }

    private var usesPhoneTabAccessory: Bool {
#if os(iOS)
        UIDevice.current.userInterfaceIdiom == .phone
#else
        false
#endif
    }
}
