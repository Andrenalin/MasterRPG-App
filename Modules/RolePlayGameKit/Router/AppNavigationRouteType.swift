// @copyright André Trettin

import CoreRPG
import SwiftUI

public enum AppNavigationRouteType: Int, Codable {
    case tabbed
    case split
    case visionSplit
    case tabbedExtSplit
    case tabbedSplit
}

extension AppNavigationRouteType: NavigationDestination {
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
        case .visionSplit:
            SplitEditorNavigation()
        case .tabbedSplit:
            TabbedSplitNavigation()
        }
    }
}
