// @copyright André Trettin

import CoreRPG
import SwiftUI

struct DiceGameResult: View {
    let itemId: UUID
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
        .animation(Animation.spring().reduced(if: reduceMotion), value: diceDisplayModel.showDiceValueEditor)
        .onChange(of: diceDisplayModel.isEditing) {
            guard diceDisplayModel.isEditing else { return }
            withAnimation(Animation.default.reduced(if: reduceMotion)) {
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
        // Looked up once per evaluation; the result was computed up to four times. See §7.61.
        let gameItem = root.gameController.gameItem(for: itemId)
        if gameItem.sumUp || gameItem.compareOption != .off {
            let result = root.gameController.result(itemId: itemId)
            Button {
                if canEditResult {
                    diceDisplayModel.showDiceValueEditor.toggle()
                    diceDisplayModel.showPlayerDice = !diceDisplayModel.showDiceValueEditor
                    diceDisplayModel.isEditing <=> false
                }
            } label: {
                Label {
                    // The result changes inside the roll's animation. Without this the old and the
                    // new text cross-fade on top of each other, and as they differ in length their
                    // two ✅ stand apart with the digits between them faded out.
                    Text(root.gameController.resultText(itemId: itemId).markDown())
                        .contentTransition(.identity)
                } icon: {
                    Image(systemName: result.checked ? "checkmark" : "xmark")
                }
            }
            .disabled(!canEditResult)
            .gameOverlayCapsuleControlStyle(
                isSelected: result.checked
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
        DiceGameResult(itemId: DiceModel.previewId, isTrailing: false)
            .environment(DiceRootModel.preview)
            .environment(DiceDisplayModel())
            .environment(AppGameStateModel())
    }
    .frame(width: 120)
    .padding()
}
