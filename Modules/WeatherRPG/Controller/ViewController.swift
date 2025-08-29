// @copyright André Trettin

import CoreRPG
import PhotoRPG
import SwiftUI

public struct ViewController: Sendable {
    public let goupViewType: GroupViewType = .photo
    public let thumbnailRowViewType: ThumbnailRowViewType = .photo
}

extension ViewController: ViewControllable {}

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
    func linkWindow() -> some View {
        LinkRootView(type: .window)
    }
}
