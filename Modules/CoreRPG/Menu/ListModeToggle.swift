// @copyright André Trettin

import SwiftUI

struct ListModeToggle: View {
    let listDisplayModel: ListDisplayModel

    var body: some View {
        @Bindable var listDisplayModel = listDisplayModel
        Toggle(isOn: $listDisplayModel.isListMode) {
            Label {
                Text("List", bundle: .module)
            } icon: {
                Image(systemName: "list.bullet")
            }
        }
#if !os(tvOS)
        .keyboardShortcut("L", modifiers: [.command, .shift])
#endif
    }
}

#Preview { ListModeToggle(listDisplayModel: ListDisplayModel()) }
