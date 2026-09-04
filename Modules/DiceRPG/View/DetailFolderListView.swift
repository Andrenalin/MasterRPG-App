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

        // See `ItemDetailRootView.bottomOverlayBar`'s own doc for why this
        // is a parameter on it rather than chained on here — CODE_AUDIT_10
        // §9.11.
        ItemDetailRootView(
            root: root.rootController,
            detailListController: folderListController,
            selectedModel: model,
            configuration: .init(disableHideHeader: true, isSubFolder: isSubFolder),
            linkTypes: EmptyLinkTransferable.self
        ) {
            DiceOverlayView(model: model)
        } editor: {
            DetailEditorView(model: model)
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
