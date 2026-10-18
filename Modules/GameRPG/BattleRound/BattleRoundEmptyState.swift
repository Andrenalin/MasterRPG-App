// @copyright André Trettin

import SwiftUI

struct BattleRoundEmptyState: View {
    let isRunning: Bool
    let start: @MainActor () -> Void

    var body: some View {
        ContentUnavailableView {
            Label {
                if isRunning {
                    Text("No Combatants", bundle: .module)
                } else {
                    Text("No Battle Running", bundle: .module)
                }
            } icon: {
                Image(systemName: "shield.lefthalf.filled")
            }
        } description: {
            if isRunning {
                Text("The selected map has no player or active-room combatants.", bundle: .module)
            } else {
                Text("Start a battle with player pins and the monsters in the selected room.", bundle: .module)
            }
        } actions: {
            if !isRunning {
                Button(
                    String(localized: "Start Battle", bundle: .module),
                    systemImage: "play.fill",
                    action: start
                )
                    .buttonStyle(.borderedProminent)
            }
        }
        // The scrolling battle list centres this with
        // `containerRelativeFrame`; a lazy stack row has no height to fill.
        .frame(maxWidth: .infinity)
    }
}

#Preview("No battle") {
    BattleRoundEmptyState(isRunning: false, start: {})
        .frame(width: 420, height: 320, alignment: .center)
}

#Preview("No combatants") {
    BattleRoundEmptyState(isRunning: true, start: {})
        .frame(width: 420, height: 320, alignment: .center)
}
