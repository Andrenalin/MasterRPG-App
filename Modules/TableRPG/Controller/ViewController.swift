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
        AnyView(ThumbnailDiceRow(itemId: itemId))
    }
}

// MARK: External Views

extension ViewController {
    @MainActor
    func diceSelection(root: TableRootModel, selectionModel: ItemSelectionModel) -> some View {
        root.diceRoot.viewController.selectionView(root: root.diceRoot, model: selectionModel)
    }    
}

// MARK: Viewer

public extension ViewController {
    @MainActor
    func linkWindow(root: TableRootModel, isInspector: Bool = false) -> some View {
        LinkRootView(type: isInspector ? .inspector : .window)
            .environment(root)
            .environment(root.diceRoot)
            .environment(root.pdfRoot)
    }
    
    @MainActor @ViewBuilder
    func windowViewer(root: TableRootModel, selection: WindowItemSelection) -> some View {
        if let model = root.itemController.model(for: selection.itemId) {
            TableSheet(model: model, showTopImage: false, dismissAction: nil)
                .environment(root)
        }
    }

    @MainActor @ViewBuilder
    func inlineViewer(root: TableRootModel, with id: UUID, dismissAction: (() -> Void)? = nil) -> some View {
        if let model = root.itemController.model(for: id) {
            TableSheet(model: model, showTopImage: false, dismissAction: dismissAction)
                .environment(root)
        }
    }
}
