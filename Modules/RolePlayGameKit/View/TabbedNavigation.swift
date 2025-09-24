// @copyright André Trettin

import CoreExternalRPG
import CoreRPG
import AudioRPG
import SwiftUI

public struct TabbedNavigation: View {
    public init() {}

    @SceneStorage("RootRoute") private var storedTab: RootRoute = .game

    @Environment(AppModel.self) private var appModel
    @Environment(\.appSizeMode) private var appSizeMode
    
    @State private var tabTitleModel = TabTitleModel()
    
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
        .environment(tabTitleModel)
        //.focusedSceneValue(\.selectedModule, $tabSelectedModule)
        .onChange(of: storedTab, initial: true) {
            guard storedTab != appModel.selectedModule else { return }
            appModel.selectedModule = storedTab
            //tabSelectedModule <=> storedTab.module
        }
        .onChange(of: appModel.selectedModule) {
            guard storedTab != appModel.selectedModule, let selectedModule = appModel.selectedModule else { return }
            storedTab = selectedModule
        }
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
        .overlay {
            UpdateDataModeVliew(model: appModel)
        }
    }
    
    var selectedModule: NetworkModules {
        (appModel.selectedModule ?? .game).module
    }

}
