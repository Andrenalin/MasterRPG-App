// @copyright André Trettin

import CoreRPG
import SwiftUI

struct DiceGameResult: View {
    let itemId: UUID
    let canShowPlayer: Bool
    let isTrailing: Bool

    @Environment(DiceRootModel.self) private var root

    @Environment(\.networkActions) private var networkActions
    @Environment(DiceDisplayModel.self) var diceDisplayModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: isTrailing ? .trailing : .leading) {
            DiceGameResultResultView(itemId: itemId)
            if diceDisplayModel.showDiceValueEditor {
                DiceQuickEditor(itemId: itemId) { newValue in
                    await root.gameController.resetCompareValue(of: itemId, value: newValue)
                    diceDisplayModel.showDiceValueEditor.toggle()
                    diceDisplayModel.showPlayerDice = !diceDisplayModel.showDiceValueEditor
                }
            }
        }
        .animation(reduceMotion ? nil : .spring(), value: diceDisplayModel.showDiceValueEditor)
        .onChange(of: diceDisplayModel.isEditing) {
            guard diceDisplayModel.isEditing else { return }
            withAnimation(reduceMotion ? nil : .default) {
                diceDisplayModel.showDiceValueEditor <=> false
            }
        }
    }
}

// MARK: - Extracted subviews (CODE_AUDIT §8.3)

private struct DiceGameResultResultView: View {
    let itemId: UUID

    @Environment(DiceRootModel.self) private var root
    @Environment(AppGameStateModel.self) private var appGameStateModel
    @Environment(DiceDisplayModel.self) var diceDisplayModel

    @ViewBuilder
    var body: some View {
        if root.gameController.gameItem(for: itemId).sumUp || root.gameController.gameItem(for: itemId).compareOption != .off {
            Button {
                if canEditResult {
                    diceDisplayModel.showDiceValueEditor.toggle()
                    diceDisplayModel.showPlayerDice = !diceDisplayModel.showDiceValueEditor
                    diceDisplayModel.isEditing <=> false
                }
            } label: {
                Label {
                    Text(root.gameController.resultText(itemId: itemId).markDown())
                } icon: {
                    Image(systemName: root.gameController.result(itemId: itemId).checked ? "checkmark" : "xmark")
                }
            }
            .disabled(!canEditResult)
            .gameOverlayCapsuleControlStyle(
                isSelected: root.gameController.result(itemId: itemId).checked
            )
        }
    }

    private var canEditResult: Bool {
        appGameStateModel.isGameRunning
        && root.gameController.canEditDice(itemId: itemId, isGameMode: true)
    }
}

#Preview {
    ZStack(alignment: .topLeading) {
        DiceGameResult(itemId: DiceModel.previewId, canShowPlayer: true, isTrailing: false)
            .environment(DiceRootModel.preview)
            .environment(DiceDisplayModel())
    }
}
