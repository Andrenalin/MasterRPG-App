// @copyright André Trettin

import SwiftUI

/// Keyboard focus shared by the three columns of the editor layout.
public enum NavigationColumnFocus: Hashable, Sendable {
    case none
    case tabs
    case list
    case detail
}
