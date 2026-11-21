// @copyright André Trettin

#if os(visionOS)
import CoreRPG
import DiceRPG
import MapRPG
import SwiftUI

// The dice edit mode's popovers on the 3D table, as attachments of the volume: the dice bag over
// the seat's dice, and one remove popover per die. Both are the same popover as the dice
// result's, and only exist while `DiceDisplayModel.isEditing` is on.

/// The dice bag popover: the dice to add, the button that closes the edit mode and the one that
/// rolls.
@MainActor
struct GameDiceBagPopover: View {
    static let attachmentId = "dice-bag"

    let root: GameRoot
    let game: GameTableModel
    let diceDisplayModel: DiceDisplayModel
    let appGameStateModel: AppGameStateModel?
    let networkActions: NetworkActions?

    @Environment(\.physicalMetrics) private var physicalMetrics
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if diceDisplayModel.isEditing {
                game.mapRoot.viewController.tablePopoverLabel(isInteractive: true) {
                    root.diceRoot.viewController.diceTableBagView(
                        root: root.diceRoot,
                        supportedSides: Set(TableDieKind.allCases.map(\.sides)),
                        poolSize: GameSetup.maxDicePerType
                    )
                    .padding(MapPopoverLayout.contentInset)
                }
                .environment(diceDisplayModel)
                .environment(appGameStateModel)
                .environment(\.networkActions, networkActions)
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.height
                } action: { height in
                    game.diceBagHeightChanged(Float(physicalMetrics.convert(height, to: .meters)))
                }
                .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .default, value: diceDisplayModel.isEditing)
    }
}

/// The remove popover over the `index`th die of the seat's row.
@MainActor
struct GameDiceRemovePopover: View {
    static func attachmentId(at index: Int) -> String { "dice-remove-\(index)" }

    let root: GameRoot
    let game: GameTableModel
    let diceDisplayModel: DiceDisplayModel
    let appGameStateModel: AppGameStateModel?
    let index: Int

    @Environment(\.physicalMetrics) private var physicalMetrics

    var body: some View {
        ZStack {
            if diceDisplayModel.isEditing, game.seatDiceSetIndices.indices.contains(index) {
                game.mapRoot.viewController.tablePopoverLabel(isInteractive: true) {
                    root.diceRoot.viewController.diceTableRemoveButtonView(
                        root: root.diceRoot,
                        setIndex: game.seatDiceSetIndices[index]
                    )
                    .padding(MapPopoverLayout.contentInset)
                }
                .environment(diceDisplayModel)
                .environment(appGameStateModel)
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.height
                } action: { height in
                    game.diceRemoveHeightChanged(Float(physicalMetrics.convert(height, to: .meters)), at: index)
                }
            }
        }
    }
}
#endif
