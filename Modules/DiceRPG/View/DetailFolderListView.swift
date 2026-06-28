// @copyright André Trettin

import CoreRPG
import SwiftUI

struct DetailFolderListView: View {
    let root: DiceRootModel
    let model: DiceModel
    let folderListController: any FolderListControllable
    var isSubFolder: Bool = false
    
    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()

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
            DiceOverlayView(model: model).opacity(0)
        }
        .overlay(alignment: .bottom) {
            DiceOverlayView(model: model)
        }
        .overlay {
            overlayContent
        }
    }

    // MARK: - Overlays

    @ViewBuilder
    private var overlayContent: some View {
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
