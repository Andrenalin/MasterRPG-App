// @copyright André Trettin

import CoreRPG
import SwiftUI

public struct ViewController {
    // Optional, not force-unwrapped: a weak reference is allowed to become
    // nil, and `logWindow()` below handles that instead of trapping.
    // See CODE_AUDIT_Game §5.9.
    weak var root: GameRoot?
}

public extension ViewController {
    @MainActor @ViewBuilder func logWindow() -> some View {
        if let root {
            LogMessageList(logController: root.logGameController)
        } else {
            ContentUnavailableView {
                Label {
                    Text("No Active Game", bundle: .module)
                } icon: {
                    Image(systemName: "gamecontroller")
                }
            }
        }
    }
}
