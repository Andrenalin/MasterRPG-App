// @copyright André Trettin

import CoreRPG
import SwiftUI

public struct ViewController {
    weak var _root: DiceRootModel?
    var root: DiceRootModel {
        _root.unsafelyUnwrapped
    }
}

// MARK: Viewer

public extension ViewController {
    @MainActor
    func linkWindow() -> some View {
        LinkRootView(isInspector: false)
            .environment(root)
    }
}
