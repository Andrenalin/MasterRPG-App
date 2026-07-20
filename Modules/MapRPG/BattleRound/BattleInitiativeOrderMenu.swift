// @copyright André Trettin

import SwiftUI

struct BattleInitiativeOrderMenu: View {
    @Binding var selection: BattleInitiativeOrder
    let isDisabled: Bool

    var body: some View {
        Picker("Initiative Order", selection: $selection) {
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
        .disabled(isDisabled)
    }
}
