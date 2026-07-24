// @copyright André Trettin

import SwiftUI

struct BattleRoundEmptyState: View {
    let isRunning: Bool
    let start: @MainActor () -> Void

    var body: some View {
        ContentUnavailableView {
            Label {
                Text(isRunning ? "No Combatants" : "No Battle Running", bundle: .module)
            } icon: {
                Image(systemName: "shield.lefthalf.filled")
            }
        } description: {
            Text(
                isRunning
                    ? "The selected map has no player or active-room combatants."
                    : "Start a battle with player pins and the monsters in the selected room.",
                bundle: .module
            )
        } actions: {
            if !isRunning {
                Button("Start Battle", systemImage: "play.fill", action: start)
                    .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview("No battle") {
    BattleRoundEmptyState(isRunning: false, start: {})
        .frame(width: 420, height: 320)
}

#Preview("No combatants") {
    BattleRoundEmptyState(isRunning: true, start: {})
        .frame(width: 420, height: 320)
}
