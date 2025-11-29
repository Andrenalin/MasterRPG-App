// @copyright André Trettin

import CoreExternalRPG
import SwiftUI

public protocol ItemDetailRoute: NavigationDestination {
    func detail() -> UUID?
    func reset(detail: UUID) -> Self
    
}

public extension View {
    func applyItemRootRoute<Route: ItemDetailRoute>(listControllable: any FolderListControllable, route: Binding<Route?>) -> some View {
        modifier(ItemRootRouteViewModifier(listControllable: listControllable, route: route))
    }
}

struct ItemRootRouteViewModifier<Route: ItemDetailRoute>: ViewModifier {
    let listControllable: any FolderListControllable
    let route: Binding<Route?>

    func body(content: Content) -> some View {
        content
            .onChange(of: listControllable.listModel.itemRoute) {
                if let selected = listControllable.listModel.itemRoute {
                    route.wrappedValue <=> route.wrappedValue?.reset(detail: selected)
                } else {
                    route.wrappedValue <=> nil
                }
            }
            .onChange(of: route.wrappedValue, initial: true) {
                if let itemId = route.wrappedValue?.detail() {
                    if listControllable.listModel.selectedItemId != itemId {
                        listControllable.listModel.set(selectedItemId: itemId)
                    }
                } else {
                    if listControllable.listModel.selected != nil {
                        listControllable.listModel.update(selection: Set())
                    }
                }
            }
            .onNavigationReceive { (route: Route, navigator) in
                guard let itemId = route.detail() else { return .auto }
                if listControllable.listModel.selectedItemId == itemId {
                    return .immediately
                }
                listControllable.listModel.set(selectedItemId: itemId)
                return .auto
            }
    }
}
