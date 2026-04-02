// @copyright André Trettin

import CoreRPG
import SwiftUI

public struct ViewController {
    weak var root: GameRoot!
}

public extension ViewController {
    @MainActor func logWindow() -> some View {
        LogMessageList(logController: root.logGameController)
    }
}
