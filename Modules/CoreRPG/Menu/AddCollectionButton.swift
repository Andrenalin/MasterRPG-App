// @copyright André Trettin

import SwiftUI

#if !os(tvOS)
struct AddCollectionButton: View {
    let root: any ItemRootControllable
    let routeActions: RouteActions
    let key: AKKeyEquivalent

    var body: some View {
        Button {
            Task {
                guard let item = await root.editControllable.addNew(type: .collection) else { return }
                routeActions.routePage(root.configurable.module, item.id, nil)
            }
        } label: {
            Label {
                Text(EditControllerAddType.collection.title)
            } icon: {
                Image(systemName: EditControllerAddType.collection.icon(collection: root.itemControllable.collectionCategory.icon))
            }
        }
        .keyboardShortcut(key, modifiers: [.command, .control, .option])
        .disabled(root.folderListControllable.listDisplayModel.isListMode)
    }
}

#Preview {
    AddCollectionButton(root: ItemRootController.fake, routeActions: RouteActions { _, _, _ in }, key: "n")
}
#endif
