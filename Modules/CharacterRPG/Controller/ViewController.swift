// @copyright André Trettin

import CoreRPG
import DiceRPG
import SwiftUI

public struct ViewController: Sendable {
    public let goupViewType: GroupViewType = .item
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
    func diceSelection(root: CharacterRootModel, selectionModel: ItemSelectionModel) -> some View {
        root.diceRoot.viewController.selectionView(root: root.diceRoot, model: selectionModel)
    }
}

// MARK: Viewer

public extension ViewController {
    @MainActor
    func linkWindow(root: CharacterRootModel, isInspector: Bool = false) -> some View {
        LinkRootView(type: isInspector ? .inspector : .window)
            .environment(root)
            .environment(root.diceRoot)
            .environment(root.pdfRoot)
            .environment(root.photoRoot)
            .environment(root.tableRoot)
    }
}
