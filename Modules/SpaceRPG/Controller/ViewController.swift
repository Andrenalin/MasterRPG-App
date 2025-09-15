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
    func linkWindow(root: SpaceRootModel, isInspector: Bool = false) -> some View {
        LinkRootView(type: isInspector ? .inspector : .window)
            .environment(root)
    }
    
    @MainActor
    func windowViewer(root: SpaceRootModel, selection: WindowItemSelection) -> some View {
        let model = root.itemController.item(for: selection.itemId) ?? .newItem
        return ViewerRootView(model: model)
            .environment(root)
    }

    @MainActor
    func inlineViewer(root: SpaceRootModel, with id: UUID, dismissAction: (() -> Void)? = nil) -> some View {
        let model = root.itemController.item(for: id) ?? .newItem
        return ViewerRootView(model: model, dismissAction: dismissAction)
            .environment(root)
    }
}
