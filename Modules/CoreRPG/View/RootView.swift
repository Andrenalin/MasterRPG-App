// @copyright André Trettin

import CoreExternalRPG
import SwiftUI

public struct RootView<ListController: ListControllable, List: View, Route: NavigationDestination>: View {
    public init(module: NetworkModules, listController: ListController, displayMode: Binding<ListDisplayModel.DisplayMode>, listMode: Binding<ListDisplayModel.ListMode>, withoutNavigation: Bool, route: Binding<Route?>, detailRoute: @escaping (UUID) -> Route, detailId: @escaping (Route) -> UUID?, @ViewBuilder list: () -> List) {
        self.module = module
        self.listController = listController
        self.displayMode = displayMode
        self.listMode = listMode
        self.withoutNavigation = withoutNavigation
        self.route = route
        self.detailRoute = detailRoute
        self.detailId = detailId
        self.list = list()
    }
    
    let module: NetworkModules
    let listController: ListController
    let displayMode: Binding<ListDisplayModel.DisplayMode>
    let listMode: Binding<ListDisplayModel.ListMode>
    let withoutNavigation: Bool
    let route: Binding<Route?>
    let detailRoute: (UUID) -> Route
    let detailId: (Route) -> UUID?
    let list: List
    
    @Environment(DeviceRotationModel.self) private var deviceRotationModel
    @Environment(TabTitleModel.self) private var tabTitleModel
#if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
#endif

    @State private var cacheItemListModel = CacheItemListModel()
    
    @State private var column: NavigationSplitViewVisibility = .all
    @State private var preferredCompactColumn: NavigationSplitViewColumn = .sidebar
    
    public var body: some View {
        Group {
#if os(iOS)
            Group {
                if horizontalSizeClass == .compact {
                    listRoot
                        .navigationDestination(for: Route.self) { route in
                            route
                                .environment(cacheItemListModel)
                                .environment(deviceRotationModel)
                        }
                        .onAppear {
                            listController.listModel.resetListSelection()
                            listController.listModel.update(selection: Set())
                        }
                } else {
                    rootView
                }
            }
            .tabBarPlacementModifier(listControllable: listController)
#else
            rootView
#endif
        }
        .syncListDisplay(listControllable: listController, displayMode: displayMode, listMode: listMode)
        .onChange(of: listController.listModel.selected) {
            if let selected = listController.listModel.selectedItemId {
                route.wrappedValue <=> detailRoute(selected)
            } else {
                route.wrappedValue <=> nil
            }
        }
        .onChange(of: route.wrappedValue, initial: true) {
            if let route = route.wrappedValue, let itemId = detailId(route) {
                if listController.listModel.selectedItemId != itemId {
                    listController.listModel.set(selectedItemId: itemId)
                }
            } else {
                listController.listModel.update(selection: Set())
            }
        }
        .onNavigationReceive { (route: Route, navigator) in
            guard let itemId = detailId(route) else {
                return .auto
            }
            if listController.listModel.selectedItemId == itemId {
                return .immediately
            }
            listController.listModel.set(selectedItemId: itemId)
            return .auto
        }
        .environment(cacheItemListModel)
    }
    
    @ViewBuilder
    private var rootView: some View {
        if withoutNavigation {
            listRoot
        } else {
            splitRoot
        }
    }
    
    @ViewBuilder
    private var splitRoot: some View {
        NavigationSplitView(columnVisibility: $column, preferredCompactColumn: $preferredCompactColumn) {
            ManagedPresentationView {
                listRoot
            }
        } detail: {
            if let selected = listController.listModel.selectedItemId {
                ManagedNavigationStack {
                    detailRoute(selected)
                }
            } else {
                SplitContentUnavailableView(module: module)
            }
        }
    }
    
    @ViewBuilder
    private var listRoot: some View {
        @Bindable var searchModel = listController.searchModel
        list
            .searchItemList(listControllable: listController)
    }
}

