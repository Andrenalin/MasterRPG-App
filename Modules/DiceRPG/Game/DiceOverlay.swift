// @copyright André Trettin

import CoreRPG
import SwiftUI

struct DiceOverlay: View {
    let item: ItemRowTreeModel
    var showFocusButton = true
    var canShowPlayer = true
    var hideOwnDice = false
    var alignIsVertical = true

    @Environment(DiceDisplayModel.self) var diceDisplayModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var itemId: UUID {
        item.model.entryId ?? item.model.itemId
    }

    var body: some View {
        AnyLayout(diceLayout) {
            DiceOverlayDiceViewsView(alignIsVertical: alignIsVertical, itemId: itemId, showFocusButton: showFocusButton, canShowPlayer: canShowPlayer, hideOwnDice: hideOwnDice)
        }
        .animation(Animation.spring().reduced(if: reduceMotion), value: diceDisplayModel.showDiceValueEditor)
        .onChange(of: diceDisplayModel.isEditing) {
            guard diceDisplayModel.isEditing else { return }
            withAnimation(Animation.default.reduced(if: reduceMotion)) {
                diceDisplayModel.showDiceValueEditor <=> false
            }
        }
    }

    var diceLayout: any Layout {
        alignIsVertical ? VStackLayout(alignment: .leading, spacing: 8) : HStackLayout(alignment: .top, spacing: 8)
    }
}

// MARK: - Extracted subviews (CODE_AUDIT §8.3)

private struct DiceOverlayDiceViewsView: View {
    let alignIsVertical: Bool
    let itemId: UUID
    let showFocusButton: Bool
    let canShowPlayer: Bool
    let hideOwnDice: Bool

    @ViewBuilder
    var body: some View {
        if alignIsVertical {
            DiceOverlayActionBarView(itemId: itemId, showFocusButton: showFocusButton, canShowPlayer: canShowPlayer, hideOwnDice: hideOwnDice)
        }

        DiceOverlayOwnDiceView(itemId: itemId, hideOwnDice: hideOwnDice, alignIsVertical: alignIsVertical)

        DiceOverlayPlayerDiceView(itemId: itemId, canShowPlayer: canShowPlayer)
    }
}

private struct DiceOverlayActionBarView: View {
    let itemId: UUID
    let showFocusButton: Bool
    let canShowPlayer: Bool
    let hideOwnDice: Bool

    var body: some View {
        DiceGameActionBar(itemId: itemId, showFocusButton: showFocusButton, canShowPlayer: canShowPlayer, hideOwnDice: hideOwnDice)
    }
}

private struct DiceOverlayOwnDiceView: View {
    let itemId: UUID
    let hideOwnDice: Bool
    let alignIsVertical: Bool

    @Environment(DiceDisplayModel.self) var diceDisplayModel

    @ViewBuilder
    var body: some View {
        if !hideOwnDice {
            if alignIsVertical {
                DiceGameResult(itemId: itemId, isTrailing: false)
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
}

private struct DiceOverlayPlayerDiceView: View {
    let itemId: UUID
    let canShowPlayer: Bool

    @Environment(DiceDisplayModel.self) var diceDisplayModel

    @ViewBuilder
    var body: some View {
        if canShowPlayer && diceDisplayModel.showPlayerDice {
            DicePlayer(alignment: .leading)
        }
    }
}

#Preview(traits: .mockData) {
    ZStack(alignment: .topLeading) {
        DiceOverlay(item: .preview)
            .environment(DiceDisplayModel(isEditing: true, showPlayerDice: false, showDiceValueEditor: false))
    }
}
