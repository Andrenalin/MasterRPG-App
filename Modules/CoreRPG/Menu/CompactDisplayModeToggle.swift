// @copyright André Trettin

import SwiftUI

struct CompactDisplayModeToggle: View {
    let listDisplayModel: ListDisplayModel

    var body: some View {
        @Bindable var listDisplayModel = listDisplayModel
        Toggle(isOn: $listDisplayModel.isCompactDisplayMode) {
            Label {
                Text("Compact", bundle: .module)
            } icon: {
                Image(systemName: "list.dash.header.rectangle")
            }
        }
#if !os(tvOS)
        .keyboardShortcut("C", modifiers: [.command, .shift])
#endif
    }
}

#Preview { CompactDisplayModeToggle(listDisplayModel: ListDisplayModel()) }
