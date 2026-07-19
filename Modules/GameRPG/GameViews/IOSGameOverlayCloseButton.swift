// @copyright André Trettin

#if os(iOS)
import SwiftUI

struct IOSGameOverlayCloseButton: View {
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
        .imageScale(.large)
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .padding(8)
        .contentShape(.circle)
        .glassEffect(.regular.interactive(), in: .circle)
        .help(Text("Quit", bundle: .module))
    }
}

#Preview {
    IOSGameOverlayCloseButton()
        .environment(GameScreenModel())
}
#endif
