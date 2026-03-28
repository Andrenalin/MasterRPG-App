// @copyright André Trettin

import SwiftUI
import GroupActivities

struct GameTableToolbar: ToolbarContent {
    let game: GameTableModel
    
    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .bottomOrnament) {
            Button("Reset", systemImage: "arrow.counterclockwise") {
                game.resetGame()
            }
            Spacer()
            Button("SharePlay", systemImage: "shareplay") {
               Task {
                    try! await RPGActivity().activate()
               }
            }
        }
    }
}
