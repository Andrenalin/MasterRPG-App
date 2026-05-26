// @copyright André Trettin

#if os(visionOS)
import SwiftUI

struct GameTableToolbar: View {
    let game: GameTableModel

    var body: some View {
        HStack(spacing: 12) {
            Button("Reset", systemImage: "arrow.counterclockwise") {
                game.resetGame()
            }
            .labelStyle(.iconOnly)
        }
        .padding(12)
        .glassBackgroundEffect()
    }
}

#endif
