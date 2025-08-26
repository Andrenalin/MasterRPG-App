// @copyright André Trettin

import CoreRPG
import SwiftUI

public struct ViewController {
    weak var _root: DiceRootModel?
    var root: DiceRootModel {
        _root.unsafelyUnwrapped
    }
    
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
    func linkWindow() -> some View {
        Text("")
//        LinkRootView(isInspector: false)
            .environment(root)
    }
}
