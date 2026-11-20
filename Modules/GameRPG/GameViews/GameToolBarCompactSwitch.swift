// @copyright André Trettin

import CoreRPG
import SwiftUI

/// Chooses between the iPhone's (compact width) map toolbar, where the 2D / 3D switch is a row
/// inside the toolbar above its buttons, and the single row used everywhere else.
struct GameToolBarCompactSwitch<Compact: View, Regular: View>: View {
    @ViewBuilder let compact: () -> Compact
    @ViewBuilder let regular: () -> Regular

#if os(iOS)
    @Environment(AppWindowSizeModel.self) private var appWindowSizeModel
#endif

    var body: some View {
#if os(iOS)
        if appWindowSizeModel.mode == .compact {
            compact()
        } else {
            regular()
        }
#else
        regular()
#endif
    }
}
