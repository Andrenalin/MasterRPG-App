// @copyright André Trettin

import MapRPG
import CoreRPG
import SwiftUI

struct BattleRoundWindowView: View {
    let root: GameRoot

    @Environment(ScenesManager.self) private var scenesManager

    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()
        if root.gameModel.gameConfig.isMaster {
            BattleRoundView(controller: root.battleRoundController, layout: .wide)
                .environment(root.mapRoot)
                .onChange(of: root.battleRoundController.model.isRunning) { wasRunning, isRunning in
                    guard wasRunning, !isRunning else { return }
                    scenesManager.dismissWindow(.battleRound)
                }
        } else {
            ContentUnavailableView {
                Label {
                    Text("Game Master Only", bundle: .module)
                } icon: {
                    Image(systemName: "lock.fill")
                }
            } description: {
                Text("Only the game master can manage battle rounds.", bundle: .module)
            }
        }
    }
}

#Preview(traits: .mockData) {
    BattleRoundWindowView(root: .previewFixture())
}
