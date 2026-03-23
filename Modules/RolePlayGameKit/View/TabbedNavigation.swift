// @copyright André Trettin

import AudioRPG
import CoreRPG
import SwiftUI

struct TabbedNavigation: View {
    @SceneStorage("RootRoute") private var storedTab: RootRoute = .game

    @Environment(AppModel.self) private var appModel
    @Environment(\.appSizeMode) private var appSizeMode
        
    var body: some View {
        @Bindable var appModel = appModel
        
        TabView(selection: $appModel.selectedModule) {
            ForEach(RootRoute.fiveTabs) { tab in
                Tab(tab.title, systemImage: tab.icon, value: tab, role: tab == .search ? .search : nil) {
                    ManagedNavigationStack(name: tab.title) { navigator in
                        tab
                            .environment(appModel.itemRootController(for: tab.module))
                            .tint(tab.module.tint)
                            .accentColor(tab.module.tint)
                    }
                    .environment(appModel.itemRootController(for: tab.module))
                    .tint(tab.module.tint)
                    .accentColor(tab.module.tint)
                }
            }
        }
#if os(iOS)
        .tabBarMinimizeBehavior26(.onScrollDown)
        .applyIf(appModel.audioRoot.audioPlayerModel.showPlayerToolBar) {
            $0.tabViewBottomAccessory {
                if appSizeMode == .compact && appModel.audioRoot.audioPlayerModel.showPlayerToolBar {
                    AudioPlayerMiniBarView()
                }
            }
        }
#endif
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
            guard RootRoute.fiveTabs.contains(route) else {
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
        .onNavigationRoute(RootFiveRouteRouter(appModel: appModel))
        .onNavigationOpenURL(RootURLHandler(appModel: appModel))
    }
    
    var selectedModule: NetworkModules {
        (appModel.selectedExtendedModule?.module ?? appModel.selectedModule?.module) ?? .game
    }
}
