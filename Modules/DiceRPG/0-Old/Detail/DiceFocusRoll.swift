// @copyright André Trettin

import CoreRPG
import SwiftUI

@MainActor @Observable
public final class DiceDisplayModel {
    public init(isEditing: Bool = false, showPlayerDice: Bool = false, showDiceValueEditor: Bool = false) {
        self.isEditing = isEditing
        self.showPlayerDice = showPlayerDice
        self.showDiceValueEditor = showDiceValueEditor
    }

    public var isEditing: Bool
    public var showPlayerDice: Bool
    public var showDiceValueEditor: Bool
}

struct DiceFocusRoll: View {
    @Environment(DiceRootModel.self) private var root
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var itemId = UUID()
    
    var body: some View {
        DiceOverlay(item: ItemRowTreeModel(itemId: itemId, typeId: root.itemController.config.module), showFocusButton: false, canShowPlayer: false, hideOwnDice: false, alignIsVertical: false)
            .onChange(of: root.gameController.gameModel.focusItemIds, initial: true) {
                withAnimation(reduceMotion ? nil : .default) {
                    itemId <=> root.gameController.gameModel.focusItemIds.first ?? UUID()
                }
            }
    }
}

#Preview(traits: .mockData) {
    DiceFocusRoll()
        .environment(DiceDisplayModel())
}
