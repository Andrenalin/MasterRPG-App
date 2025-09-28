// @copyright André Trettin

import AndrenalinKit
import SwiftUI

struct DiceGameResult: View {
    let itemId: UUID
    let canShowPlayer: Bool
    let isTrailing: Bool

    @Environment(DiceRoot.self) private var root

    @Environment(\.gameModus) private var gameModus
    @Environment(\.networkActions) private var networkActions
    @Environment(DiceDisplayModel.self) var diceDisplayModel

    var body: some View {
        VStack(alignment: isTrailing ? .trailing : .leading) {
            resultView
            if diceDisplayModel.showDiceValueEditor {
                DiceQuickEditor(itemId: itemId) { newValue in
                    await root.gameController.resetCompareValue(of: itemId, value: newValue)
                    diceDisplayModel.showDiceValueEditor.toggle()
                    diceDisplayModel.showPlayerDice = !diceDisplayModel.showDiceValueEditor
                }
            }
        }
        .animation(.spring(), value: diceDisplayModel.showDiceValueEditor)
        .onChange(of: diceDisplayModel.isEditing) {
            guard diceDisplayModel.isEditing else { return }
            withAnimation { diceDisplayModel.showDiceValueEditor <=> false }
        }
    }

    @ViewBuilder
    private var resultView: some View {
        if root.gameController.gameItem(for: itemId).sumUp || root.gameController.gameItem(for: itemId).compareOption != .off {
            Button {
                if gameModus != .edit && root.gameController.canEditDice(itemId: itemId, isGameMode: true){
                    diceDisplayModel.showDiceValueEditor.toggle()
                    diceDisplayModel.showPlayerDice = !diceDisplayModel.showDiceValueEditor
                    diceDisplayModel.isEditing <=> false
                }
            } label: {
                Label("\(root.gameController.resultText(itemId: itemId).markDown())", systemImage: root.gameController.result(itemId: itemId).checked ? "checkmark" : "xmark")
            }
#if !os(tvOS)
            .buttonStyle(.borderedProminent)
#endif
        }
    }
}

#Preview {
    ZStack(alignment: .topLeading) {
        DiceGameResult(itemId: DiceModel.previewId, canShowPlayer: true, isTrailing: false)
            .environment(DiceRoot.preview)
            .environment(\.gameModus, .master)
            .environment(DiceDisplayModel())
    }
}
