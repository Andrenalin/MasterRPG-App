// @copyright André Trettin

import SwiftUI
import TipKit

#if !os(tvOS)
struct AddItemButton: View {
    let root: any ItemRootControllable
    let routeActions: RouteActions

    var body: some View {
        Button {
            Task {
                guard let item = await root.editControllable.addNew(type: .item) else { return }
                routeActions.routePage(root.configurable.module, item.id, nil)
                await MasterRPGTips.donateItemCreated()
            }
        } label: {
            Label { Text("New \(root.configurable.module.title)", bundle: .module) } icon: { Image(systemName: "plus") }
        }
        .keyboardShortcut("n", modifiers: .command)
        .popoverTip(MasterRPGTips.firstItem)
    }
}

#Preview {
    AddItemButton(root: ItemRootController.fake, routeActions: RouteActions { _, _, _ in })
}
#endif
