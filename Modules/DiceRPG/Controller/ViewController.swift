// @copyright André Trettin

import CoreRPG
import SwiftUI

public struct ViewController {
    weak var _root: DiceRootModel?
    var root: DiceRootModel {
        _root.unsafelyUnwrapped
    }
    
    public let goupViewType: GroupViewType = .none
}

extension ViewController: ViewControllable {}

// MARK: Viewer

public extension ViewController {
    @MainActor
    func linkWindow() -> some View {
        Text("")
//        LinkRootView(isInspector: false)
            .environment(root)
    }
}
