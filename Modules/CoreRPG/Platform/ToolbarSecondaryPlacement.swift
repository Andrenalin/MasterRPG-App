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
