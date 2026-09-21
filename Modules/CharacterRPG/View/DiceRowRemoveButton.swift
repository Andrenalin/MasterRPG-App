// @copyright André Trettin

import CoreRPG
import SwiftUI

/// The red/white minus used throughout the sheet for deleting entries
/// (`SheetEntryDeleteButton`), placed at the end of a dice row to unlink the
/// entry's `diceId` without deleting the entry itself.
struct DiceRowRemoveButton: View {
    let itemId: UUID
    let entryId: UUID

    @Environment(CharacterRootModel.self) private var root
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(role: .destructive, action: removeDice) {
            Label {
                Text("Remove Dice", bundle: .module)
            } icon: {
                Image(systemName: "minus.circle.fill")
                    .imageScale(.large)
                    .foregroundStyle(.white, .red, .red)
            }
            .labelStyle(.iconOnly)
        }
        .foregroundStyle(.white, .red, .red)
        .borderLessTVButtonStyle()
        .frame(minWidth: 44, minHeight: 44)
        .help(Text("Remove Dice", bundle: .module))
    }

    private func removeDice() {
        withAnimation(reduceMotion ? nil : .default) {
            root.editController.removeDice(itemId: itemId, entryId: entryId)
        }
    }
}

#Preview {
    DiceRowRemoveButton(itemId: ValueModel.previewId, entryId: UUID())
        .environment(CharacterRootModel.preview)
        .padding()
}
