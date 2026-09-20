// @copyright André Trettin

#if os(visionOS)
import SwiftUI

/// Surfaces table conditions that would otherwise be silent: dice results that could not be mirrored
/// onto the table, and a seat (with its dice pool) that may be shared with another player.
@MainActor
struct GameTableNoticesView: View {
    let game: GameTableModel

    var body: some View {
        if game.diceOverflowCount != nil || game.sharedSeatPlayerCount != nil {
            VStack(alignment: .leading) {
                if let count = game.diceOverflowCount {
                    Label {
                        Text("\(count) dice results are not shown on the table", bundle: .module)
                    } icon: {
                        Image(systemName: "die.face.5")
                    }
                }
                if let players = game.sharedSeatPlayerCount {
                    Label {
                        Text("This table has fewer seats than players (\(players)). You may share a seat and its dice.", bundle: .module)
                    } icon: {
                        Image(systemName: "person.2")
                    }
                }
            }
            .font(.footnote)
            .padding()
            .glassBackgroundEffect()
        }
    }
}
#endif
