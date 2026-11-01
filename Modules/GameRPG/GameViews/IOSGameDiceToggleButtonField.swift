// @copyright André Trettin

import CoreRPG
#if os(iOS)
import SwiftUI

/// The round glass field the iOS overlay menu puts around a toggle button.
private struct IOSGameToggleButtonField<ToggleButton: View>: View {
    @ViewBuilder let toggleButton: ToggleButton

    var body: some View {
        toggleButton
            .buttonStyle(.plain)
            .imageScale(.large)
            .padding(8)
            .contentShape(.circle)
            .glassEffect(.regular.interactive(), in: .circle)
    }
}

struct IOSGameDiceToggleButtonField: View {
    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()
        IOSGameToggleButtonField {
            GameDiceToggleButton()
        }
    }
}

#Preview {
    IOSGameDiceToggleButtonField()
        .environment(GameScreenModel())
}
#endif
