// @copyright André Trettin

import SwiftUI

public extension View {
    nonisolated func defaultTabBarPlacementAll(_ defaultPlacement: AdaptableTabBarPlacementAll) -> some View {
        #if os(iOS)
        Group {
        
            if #available(iOS 27.0, *) {
                self
                    .defaultTabBarPlacement(.sidebar)
            } else {
                self
            }
        }
        #else
        self
        #endif
    }
}

@MainActor
public enum AdaptableTabBarPlacementAll : Hashable {
    case automatic
    case tabBar
    case sidebar
}
