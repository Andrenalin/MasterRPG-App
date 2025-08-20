// @copyright André Trettin

import CoreExternalRPG
import SwiftUI

public struct RootView<ListController: OldListControllable, List: View, Route: NavigationDestination>: View {
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
    @Environment(\.tabBarPlacement) private var tabBarPlacement
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
            .onChange(of: tabBarPlacement, initial: true) {
                tabTitleModel.toggleTitles(horizontalSizeClass: horizontalSizeClass, tabBarPlacement: tabBarPlacement)
            }
            .onChange(of: horizontalSizeClass, initial: true) {
                listController.listDisplayModel.isPadStyle = horizontalSizeClass != .compact
                tabTitleModel.toggleTitles(horizontalSizeClass: horizontalSizeClass, tabBarPlacement: tabBarPlacement)
            }
#else
            rootView
#endif
        }
        .onChange(of: displayMode.wrappedValue, initial: true) {
            listController.listDisplayModel.displayMode <=> displayMode.wrappedValue
        }
        .onChange(of: listController.listDisplayModel.displayMode) {
            displayMode.wrappedValue <=> listController.listDisplayModel.displayMode
        }
        .onChange(of: listMode.wrappedValue, initial: true) {
            listController.listDisplayModel.listMode <=> listMode.wrappedValue
        }
        .onChange(of: listController.listDisplayModel.listMode) {
            listMode.wrappedValue <=> listController.listDisplayModel.listMode
        }
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
#if os(tvOS)
            .searchable(text: $searchModel.searchFieldText, placement: .automatic, prompt: Text("Search for items", bundle: .module))
#else
            .searchable(text: $searchModel.searchFieldText, tokens: $searchModel.selectedTokens, placement: .automatic, prompt: Text("Search or use @ for tags", bundle: .module), token: { token in
                Label(token.tag.prefix(3), systemImage: "tag")
            })
            .searchSuggestions {
                ForEach(searchModel.filteredTagSuggestions) { suggestion in
                    Button {
                        withAnimation {
                            searchModel.selectedTokens.append(suggestion)
                            searchModel.searchFieldText = ""
                            listController.resetFilter()
                        }
                    } label: {
                        Label(suggestion.tag, systemImage: "tag")
                    }
                }
            }
#endif
            .searchPresentationToolbarBehavior(.avoidHidingContent)
            .onChange(of: searchModel.searchFieldText) {
                guard searchModel.searchFieldText.starts(with: "@") == false else { return }
                withAnimation { searchModel.searchText = searchModel.searchFieldText }
            }
            .onChange(of: searchModel.searchText, initial: true) {
                withAnimation {
                    listController.resetFilter()
                    cacheItemListModel.reset(search: searchModel.searchText)
                }
            }
    }
}

