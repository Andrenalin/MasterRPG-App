// @copyright André Trettin

import CoreRPG
import SwiftUI

#Preview(traits: .mockData) {
    @Previewable @Environment(SpaceRootModel.self) var root
    DetailFolderListView(root: root, model: root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items[0]), folderListController: root.folderListController)
}

struct DetailFolderListView: View {
    let root: SpaceRootModel
    let model: SpaceModel
    let folderListController: any FolderListControllable
    var isSubFolder: Bool = false
    
    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()

        ItemDetailRootView(
            root: root.rootController,
            detailListController: folderListController,
            selectedModel: model,
            configuration: .init(editorAsBackground: true, isSubFolder: isSubFolder),
            linkTypes: EmptyLinkTransferable.self
        ) {
            ViewerRootView(model: model, configuration: ViewerConfiguration(closeButton: false, addToolbar: false, isGame: false))
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
}
