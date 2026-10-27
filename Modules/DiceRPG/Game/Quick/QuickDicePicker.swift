// @copyright André Trettin

import CoreRPG
import SwiftUI

/// The dice list as a sheet, for choosing the base dice of a quick dice slot. The choice lands
/// in `selectionModel`; the window platforms drag from the dice link window instead.
struct QuickDicePicker: View {
    let selectionModel: ItemSelectionModel

    @Environment(DiceRootModel.self) private var root

    var body: some View {
        // The list brings its own navigation stack and toolbar.
        LinkRootView(type: .selection, itemSelectionModel: selectionModel)
            .environment(root)
    }
}

#Preview(traits: .mockData) {
    QuickDicePicker(selectionModel: ItemSelectionModel())
}
