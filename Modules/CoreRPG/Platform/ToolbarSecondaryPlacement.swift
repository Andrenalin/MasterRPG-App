// @copyright André Trettin

import SwiftUI

extension ToolbarItemPlacement {
    public static var secondaryActionAll: ToolbarItemPlacement {
#if os(tvOS)
        .automatic
#else
        .secondaryAction
#endif
    }
}

extension SearchFieldPlacement {
    public static var toolbarAll: SearchFieldPlacement {
#if os(tvOS)
        .automatic
#else
        .toolbar
#endif
    }

    public static var toolbarPrincipalAll: SearchFieldPlacement {
    #if os(tvOS)
            .automatic
    #else
            .toolbarPrincipal
    #endif
        }

    
    public static var navigationBarDrawerAll: SearchFieldPlacement {
#if os(tvOS)
        .automatic
#elseif os(macOS)
        .toolbar
#else
        .navigationBarDrawer(displayMode: .always)
#endif
    }

}
