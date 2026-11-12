// @copyright André Trettin

import SwiftUI

/// Starts the generation of an item (a Table) from a sheet header, in place of the share button.
/// The sheet's host provides the presentation through `itemGenerationAction`.
struct ItemGenerateButton: View {
    let root: any ItemRootControllable
    let itemId: UUID

    @Environment(\.itemGenerationAction) private var itemGenerationAction

    var body: some View {
        if itemGenerationAction.isEnabled {
            Button {
                itemGenerationAction(itemId)
            } label: {
                Label { Text("Generate", bundle: .module) } icon: { Image(systemName: "gear") }
            }
            .selectedRoundButton(title: String(localized: "Generate", bundle: .module), module: root.configurable.module, isSelected: false)
        }
    }
}
