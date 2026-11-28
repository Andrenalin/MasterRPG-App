// @copyright André Trettin

import CoreRPG
import SwiftUI

/// The editor's dice drop target of an item (Adventure, Character, Table): shows the item's dice
/// and stores a newly chosen one through `setDice`. The three modules kept copies of this view.
/// See CODE_AUDIT_Edit_Save §9.6.
public struct DiceDropSelectionEditor: View {
    /// - Parameter setDice: stores the chosen dice; the editor persists also during a game, so
    ///   callers pass their setter with `forceSave: true`.
    public init(diceRoot: DiceRootModel, selection: ItemSelectionModel, diceId: UUID?, setDice: @escaping @MainActor (UUID?) -> Void) {
        self.diceRoot = diceRoot
        self.selection = selection
        self.diceId = diceId
        self.setDice = setDice
    }

    let diceRoot: DiceRootModel
    let selection: ItemSelectionModel
    let diceId: UUID?
    let setDice: @MainActor (UUID?) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public var body: some View {
        diceRoot.viewController.dropChooseView(model: selection)
            .onChange(of: selection.selection) {
                withAnimation(reduceMotion ? nil : .easeInOut) {
                    setDice(selection.itemId)
                }
            }
            .task(id: diceId) {
                selection.resetSelection(itemId: diceId, entryId: nil)
            }
    }
}
