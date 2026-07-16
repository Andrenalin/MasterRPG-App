// @copyright André Trettin

import SwiftUI

#if !os(tvOS)
struct AddFolderButton: View {
    let root: any ItemRootControllable
    let routeActions: RouteActions
    let key: AKKeyEquivalent

    var body: some View {
        Button {
            Task {
                guard let item = await root.editControllable.addNew(type: .folder) else { return }
                routeActions.routePage(root.configurable.module, item.id, nil)
            }
        } label: {
            Label {
                Text(EditControllerAddType.folder.title)
            } icon: {
                Image(systemName: EditControllerAddType.folder.icon(collection: root.itemControllable.collectionCategory.icon))
            }
        }
        .keyboardShortcut(key, modifiers: [.command, .control, .shift])
        .disabled(root.folderListControllable.listDisplayModel.isListMode)
    }
}

#Preview {
    AddFolderButton(root: ItemRootController.fake, routeActions: RouteActions { _, _, _ in }, key: "n")
}
#endif
