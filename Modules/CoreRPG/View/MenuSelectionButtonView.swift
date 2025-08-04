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
#if !os(tvOS)
       .keyboardShortcut("S", modifiers: [.command, .shift])
#endif
    }
}
