// @copyright André Trettin

import CoreRPG
#if os(iOS)
import SwiftUI

struct IOSGameDiceToggleButtonField: View {
    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()
        GameDiceToggleButton()
            .buttonStyle(.plain)
            .imageScale(.large)
            .padding(8)
            .contentShape(.circle)
            .glassEffect(.regular.interactive(), in: .circle)
    }
}

#Preview {
    IOSGameDiceToggleButtonField()
        .environment(GameScreenModel())
}
#endif
