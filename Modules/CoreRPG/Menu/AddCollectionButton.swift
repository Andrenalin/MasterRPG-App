// @copyright André Trettin

import SwiftUI

#if !os(tvOS)
struct AddCollectionButton: View {
    let root: any ItemRootControllable
    let routeActions: RouteActions

    /// Ignores a second press while a collection is being created.
    @State private var isCreating = false

    var body: some View {
        Button {
            addItemAndRoute(type: .collection, root: root, routeActions: routeActions, isCreating: $isCreating) {
                await MasterRPGTips.donateContentOrganized()
            }
        } label: {
            Label {
                Text("New Collection in \(root.configurable.module.title)", bundle: .module)
            } icon: {
                Image(systemName: EditControllerAddType.collection.icon(collection: root.itemControllable.collectionCategory.icon))
            }
        }
        .keyboardShortcut("n", modifiers: [.command, .shift, .option])
        .disabled(root.folderListControllable.listDisplayModel.isListMode || isCreating)
    }
}

#Preview {
    AddCollectionButton(root: ItemRootController.fake, routeActions: RouteActions { _, _, _ in })
}
#endif
