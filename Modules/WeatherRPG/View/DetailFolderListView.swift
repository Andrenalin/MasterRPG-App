// @copyright André Trettin

import CoreRPG
import SwiftUI

#Preview(traits: .mockData) {
    @Previewable @Environment(WeatherRootModel.self) var root
    @Previewable @State var animate = false
    DetailFolderListView(
        root: root,
        model: root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items[0]),
        folderListController: root.folderListController,
        animate: $animate
    )
}

struct DetailFolderListView: View {
    let root: WeatherRootModel
    let model: WeatherModel
    let folderListController: any FolderListControllable
    var isSubFolder: Bool = false
    @Binding var animate: Bool

    var body: some View {
        // See `ItemDetailRootView.bottomOverlayBar`'s own doc for why this
        // is a parameter on it rather than chained on here — CODE_AUDIT_10
        // §9.11.
        ItemDetailRootView(
            root: root.rootController,
            detailListController: folderListController,
            selectedModel: model,
            configuration: .init(isSubFolder: isSubFolder),
            linkTypes: EmptyLinkTransferable.self
        ) {
            OverlayViewer(model: model, animate: $animate)
                .allowsHitTesting(false)
        } editor: {
            WeatherEditor(model: model)
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
