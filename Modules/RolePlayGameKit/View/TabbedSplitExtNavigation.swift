// @copyright André Trettin

import CoreRPG
import SwiftUI

public struct TabbedSplitExtNavigation: View {
    public init() {}
    
    @SceneStorage("RootRoute") private var storedTab: RootRoute = .game
    
    @Environment(AppModel.self) private var appModel
    
    @State private var column: NavigationSplitViewVisibility = .all
    @State private var preferredCompactColumn: NavigationSplitViewColumn = .sidebar
    
    public var body: some View {
        @Bindable var appModel = appModel
        
        TabView(selection: $appModel.selectedModule) {
            ForEach(RootRoute.visionTabs) { tab in
                Tab(tab.title, systemImage: tab.icon, value: tab, role: tab == .search ? .search : nil) {
                    tabView(tab: tab)
                }
            }
        }
        .onChange(of: storedTab, initial: true) {
            guard storedTab != appModel.selectedModule else { return }
            appModel.selectedModule = storedTab
        }
        .onChange(of: appModel.selectedModule) {
            if let selected = appModel.selectedModule, appModel.menuSelectedModule != selected.module {
                appModel.menuSelectedModule = selected.module
            }
            guard storedTab != appModel.selectedModule, let selectedModule = appModel.selectedModule else { return }
            storedTab = selectedModule
        }
        .focusedSceneValue(\.selectedModule, $appModel.menuSelectedModule)
        .onNavigationReceive { (route: RootRoute, navigator) in
            guard RootRoute.visionTabs.contains(route) else {
                guard appModel.selectedModule != .editors else { return .immediately }
                appModel.selectedModule = .editors
                return .after(0.8)
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
            SplitDetailView()
                .environment(appModel.itemRootController(for: tab.module))
        }
    }
}
