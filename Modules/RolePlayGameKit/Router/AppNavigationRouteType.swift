// @copyright André Trettin

import CoreRPG
import SwiftUI

public enum AppNavigationRouteType: Int, Codable {
    case tabbed
    case split
    case visionSplit
    case tabbedSplit
}

extension AppNavigationRouteType: NavigationDestination {
    public var body: some View {
        switch self {
        case .tabbed:
            TabbedNavigation()
        case .split:
#if os(tvOS)
            EmptyView()
#else
            SplitNavigation()
#endif
        case .visionSplit:
            TabbedSplitExtNavigation()
        case .tabbedSplit:
            TabbedSplitNavigation()
        }
    }
}
