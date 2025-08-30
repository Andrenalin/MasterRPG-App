// @copyright André Trettin

import CoreRPG
import PhotoRPG
import SwiftUI

public struct ViewController: Sendable {
    public let goupViewType: GroupViewType = .item
    public let thumbnailRowViewType: ThumbnailRowViewType = .none
}

extension ViewController: ViewControllable {}

// MARK: External Views

extension ViewController {
    @MainActor
    func diceSelection(root: TableRootModel, selectionModel: ItemSelectionModel) -> some View {
        Text("coming")
        //root.diceRoot.viewController.selectionView(root: root.diceRoot, model: selectionModel)
    }
}

// MARK: Viewer

public extension ViewController {
    @MainActor
    func linkWindow() -> some View {
        LinkRootView(type: .window)
    }
}
