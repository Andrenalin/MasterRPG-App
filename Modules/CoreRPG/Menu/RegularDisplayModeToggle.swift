// @copyright André Trettin

import SwiftUI

struct RegularDisplayModeToggle: View {
    let listDisplayModel: ListDisplayModel

    var body: some View {
        @Bindable var listDisplayModel = listDisplayModel
        Toggle(isOn: $listDisplayModel.isRegularDisplayMode) {
            Label {
                Text("Regular", bundle: .module)
            } icon: {
                Image(systemName: "list.bullet.below.rectangle")
            }
        }
#if !os(tvOS)
        .keyboardShortcut("R", modifiers: [.command, .shift])
#endif
    }
}

#Preview { RegularDisplayModeToggle(listDisplayModel: ListDisplayModel()) }
