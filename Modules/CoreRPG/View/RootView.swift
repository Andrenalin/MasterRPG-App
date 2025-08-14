// @copyright André Trettin

import CoreExternalRPG
import SwiftUI

public struct RootView<List: View, Route: NavigationDestination>: View {
    public init(module: NetworkModules, listModel: ListModel, displayMode: Binding<ListModel.DisplayMode>, listMode: Binding<ListModel.ListMode>, withoutNavigation: Bool, route: Binding<Route?>, detailRoute: @escaping (UUID) -> Route, detailId: @escaping (Route) -> UUID?, @ViewBuilder list: () -> List) {
        self.module = module
        self.listModel = listModel
        self.displayMode = displayMode
        self.listMode = listMode
        self.withoutNavigation = withoutNavigation
        self.route = route
        self.detailRoute = detailRoute
        self.detailId = detailId
        self.list = list()
    }
    
    let module: NetworkModules
    let listModel: ListModel
    let displayMode: Binding<ListModel.DisplayMode>
    let listMode: Binding<ListModel.ListMode>
    let withoutNavigation: Bool
    let route: Binding<Route?>
    let detailRoute: (UUID) -> Route
    let detailId: (Route) -> UUID?
    let list: List
    
    @Environment(DeviceRotationModel.self) private var deviceRotationModel
    @Environment(SearchModel.self) private var searchModel
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
                        .onAppear {
                            listModel.resetListSelection()
                            listModel.update(selection: Set())
                        }
                } else {
                    rootView
                }
            }
            .onChange(of: tabBarPlacement, initial: true) {
                tabTitleModel.toggleTitles(horizontalSizeClass: horizontalSizeClass, tabBarPlacement: tabBarPlacement)
            }
            .onChange(of: horizontalSizeClass, initial: true) {
                listModel.isPadStyle = horizontalSizeClass != .compact
                tabTitleModel.toggleTitles(horizontalSizeClass: horizontalSizeClass, tabBarPlacement: tabBarPlacement)
            }
#else
            rootView
#endif
        }
        .onChange(of: displayMode.wrappedValue, initial: true) {
            listModel.displayMode <=> displayMode.wrappedValue
        }
        .onChange(of: listModel.displayMode) {
            displayMode.wrappedValue <=> listModel.displayMode
        }
        .onChange(of: listMode.wrappedValue, initial: true) {
            listModel.listMode <=> listMode.wrappedValue
        }
        .onChange(of: listModel.listMode) {
            listMode.wrappedValue <=> listModel.listMode
        }
        .onChange(of: listModel.selected) {
            if let itemId = listModel.selected {
                route.wrappedValue <=> detailRoute(itemId)
            } else {
                route.wrappedValue <=> nil
            }
        }
        .onChange(of: route.wrappedValue, initial: true) {
            if let route = route.wrappedValue, let itemId = detailId(route) {
                if listModel.selected != itemId {
                    listModel.update(selection: Set(arrayLiteral: itemId))
                }
            } else {
                listModel.update(selection: Set())
            }
        }
        .onNavigationReceive { (route: Route, navigator) in
            guard let itemId = detailId(route) else {
                return .auto
            }
            if listModel.selected == itemId {
                return .immediately
            }
            listModel.update(selection: Set(arrayLiteral: itemId))
            return .auto
        }
        .environment(cacheItemListModel)
        .environment(listModel)
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
            if let selected = listModel.selected {
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
        @Bindable var searchModel = searchModel
        list
            .navigationDestination(for: Route.self) { route in
                route
                    .environment(cacheItemListModel)
                    .environment(deviceRotationModel)
                    .environment(listModel)
                    .environment(searchModel)
            }
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
                cacheItemListModel.reset(search: searchModel.searchText)
            }
    }
    
    var searchPlacement: SearchFieldPlacement {
        .automatic
    }
    
    var searchScopeActivition: SearchScopeActivation {
#if os(tvOS)
        .automatic
#else
        .onSearchPresentation
#endif
    }
}

