// @copyright André Trettin

import CoreExternalRPG
import SwiftData
import SwiftUI

public struct ItemRootView: View {
    public init(root: any ItemRootControllable, withoutNavigation: Bool, displayMode: Binding<ListDisplayModel.DisplayMode>, listMode: Binding<ListDisplayModel.ListMode>, route: Binding<ItemRootRoute?>) {
        self.root = root
        self.withoutNavigation = withoutNavigation
        self.displayMode = displayMode
        self.listMode = listMode
        self.route = route
    }

    let root: ItemRootControllable
    let withoutNavigation: Bool

    let displayMode: Binding<ListDisplayModel.DisplayMode>
    let listMode: Binding<ListDisplayModel.ListMode>
    let route: Binding<ItemRootRoute?>

    @State private var cacheItemListModel = CacheItemListModel()

    public var body: some View {
        ItemContentRootView(module: root.module, listController: root.listControllable, withoutNavigation: withoutNavigation) {
            //            //ListView()
            Text("List")
        }
        .applyItemRootRoute(listControllable: root.listControllable, route: route)
        .environment(cacheItemListModel)
        .environment(root.listDisplayModel)
        .environment(root.searchModel)
        .syncListDisplay(listControllable: root.listControllable, displayMode: displayMode, listMode: listMode)
        .tabBarPlacementModifier(listControllable: root.listControllable)
    }
}

//#Preview("Small", traits: .mockData) {
//    @Previewable @Query var models: [AudioDataModel]
//
//    ManagedNavigationStack {
//        ItemRootView(withoutNavigation: true)
//    }
//}
//
//
//#Preview("Split", traits: .mockData) {
//    @Previewable @Query var models: [AudioDataModel]
//
//    ItemRootView(withoutNavigation: false)
//}

