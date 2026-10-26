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
        DetailFolderList(
            root: root.rootController,
            openFileWindowModel: root.openFileWindowModel,
            detailListController: folderListController,
            selectedModel: model,
            configuration: .init(editorAsBackground: true, editorOnTop: editorOnTop, isSubFolder: isSubFolder),
            linkTypes: EmptyLinkTransferable.self
        ) {
            // An item without a file gets no viewer at all: creating a `RealityView` before a
            // scan leaves `ObjectCaptureSession` without a camera feed, and only an item without
            // a file offers the scanner. See `SpaceRootModel.liveViewerWasShown`.
            if model.url == nil {
                Color.clear
            } else {
                ViewerRootView(model: model, configuration: ViewerConfiguration(closeButton: false, addToolbar: false, isGame: false))
            }
        } viewer: { itemId, dismiss in
            root.viewController.viewer(
                root: root,
                itemId: itemId,
                configuration: ViewerConfiguration(closeButton: true, addToolbar: true),
                dismissAction: dismiss
            )
        }
    }

    // The RealityView has real depth, so a flat overlay drawn "in front of" it
    // in the view tree doesn't reliably stay visually in front on visionOS —
    // the model can protrude past the overlay's plane. Layering the editor on
    // top instead (with top padding clearing the file-importer overlay) avoids
    // that collision. See ItemEditorBackgroundView.editorOnTop.
    private var editorOnTop: Bool {
#if os(visionOS)
        true
#else
        false
#endif
    }
}
