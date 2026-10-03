// @copyright André Trettin

import CoreRPG
import SwiftUI

#Preview(traits: .mockData) {
    @Previewable @Environment(DiceRootModel.self) var root
    DetailFolderListView(
        root: root,
        model: root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items[0]),
        folderListController: root.folderListController
    )
}

struct DetailFolderListView: View {
    let root: DiceRootModel
    let model: DiceModel
    let folderListController: any FolderListControllable
    var isSubFolder: Bool = false
    
    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()

        DetailFolderList(
            root: root.rootController,
            openFileWindowModel: root.openFileWindowModel,
            detailListController: folderListController,
            selectedModel: model,
            configuration: .init(disableHideHeader: true, isSubFolder: isSubFolder),
            linkTypes: EmptyLinkTransferable.self
        ) {
            DiceOverlayView(model: model)
        } editor: {
            DetailEditorView(model: model)
        } viewer: { itemId, dismiss in
            root.viewController.viewer(
                root: root,
                itemId: itemId,
                configuration: ViewerConfiguration(closeButton: true),
                dismissAction: dismiss
            )
        }
    }
}
