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
        ItemDetailRootView(
            root: root.rootController,
            detailListController: folderListController,
            selectedModel: model,
            configuration: .init(isSubFolder: isSubFolder),
            linkTypes: EmptyLinkTransferable.self) {
                WeatherEditor(model: model)
            }
            .safeAreaInset(edge: .bottom, alignment: .center, spacing: 12) {
                OverlayViewer(model: model, animate: $animate)
                    .opacity(0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .overlay(alignment: .bottom) {
                OverlayViewer(model: model, animate: $animate)
                    .allowsHitTesting(false)
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
