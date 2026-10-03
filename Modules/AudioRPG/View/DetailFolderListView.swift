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

#if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
#endif

    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()

        DetailFolderList(
            root: root.rootController,
            openFileWindowModel: root.openFileWindowModel,
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
        } viewer: { itemId, dismiss in
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
        horizontalSizeClass == .compact
#else
        false
#endif
    }
}
