// @copyright André Trettin

import CoreRPG
import SwiftUI

struct DetailFolderListView: View {
    let root: WeatherRootModel
    let model: WeatherModel
    let folderListController: any FolderListControllable
    @Binding var animate: Bool

    var body: some View {
        ItemDetailRootView(
            root: root.rootController,
            detailListController: folderListController,
            selectedModel: model,
            configuration: .init(),
            linkTypes: EmptyLinkTransferable.self) {
                WeatherEditor(model: model)
            }
            .safeAreaInset(edge: .bottom, alignment: .center, spacing: 12) {
                OverlayViewer(model: model, animate: $animate)
                    .opacity(0)
            }
            .overlay(alignment: .bottom) {
                OverlayViewer(model: model, animate: $animate)
                    .allowsHitTesting(false)
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
