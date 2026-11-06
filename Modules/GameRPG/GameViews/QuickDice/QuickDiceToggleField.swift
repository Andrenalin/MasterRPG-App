// @copyright André Trettin

import CoreRPG
import SwiftUI

/// The quick dice show/hide button as a round glass field, floating at the bottom leading side
/// of the quick dice overlay (see `OverlayGameLayout`) instead of in the top menu.
struct QuickDiceToggleField: View {
    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()
        GameQuickDiceToggleButton()
            .roundGameControl()
    }
}

#Preview {
    QuickDiceToggleField()
        .padding()
        .environment(GameScreenModel())
}
