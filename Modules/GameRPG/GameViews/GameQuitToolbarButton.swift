// @copyright André Trettin

#if os(macOS)
import SwiftUI

struct GameQuitToolbarButton: View {
    @Environment(GameScreenModel.self) private var gameScreenModel

    var body: some View {
        Button(role: .cancel) {
            gameScreenModel.showQuitGameAlert = true
        } label: {
            Label {
                Text("Quit", bundle: .module)
            } icon: {
                Image(systemName: "xmark.circle")
            }
            .labelStyle(.iconOnly)
        }
        .help(Text("Quit", bundle: .module))
    }
}

#Preview {
    GameQuitToolbarButton()
        .environment(GameScreenModel())
}
#endif
