// @copyright André Trettin

import CoreRPG
import SwiftUI
import DiceRPG

struct DetailFolderListView: View {
    let root: TableRootModel
    let model: TableModel
    let folderListController: any FolderListControllable
    var isSubFolder: Bool = false
    
    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()

        ItemDetailRootView(
            root: root.rootController,
            detailListController: folderListController,
            selectedModel: model,
            configuration: .init(isSubFolder: isSubFolder),
            linkTypes: LinkTableModuleTransferable.self
        ) {
            DetailEditorView(root: root, model: model)
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
