// @copyright André Trettin

import CoreExternalRPG
import SwiftUI

extension View {
    func applyItemRootRoute(listControllable: any ListControllable, route: Binding<ItemRootRoute?>) -> some View {
        modifier(ItemRootRouteViewModifier(listControllable: listControllable, route: route))
    }
}

struct ItemRootRouteViewModifier: ViewModifier {
    let listControllable: any ListControllable
    let route: Binding<ItemRootRoute?>

    func body(content: Content) -> some View {
        content
            .onChange(of: listControllable.listModel.selected) {
                if let selected = listControllable.listModel.selectedItemId {
                    route.wrappedValue <=> .detail(selected)
                } else {
                    route.wrappedValue <=> nil
                }
            }
            .onChange(of: route.wrappedValue, initial: true) {
                if let route = route.wrappedValue {
                    switch route {
                        case .detail(let itemId):
                            if listControllable.listModel.selectedItemId != itemId {
                                listControllable.listModel.set(selectedItemId: itemId)
                            }
                    }
                } else {
                    listControllable.listModel.update(selection: Set())
                }
            }
            .onNavigationReceive { (route: ItemRootRoute, navigator) in
                switch route {
                    case .detail(let itemId):
                        if listControllable.listModel.selectedItemId == itemId {
                            return .immediately
                        }
                        listControllable.listModel.set(selectedItemId: itemId)
                }
                return .auto
            }
    }
}




