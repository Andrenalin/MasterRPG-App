// @copyright André Trettin

import SwiftUI

struct MenuSelectionButtonView: View {
    let listModel: ListModel
    
    var body: some View {
        Button {
            withAnimation { listModel.toogleSelectionMode() }
       } label: {
            Label {
                Text("Select", bundle: .module)
            } icon: {
                Image(systemName: "checkmark.circle")
            }
       }
       .keyboardShortcut("S", modifiers: [.command, .shift])
    }
}
