// @copyright André Trettin

import SwiftUI

@Observable
public final class TabTitleModel {
    public init(titles: [NetworkModules : String] = [:]) {
        self.titles = titles
    }
    
    public var titles: [NetworkModules: String]

#if os(iOS)
    public func toggleTitles(horizontalSizeClass: UserInterfaceSizeClass?, tabBarPlacement: TabBarPlacement?) {
        NetworkModules.allCases.forEach {
            titles[$0] <=> $0.title
//            if horizontalSizeClass == .compact || tabBarPlacement == .sidebar {
//                titles[$0] = $0.title
//            } else {
//                titles[$0] = ""
//            }
        }
    }
    #endif
}

