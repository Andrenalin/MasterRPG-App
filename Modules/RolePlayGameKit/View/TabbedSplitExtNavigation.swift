// @copyright André Trettin

import CoreRPG
import SwiftUI

struct TabbedSplitExtNavigation: View {
    @SceneStorage("GameRoute") private var storedTab: RootRoute = .game
    
    @Environment(AppModel.self) private var appModel
    
    @State private var column: NavigationSplitViewVisibility = .all
    @State private var preferredCompactColumn: NavigationSplitViewColumn = .sidebar
    
    var body: some View {
        @Bindable var appModel = appModel
        
        TabView(selection: $appModel.selectedModule) {
            ForEach(RootRoute.visionTabs) { tab in
                Tab(tab.title, systemImage: tab.icon, value: tab, role: tab == .search ? .search : nil) {
                    tabView(tab: tab)
                }
            }
        }
        .syncOptionalState(
            source: $storedTab,
            destination: $appModel.selectedModule
        ) { newValue in
            if appModel.menuSelectedModule != newValue.module {
                appModel.menuSelectedModule = newValue.module
            }
        }
        .focusedSceneValue(\.selectedModule, $appModel.menuSelectedModule)
        .onNavigationReceive { (route: RootRoute, navigator) in
            guard RootRoute.visionTabs.contains(route) else {
                return .immediately
            }
            if appModel.selectedModule == route {
                return .immediately
            }
            appModel.selectedModule = route
            return .after(0.8)
        }
        .onNavigationRoute(RootVisionRouteRouter(appModel: appModel))
        .onNavigationOpenURL(RootURLHandler(appModel: appModel))
    }
    
    var selectedModule: NetworkModules {
        (appModel.selectedExtendedModule?.module ?? appModel.selectedModule?.module) ?? .game
    }
    
    @ViewBuilder func tabView(tab: RootRoute) -> some View {
        if tab.hasDetailView {
            splitWithDetail(tab: tab)
        } else {
            contentView(tab: tab)
        }
    }
    
    func contentView(tab: RootRoute) -> some View {
        ManagedPresentationView {
            tab
        }
        .environment(appModel.itemRootController(for: tab.module))
    }
    
    @ViewBuilder func splitWithDetail(tab: RootRoute) -> some View {
        NavigationSplitView(columnVisibility: $column, preferredCompactColumn: $preferredCompactColumn) {
            contentView(tab: tab)
        } detail: {
            SplitDetailView(isExtendedRoutes: false)
                .environment(appModel.itemRootController(for: tab.module))
        }
    }
}
