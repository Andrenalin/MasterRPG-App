// @copyright André Trettin

import CoreRPG
import SwiftUI

public enum AppRootType: Int, Codable {
    case tabbed
    case split
    case tabbedExtSplit
    case tabbedSplit
}

extension AppRootType: NavigationDestination {
    public var body: some View {
        switch self {
        case .tabbed:
            TabbedNavigation()
        case .split:
#if os(tvOS)
            TabbedNavigation()
#else
            SplitNavigation()
#endif
        case .tabbedExtSplit:
            TabbedSplitExtNavigation()
        case .tabbedSplit:
            TabbedSplitNavigation()
        }
    }
}
