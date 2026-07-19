// @copyright André Trettin

import CoreRPG
import SwiftUI

struct DiceOverlay: View {
    let item: ItemRowTreeModel
    var showFocusButton = true
    var canShowPlayer = true
    var hideOwnDice = false
    var alignIsVertical = true

    @Environment(DiceRootModel.self) private var root

    @Environment(AppGameStateModel.self) private var appGameStateModel
    @Environment(\.networkActions) private var networkActions
    @Environment(DiceDisplayModel.self) var diceDisplayModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var overlayHeight: CGFloat = 100

    var itemId: UUID {
        item.model.entryId ?? item.model.itemId
    }

    var body: some View {
        AnyLayout(diceLayout) {
            diceViews
        }
        .animation(reduceMotion ? nil : .spring(), value: diceDisplayModel.showDiceValueEditor)
        .onChange(of: diceDisplayModel.isEditing) {
            guard diceDisplayModel.isEditing else { return }
            withAnimation(reduceMotion ? nil : .default) {
                diceDisplayModel.showDiceValueEditor <=> false
            }
        }
    }

    var diceLayout: any Layout {
        alignIsVertical ? VStackLayout(alignment: .leading, spacing: 8) : HStackLayout(alignment: .top, spacing: 8)
    }

    @ViewBuilder
    var diceViews: some View {
        if alignIsVertical {
            actionBarView
        }

        ownDiceView

        playerDiceView
    }

    private var actionBarView: some View {
        DiceGameActionBar(itemId: itemId, showFocusButton: showFocusButton, canShowPlayer: canShowPlayer, hideOwnDice: hideOwnDice)
    }

    @ViewBuilder
    private var ownDiceView: some View {
        if !hideOwnDice {
            if alignIsVertical {
                DiceGameResult(itemId: itemId, canShowPlayer: canShowPlayer, isTrailing: false)
            }

            if diceDisplayModel.isEditing {
                DiceInlineEditor(itemId: itemId)
            } else {
                if !diceDisplayModel.showDiceValueEditor {
                    DiceRoll(itemId: itemId)
                }
            }
        }
    }

    @ViewBuilder
    private var playerDiceView: some View {
        if canShowPlayer && diceDisplayModel.showPlayerDice {
            DicePlayer(filterout: itemId, alignment: .leading)
        }
    }
}

#Preview(traits: .mockData) {
    ZStack(alignment: .topLeading) {
        DiceOverlay(item: .preview)
            .environment(DiceDisplayModel(isEditing: true, showPlayerDice: false, showDiceValueEditor: false))
    }
}
