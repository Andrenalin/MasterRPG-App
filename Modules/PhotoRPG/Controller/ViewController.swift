// @copyright André Trettin

import CoreRPG
import SwiftUI

public struct ViewController: Sendable {
    public let goupViewType: GroupViewType = .photo
    public let thumbnailRowViewType: ThumbnailRowViewType = .photo
}

extension ViewController: ViewControllable {}

// MARK: Viewer

public extension ViewController {
    @MainActor
    func linkWindow(root: PhotoRootModel, isInspector: Bool = false) -> some View {
        LinkRootView(type: isInspector ? .inspector : .window)
            .environment(root)
    }
    
    func selectionView(root: PhotoRootModel, model: ItemSelectionModel) -> some View {
        PhotoDropChooseView(model: model)
            .environment(root)
    }
    
    @ViewBuilder @MainActor
    func thumbnailRow(root: PhotoRootModel, for itemId: UUID) -> some View {
        if let model = root.itemController.modelSync(for: itemId) {
            ThumbnailRowPhotoView(cacheController: root.cacheController, model: model)
        }
    }
}
