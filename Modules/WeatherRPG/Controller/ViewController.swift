// @copyright André Trettin

import CoreRPG
import PhotoRPG
import SwiftUI

public struct ViewController: Sendable {
    public let goupViewType: GroupViewType = .photo
    public let thumbnailRowViewType: ThumbnailRowViewType = .custom
}

extension ViewController: ViewControllable {
    public func thumbnailRowView(for itemId: UUID) -> AnyView {
        AnyView(ThumbnailPhotoRow(itemId: itemId))
    }
}

// MARK: External Views

extension ViewController {
    @MainActor
    func photoSelection(root: WeatherRootModel, selectionModel: ItemSelectionModel) -> some View {
        root.photoRoot.viewController.selectionView(root: root.photoRoot, model: selectionModel)
    }
}

// MARK: Viewer

public extension ViewController {
    @MainActor
    func linkWindow(root: WeatherRootModel, isInspector: Bool = false) -> some View {
        LinkRootView(type: isInspector ? .inspector : .window)
            .environment(root)
            .environment(root.photoRoot)
    }
    
    @MainActor
    func windowViewer(root: WeatherRootModel, selection: WindowItemSelection) -> some View {
        let model = root.itemController.modelSync(for: selection.itemId) ?? .newItem
        return ViewerRootView(model: model)
            .environment(root)
    }

    @MainActor
    func inlineViewer(root: WeatherRootModel, with id: UUID, dismissAction: (() -> Void)? = nil) -> some View {
        let model = root.itemController.modelSync(for: id) ?? .newItem
        return ViewerRootView(model: model, dismissAction: dismissAction)
            .environment(root)
    }

}
