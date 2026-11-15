// @copyright André Trettin

import SwiftUI

#if !os(tvOS)
/// The shared tail of the Add Item, Add Folder and Add Collection buttons: ignore a second
/// press while an add is in flight, create the item, route to it and refresh the tips.
/// See CODE_AUDIT_26 §5.70.
@MainActor
func addItemAndRoute(
    type: EditControllerAddType,
    root: any ItemRootControllable,
    routeActions: RouteActions,
    isCreating: Binding<Bool>,
    donate: @escaping @MainActor () async -> Void
) {
    guard !isCreating.wrappedValue else { return }
    isCreating.wrappedValue = true
    Task {
        defer { isCreating.wrappedValue = false }
        guard let item = await root.editControllable.addNew(type: type) else { return }
        routeActions.routePage(root.configurable.module, item.id, nil)
        await donate()
        if let rootManager = root.rootManager {
            MasterRPGTips.refreshEligibility(rootManager: rootManager)
        }
    }
}
#endif
