// @copyright André Trettin

import CoreRPG
import DiceRPG
import SwiftUI

#Preview(traits: .mockData) {
    @Previewable @Environment(TableRootModel.self) var root
    DetailFolderListView(root: root, model: root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items[0]), folderListController: root.folderListController)
}

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
