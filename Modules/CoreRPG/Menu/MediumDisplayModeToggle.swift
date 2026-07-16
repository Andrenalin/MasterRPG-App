// @copyright André Trettin

import SwiftUI

struct MediumDisplayModeToggle: View {
    let listDisplayModel: ListDisplayModel

    var body: some View {
        @Bindable var listDisplayModel = listDisplayModel
        Toggle(isOn: $listDisplayModel.isMediumDisplayMode) {
            Label {
                Text("Medium", bundle: .module)
            } icon: {
                Image(systemName: "list.bullet.rectangle")
            }
        }
#if !os(tvOS)
        .keyboardShortcut("M", modifiers: [.command, .shift])
#endif
    }
}

#Preview { MediumDisplayModeToggle(listDisplayModel: ListDisplayModel()) }
