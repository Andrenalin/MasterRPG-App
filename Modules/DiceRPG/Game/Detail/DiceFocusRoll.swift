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

    var body: some View {
        FocusedDiceContainer { itemId in
            DiceOverlay(item: ItemRowTreeModel(itemId: itemId, typeId: root.itemController.config.module), showFocusButton: false, canShowPlayer: false, hideOwnDice: false, alignIsVertical: false)
        }
    }
}

#Preview(traits: .mockData) {
    DiceFocusRoll()
        .environment(DiceDisplayModel())
}
