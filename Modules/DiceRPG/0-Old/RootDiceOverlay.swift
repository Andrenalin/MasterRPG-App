// @copyright André Trettin

import CoreRPG
import SwiftUI

struct RootDiceOverlay: View {
    let hideDice: Bool

    @Environment(DiceRootModel.self) private var root

    @State private var itemId: UUID = UUID()

    var body: some View {
        DiceOverlay(item: ItemRowTreeModel(itemId: itemId, typeId: root.itemController.config.module), showFocusButton: false, hideOwnDice: valueFor(iOS: false, macOS: false, tvOS: false, visionOS: true))
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
