// @copyright André Trettin

import CoreExternalRPG
import CoreRPG
#if !os(tvOS)
//import RealityKit
#endif
import SwiftUI

public struct TabNavigation: View {
    public init() {}
    
    @Environment(AppModel.self) private var appModel
#if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
#endif

    @Namespace private var hoverEffectNameSpace
    @SceneStorage("RootRoute") private var selectedTab: RootRoute = .game
    @State private var tabTitleModel = TabTitleModel()
    
    public var body: some View {
        let _ = Self._printChanges()

        Group {
#if os(macOS)
            allTabs
#elseif os(visionOS)
            allCustomTabs
#else
            if horizontalSizeClass == .compact {
                fiveTabs
            } else {
                allTabs
            }
#endif
        }
        .environment(appModel.deviceRotationModel)
        .environment(tabTitleModel)
#if os(iOS)
        .tabBarMinimizeBehavior26(.onScrollDown)
#endif
#if os(macOS)
        .tabViewStyle(.tabBarOnly)
#else
        .tabViewStyle(.sidebarAdaptable)
#endif
        //.onNavigationOpenURL(RootURLHandler(appStore: appStore))
        //.focusedSceneValue(\.selectedModule, tabSelectedModule)
    }
    
    private var tabSelectedModule: Binding<NetworkModules> {
        Binding {
            selectedTab.module
        } set: {
            try? appModel.externalRouter.route(to: KnownRoutes.route(module: $0, itemId: nil, entryId: nil))
        }
    }
}

private extension TabNavigation {
    func pageTab(for tab: RootRoute) -> Tab<RootRoute, some View, DefaultTabLabel> {
        Tab(tabTitleModel.titles[tab.module, default: tab.title], systemImage: tab.icon, value: tab) {
            tab
        }
    }
    
    var allTabs: some View {
        TabView(selection: $selectedTab) {
            ForEach(RootRoute.allTabs) { tab in
                pageTab(for: tab)
            }
        }
        .onNavigationReceive(assign: $selectedTab, delay: 0.8)
        .onNavigationRoute(RootRouteRouter(appModel: appModel))
    }

    var fiveTabs: some View {
        TabView(selection: $selectedTab) {
            ForEach(RootRoute.fiveTabs) { tab in
                pageTab(for: tab)
            }
        }
        .onNavigationReceive { (route: RootRoute, navigator) in
            let isFive = RootRoute.fiveTabs.contains(route)
            if isFive == true {
                if selectedTab == route {
                    return .immediately
                }
                selectedTab = route
                return .auto
            }
            if selectedTab != .editors {
                selectedTab = .editors
            }
            return .immediately
        }
        .onNavigationRoute(RootFiveRouteRouter(appModel: appModel))
    }

    var allCustomTabs: some View {
        ZStack {
            ForEach(RootRoute.allTabs) { tab in
                tab.opacity(selectedTab == tab ? 1 : 0)
            }
        }
        .onNavigationReceive(assign: $selectedTab, delay: 0.8)
        .onNavigationRoute(RootRouteRouter(appModel: appModel))
#if os(visionOS)
        .ornament(attachmentAnchor: .scene(.leading), contentAlignment: .center) {
            PrimaryTabBar(tabId: tabId, selectedTab: $selectedTab)
        }
#endif
    }
}
