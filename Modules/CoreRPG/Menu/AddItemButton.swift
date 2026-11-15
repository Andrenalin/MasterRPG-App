// @copyright André Trettin

import SwiftUI

#if !os(tvOS)
struct AddItemButton: View {
    let root: any ItemRootControllable
    let routeActions: RouteActions

    /// Ignores a second press while an item is being created.
    @State private var isCreating = false

    var body: some View {
        Button {
            addItemAndRoute(type: .item, root: root, routeActions: routeActions, isCreating: $isCreating) {
                await MasterRPGTips.donateItemCreated()
            }
        } label: {
            Label { Text("New \(root.configurable.module.title)", bundle: .module) } icon: { Image(systemName: "plus") }
        }
        .keyboardShortcut("n", modifiers: .command)
        .disabled(isCreating)
    }
}

#Preview {
    AddItemButton(root: ItemRootController.fake, routeActions: RouteActions { _, _, _ in })
}
#endif
