// @copyright André Trettin

import CoreRPG
import SwiftUI

struct DetailFolderListView: View {
    let root: PdfRootModel
    let model: PdfModel
    let folderListController: any FolderListControllable

    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()

        ItemDetailRootView(
            root: root.rootController,
            detailListController: folderListController,
            selectedModel: model,
            configuration: .init(),
            linkTypes: LinkPdfModuleTransferable.self
        ) {
            DetailEditorView(root: root, model: model)
        }
        .overlay {
            overlayContent
        }
    }

    // MARK: - Overlays

    @ViewBuilder
    private var overlayContent: some View {
        if root.openFileWindowModel.showItem {
            root.viewController.viewer(root: root, itemId: root.openFileWindowModel.itemId, entryId: nil, configuration: ViewerConfiguration(closeButton: true, canBookmark: true), onTextExtracted: nil, dismissAction: {
                root.openFileWindowModel.showItem = false
            })
        }
    }
}
