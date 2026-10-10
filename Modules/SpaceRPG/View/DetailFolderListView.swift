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

    private static let diagnosticNoBackgroundViewer = true

    var body: some View {
        DetailFolderList(
            root: root.rootController,
            openFileWindowModel: root.openFileWindowModel,
            detailListController: folderListController,
            selectedModel: model,
            configuration: .init(editorAsBackground: true, editorOnTop: editorOnTop, isSubFolder: isSubFolder),
            linkTypes: EmptyLinkTransferable.self
        ) {
            // Skip the background `RealityView` while a 3D scan is running: it and
            // `Scanner3DRootView`'s ObjectCaptureSession would otherwise render
            // concurrently and starve each other of Metal drawables. See
            // `SpaceRootModel.isScanning3D`.
            // TEMP DIAGNOSTIC, remove again: never mount the background `RealityView`, to test
            // whether a `RealityView` shown earlier in the launch blanks the scanner's camera feed.
            if root.isScanning3D || Self.diagnosticNoBackgroundViewer {
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
