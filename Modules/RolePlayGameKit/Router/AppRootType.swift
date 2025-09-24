// @copyright André Trettin

import CoreExternalRPG
import SwiftUI

public enum AppRootType: Int, Codable {
    case tabbed
    case split
    case tabbedSplit
}

extension AppRootType: NavigationDestination {
    public var body: some View {
        switch self {
        case .tabbed:
            TabbedNavigation()
        case .split:
            SplitNavigation()
        case .tabbedSplit:
            TabbedSplitNavigation()
        }
    }
}
