// @copyright André Trettin

import CoreRPG
import SwiftUI

struct DetailFolderListView: View {
    let root: PhotoRootModel
    let model: PhotoModel
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
            ViewerRootView(model: model, configuration: ViewerConfiguration(addToolbar: false))
        }
        .overlay {
            overlayContent
        }
    }

    // MARK: - Overlays

    @ViewBuilder private var overlayContent: some View {
        if root.openFileWindowModel.showItem {
            root.viewController.viewer(
                root: root,
                itemId: root.openFileWindowModel.itemId,
                configuration: ViewerConfiguration(closeButton: true)
            ) {
                root.openFileWindowModel.showItem = false
            }
        }
    }
}
