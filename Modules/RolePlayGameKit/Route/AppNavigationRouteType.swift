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
        let _ = Self.printViewChangesOnlyInDebug()
        
        switch self {
        case .tabbed:
            TabbedNavigation()
        case .split:
#if os(tvOS)
            EmptyView()
#elseif os(visionOS)
            SplitEditorNavigation()
#else
            SplitNavigation()
#endif
        case .visionSplit:
            SplitVisionNavigation()
        case .tabbedSplit:
            TabbedSplitNavigation()
        }
    }
}
