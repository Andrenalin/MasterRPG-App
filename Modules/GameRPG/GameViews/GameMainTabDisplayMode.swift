// @copyright André Trettin

import Foundation

/// Display mode for the game main tab
enum GameMainTabDisplayMode: Int, Equatable {
    /// Game tab is hidden
    case hidden = 0
    /// Game tab is shown inline within the game screen
    case inline = 1
    /// Game tab is shown in a separate window (macOS toolbar)
    case window = 2
}
