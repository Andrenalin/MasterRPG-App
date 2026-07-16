// @copyright André Trettin

import SwiftUI

struct FolderModeToggle: View {
    let listDisplayModel: ListDisplayModel

    var body: some View {
        @Bindable var listDisplayModel = listDisplayModel
        Toggle(isOn: $listDisplayModel.isFolderMode) {
            Label {
                Text("Folder", bundle: .module)
            } icon: {
                Image(systemName: "folder")
            }
        }
#if !os(tvOS)
        .keyboardShortcut("F", modifiers: [.command, .shift])
#endif
    }
}

#Preview { FolderModeToggle(listDisplayModel: ListDisplayModel()) }
