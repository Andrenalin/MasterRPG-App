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
    }
}
