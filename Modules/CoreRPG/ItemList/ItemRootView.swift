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

    @Environment(DeviceRotationModel.self) private var deviceRotationModel
#if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
#endif

    @State private var column: NavigationSplitViewVisibility = .all
    @State private var preferredCompactColumn: NavigationSplitViewColumn = .sidebar
    @State private var cacheItemListModel = CacheItemListModel()

    public var body: some View {
        rootView
            .applyItemRootRoute(listControllable: root.listControllable, route: route)
            .environment(cacheItemListModel)
            .environment(root.listDisplayModel)
            .environment(root.searchModel)
            .syncListDisplay(listControllable: root.listControllable, displayMode: displayMode, listMode: listMode)
            .tabBarPlacementModifier(listControllable: root.listControllable)
    }
}

private extension ItemRootView {
    @ViewBuilder var rootView: some View {
#if os(iOS)
        Group {
            if withoutNavigation || horizontalSizeClass == .compact {
                listRoot
                    .navigationDestination(for: ItemRootRoute.self) { route in
                        route
                            .environment(cacheItemListModel)
                            .environment(deviceRotationModel)
                    }
                    .onAppear {
                        listModel.resetListSelection()
                        listModel.update(selection: Set())
                    }
            } else {
                splitRoot
            }
        }
#else
        splitRoot
#endif
    }

    @ViewBuilder var splitRoot: some View {
        NavigationSplitView(columnVisibility: $column, preferredCompactColumn: $preferredCompactColumn) {
            ManagedPresentationView {
                listRoot
            }
        } detail: {
            if let selected = listModel.selectedItemId {
                ManagedNavigationStack {
                    ItemRootRoute.detail(selected)
                }
            } else {
                SplitContentUnavailableView(module: root.module)
            }
        }
    }

    @ViewBuilder var listRoot: some View {
        ListRootView(root: root, parentModel: nil)
            .searchItemList(listControllable: root.listControllable)
    }

    var listModel: ListModel {
        root.listControllable.listModel
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

