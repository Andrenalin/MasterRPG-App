// @copyright André Trettin

import CoreRPG
import SwiftUI

//#if !os(tvOS)
//var shortcut: INShortcut {
//    let activity = NSUserActivity(activityType: "\(URL.appScheme)://\(NetworkModules.dice.token)/")
//    activity.title = "Display my favorite Dice"
//    activity.suggestedInvocationPhrase = "Show favorite dice"
//    activity.userInfo = ["itemId": itemId]
//
//    return INShortcut(userActivity: activity)
//}
//#endif

struct RootDiceOverlay: View {
    let hideDice: Bool

    @Environment(DiceRootModel.self) private var root

    @State private var itemId: UUID = UUID()

    var body: some View {
        DiceOverlay(item: ItemRowModel(itemId: itemId, typeId: root.itemController.module), showFocusButton: false, hideOwnDice: valueFor(iOS: false, macOS: false, tvOS: false, visionOS: true))
        .onChange(of: root.gameController.gameModel.focusItemIds, initial: true) {
            withAnimation { itemId <=> root.gameController.gameModel.focusItemIds.first ?? UUID() }
        }
    }
}

#Preview(traits: .mockData) {
    Color.red.opacity(0.3).ignoresSafeArea()
        .overlay {
            RootDiceOverlay(hideDice: false)
        }
        .environment(\.gameModus, .player)
        .environment(DiceDisplayModel())
}
