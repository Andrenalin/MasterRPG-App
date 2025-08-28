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
    func linkWindow(isInspector: Bool = false) -> some View {
        LinkRootView(type: isInspector ? .inspector : .window)
    }
    
    func selectionView(root: PhotoRootModel, model: SingleSelectionModel) -> some View {
        PhotoDropChooseView(model: model)
            .environment(root)
    }
}
