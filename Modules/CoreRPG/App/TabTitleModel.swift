// @copyright André Trettin

import SwiftUI

@Observable
public final class TabTitleModel {
    public init(titles: [RootRoute : String] = [:]) {
        self.titles = titles
    }
    
    public var titles: [RootRoute: String]

#if os(iOS)
    public func toggleTitles(horizontalSizeClass: UserInterfaceSizeClass?, tabBarPlacement: TabBarPlacement?) {
        RootRoute.allTabs.forEach {
            if horizontalSizeClass == .compact || tabBarPlacement == .sidebar {
                titles[$0] = $0.title
            } else {
                titles[$0] = ""
            }
        }
    }
    #endif
}

