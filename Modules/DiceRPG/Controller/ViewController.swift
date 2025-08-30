// @copyright André Trettin

import CoreRPG
import SwiftUI

public struct ViewController {
    public let goupViewType: GroupViewType = .none
    public let thumbnailRowViewType: ThumbnailRowViewType = .custom
}

extension ViewController: ViewControllable {
    public func thumbnailRowView(for itemId: UUID) -> AnyView {
        AnyView(ThumbnailDiceRow(itemId: itemId))
    }
}

// MARK: Viewer

public extension ViewController {
    @MainActor
    func linkWindow(root: DiceRootModel, isInspector: Bool = false) -> some View {
        LinkRootView(type: isInspector ? .inspector : .window)
            .environment(root)
    }
    
    func selectionView(root: DiceRootModel, model: ItemSelectionModel) -> some View {
        DiceDropChooseView(model: model)
            .environment(root)
    }
}
