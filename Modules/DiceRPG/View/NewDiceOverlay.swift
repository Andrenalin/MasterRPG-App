//// @copyright André Trettin
//
//import CoreRPG
//import SwiftUI
//
//struct DiceOverlay: View {
//    let item: ItemRowModel
//    var showFocusButton = true
//    var canShowPlayer = true
//    var hideOwnDice = false
//    var alignIsVertical = true
//
//    @Environment(DiceRootModel.self) private var root
//
//    @Environment(\.gameModus) private var gameModus
//    @Environment(\.networkActions) private var networkActions
//    @Environment(DiceDisplayModel.self) var diceDisplayModel
//
//    @State private var overlayHeight: CGFloat = 100
//
//    var itemId: UUID {
//        item.entryId ?? item.itemId
//    }
//
//    var body: some View {
//        AnyLayout(diceLayout) {
//            diceViews
//        }
//        .animation(.spring(), value: diceDisplayModel.showDiceValueEditor)
//        .onChange(of: diceDisplayModel.isEditing) {
//            guard diceDisplayModel.isEditing else { return }
//            withAnimation { diceDisplayModel.showDiceValueEditor <=> false }
//        }
//        .onAppear {
//            withAnimation {
//                if canShowPlayer && !root.gameController.gameModel.items.isEmpty {
//                    diceDisplayModel.showPlayerDice <=> true
//                }
//            }
//        }
//    }
//
//    var diceLayout: any Layout {
//        alignIsVertical ? VStackLayout(alignment: .leading, spacing: 8) : HStackLayout(alignment: .top, spacing: 8)
//    }
//
//    @ViewBuilder
//    var diceViews: some View {
//        if alignIsVertical {
//            actionBarView
//        }
//
//        ownDiceView
//
//        playerDiceView
//    }
//
//    private var actionBarView: some View {
//        DiceGameActionBar(itemId: itemId, showFocusButton: showFocusButton, canShowPlayer: canShowPlayer, hideOwnDice: hideOwnDice)
//    }
//
//    @ViewBuilder
//    private var ownDiceView: some View {
//        if !hideOwnDice {
//            if alignIsVertical {
//                DiceGameResult(itemId: itemId, canShowPlayer: canShowPlayer, isTrailing: false)
//            }
//
//            if diceDisplayModel.isEditing {
//                DiceInlineEditor(itemId: itemId)
//            } else {
//                if !diceDisplayModel.showDiceValueEditor {
//                    DiceRoll(itemId: itemId)
//                }
//            }
//        }
//    }
//
//    @ViewBuilder
//    private var playerDiceView: some View {
//        if canShowPlayer && diceDisplayModel.showPlayerDice {
//            DicePlayer(filterout: itemId, alignment: .leading)
//        }
//    }
//}
//
//#Preview(traits: .mockData) {
//    ZStack(alignment: .topLeading) {
//        DiceOverlay(item: ItemRowModel(itemId: MockData.previewId, typeId: .dice))
//            .environment(\.gameModus, .master)
//            .environment(DiceDisplayModel())
//    }
//}
