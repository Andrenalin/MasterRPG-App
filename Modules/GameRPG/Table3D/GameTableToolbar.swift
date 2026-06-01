// @copyright André Trettin

#if os(visionOS)
import SwiftUI

struct GameTableToolbar: View {
    let game: GameTableModel

    var body: some View {
        HStack(spacing: 12) {
            Button(action: { game.resetGame() }) {
                Label { Text("Reset", bundle: .module) } icon: { Image(systemName: "arrow.counterclockwise") }
            }
            .labelStyle(.iconOnly)
        }
        .padding(12)
        .glassBackgroundEffect()
    }
}

#endif
