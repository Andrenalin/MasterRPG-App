// @copyright André Trettin

import SwiftUI

struct GeneratedSheetEntryContextMenu: View {
    let canRefine: Bool
    let takeOverAction: () -> Void
    let refineAction: () -> Void
    let deleteAction: () -> Void

    var body: some View {
        Button(action: takeOverAction) {
            Label {
                Text("Take Over", bundle: .module)
            } icon: {
                Image(systemName: "checkmark.circle.fill")
            }
        }

        Button(action: refineAction) {
            Label {
                Text("Refine with AI", bundle: .module)
            } icon: {
                Image(systemName: "sparkles")
            }
        }
        .disabled(!canRefine)

        Divider()

        Button(role: .destructive, action: deleteAction) {
            Label {
                Text("Delete", bundle: .module)
            } icon: {
                Image(systemName: "trash")
            }
        }
    }
}

#Preview("Generated Entry Menu") {
    GeneratedSheetEntryContextMenu(canRefine: true, takeOverAction: {}, refineAction: {}, deleteAction: {})
        .padding()
}
