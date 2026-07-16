// @copyright André Trettin

#if os(iOS)
import SwiftUI

struct IOSGameDiceToggleButtonField: View {
    var body: some View {
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
