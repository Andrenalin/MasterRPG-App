// @copyright André Trettin

import SwiftUI

struct MenuSelectionButtonView: View {
    let listDisplayModel: ListDisplayModel
    
    var body: some View {
        Button {
            withAnimation { listDisplayModel.isSelectionMode.toggle() }
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
