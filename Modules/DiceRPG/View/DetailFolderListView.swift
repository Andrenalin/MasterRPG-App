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

        // Deliberately does NOT use the shared `DetailFolderList` (CoreRPG,
        // see CODE_AUDIT §9.3): `DiceOverlayView`'s `safeAreaInset`/`overlay`
        // must sit *between* the editor content and `.openFileWindowOverlay`
        // so the file viewer still renders above it — wrapping them the
        // other way around (chained onto `DetailFolderList`'s already-
        // composed result) would swap that stacking order.
        ItemDetailRootView(
            root: root.rootController,
            detailListController: folderListController,
            selectedModel: model,
            configuration: .init(disableHideHeader: true, isSubFolder: isSubFolder),
            linkTypes: EmptyLinkTransferable.self
        ) {
            DetailEditorView(model: model)
        }
        .safeAreaInset(edge: .bottom, alignment: .center, spacing: 12) {
            DiceOverlayView(model: model)
                .opacity(0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .overlay(alignment: .bottom) {
            DiceOverlayView(model: model)
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
