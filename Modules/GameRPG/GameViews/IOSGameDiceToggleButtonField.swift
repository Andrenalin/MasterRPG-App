// @copyright André Trettin

import CoreRPG
#if os(iOS)
import SwiftUI

/// The round glass field the iOS overlay menu puts around the dice toggle button.
struct IOSGameDiceToggleButtonField: View {
    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()
        GameDiceToggleButton()
            .roundGameControl()
    }
}

#Preview {
    IOSGameDiceToggleButtonField()
        .environment(GameScreenModel())
}
#endif
