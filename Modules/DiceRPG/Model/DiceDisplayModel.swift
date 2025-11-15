// @copyright André Trettin

import CoreRPG
import SwiftUI

@Observable
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

    @State private var itemId = UUID()
    
    var body: some View {
        DiceOverlay(item: ItemRowModel(itemId: itemId, typeId: root.itemController.module), showFocusButton: false, canShowPlayer: false, hideOwnDice: false, alignIsVertical: false)
            .onChange(of: root.gameController.gameModel.focusItemIds, initial: true) {
                withAnimation { itemId <=> root.gameController.gameModel.focusItemIds.first ?? UUID() }
            }
    }
}

struct DiceFocusActionBar: View {
    @Environment(DiceRootModel.self) private var root

    @State private var itemId = UUID()

    var body: some View {
        DiceGameActionBar(itemId: itemId, showFocusButton: false, canShowPlayer: false, hideOwnDice:false)
            .onChange(of: root.gameController.gameModel.focusItemIds, initial: true) {
                withAnimation { itemId <=> root.gameController.gameModel.focusItemIds.first ?? UUID() }
            }
    }
}

struct DiceFocusResult: View {
    @Environment(DiceRootModel.self) private var root

    @State private var itemId = UUID()

    var body: some View {
        DiceGameResult(itemId: itemId, canShowPlayer: false, isTrailing: true)
            .onChange(of: root.gameController.gameModel.focusItemIds, initial: true) {
                withAnimation { itemId <=> root.gameController.gameModel.focusItemIds.first ?? UUID() }
            }
    }
}


//#Preview {
//    DiceFocusRoll()
//        .environment(DiceRootModel.previewWithData)
//}
//
