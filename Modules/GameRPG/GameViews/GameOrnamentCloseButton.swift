// @copyright André Trettin

#if os(visionOS)
import CoreRPG
import SwiftUI

/// Close control for the top-leading scene ornament on visionOS, sized to
/// match the volume and wifi/join-code buttons in the top-trailing ornament.
struct GameOrnamentCloseButton: View {
    @Environment(GameScreenModel.self) private var gameScreenModel

    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()
        Button {
            gameScreenModel.showQuitGameAlert = true
        } label: {
            Label {
                Text("Quit", bundle: .module)
            } icon: {
                Image(systemName: "xmark.circle")
            }
        }
        .labelStyle(.iconOnly)
        .frame(minWidth: 44, minHeight: 44)
        .help(Text("Quit", bundle: .module))
    }
}

#Preview(traits: .mockData) {
    GameOrnamentCloseButton()
        .environment(GameScreenModel())
}
#endif
