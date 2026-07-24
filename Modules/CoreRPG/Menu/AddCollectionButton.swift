// @copyright André Trettin

import SwiftUI

#if !os(tvOS)
struct AddCollectionButton: View {
    let root: any ItemRootControllable
    let routeActions: RouteActions

    var body: some View {
        Button {
            Task {
                guard let item = await root.editControllable.addNew(type: .collection) else { return }
                routeActions.routePage(root.configurable.module, item.id, nil)
            }
        } label: {
            Label {
                Text("New Collection in \(root.configurable.module.title)", bundle: .module)
            } icon: {
                Image(systemName: EditControllerAddType.collection.icon(collection: root.itemControllable.collectionCategory.icon))
            }
        }
        .keyboardShortcut("n", modifiers: [.command, .shift, .option])
        .disabled(root.folderListControllable.listDisplayModel.isListMode)
    }
}

#Preview {
    AddCollectionButton(root: ItemRootController.fake, routeActions: RouteActions { _, _, _ in })
}
#endif
