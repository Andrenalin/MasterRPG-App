// @copyright André Trettin

import MapRPG
import SwiftUI

struct BattleInitiativeOrderMenu: View {
    @Binding var selection: BattleInitiativeOrder

    var body: some View {
        Picker(
            String(localized: "Initiative Order", bundle: .module),
            selection: $selection
        ) {
            Label {
                Text("Descending", bundle: .module)
            } icon: {
                Image(systemName: "arrow.down")
            }
            .tag(BattleInitiativeOrder.descending)

            Label {
                Text("Ascending", bundle: .module)
            } icon: {
                Image(systemName: "arrow.up")
            }
            .tag(BattleInitiativeOrder.ascending)
        }
        .pickerStyle(.menu)
        .labelsHidden()
    }
}

#Preview("Initiative order") {
    @Previewable @State var selection = BattleInitiativeOrder.descending

    BattleInitiativeOrderMenu(selection: $selection)
        .padding()
}
