// @copyright André Trettin

import CoreExternalRPG
import AndrenalinKit
import RPGAudios
import SwiftUI

public struct TabbedNavigation: View {
    public init() {}

    @SceneStorage("RootRoute") private var storedTab: RootRoute = .game

    @Environment(AppStore.self) private var appModel
    @Environment(\.appSizeMode) private var appSizeMode
    
    
    public var body: some View {
        let _ = Self._printChanges()
        let _ = print("Tab: \(selectedModule.title)")
        @Bindable var appModel = appModel
        
        TabView(selection: $appModel.selectedModule) {
            ForEach(RootRoute.fiveTabs) { tab in
                Tab(tab.title, systemImage: tab.icon, value: tab, role: tab == .search ? .search : nil) {
                    ManagedNavigationStack(name: tab.title) { _ in
                        tab
                    }
                    .environment(appModel.itemRootController(for: selectedModule))
                }
            }
        }
#if os(iOS)
        .tabBarMinimizeBehavior26(.onScrollDown)
        .tabViewBottomAccessory {
            if appSizeMode == .compact && appModel.audioRoot.audioPlayerModel.showPlayerToolBar {
                AudioPlayerMiniBarView()
            }
        }
#endif
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
        .onNavigationRoute(RootFiveRouteRouter(appStore: appModel))
        .onNavigationOpenURL(RootURLHandler(appStore: appModel))
    }
    
    var selectedModule: NetworkModules {
        (appModel.selectedModule ?? .game).module
    }

}
