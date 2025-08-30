// @copyright André Trettin

import CoreExternalRPG
import AndrenalinKit
import RPGAdventures
import RPGAudios
import RPGDie
import RPGMaps
import RPGPhotos
import RPGSpaces
import RPGTables
import RPGWeathers
#if !os(tvOS)
import RealityKit
#endif
import SwiftUI

public struct TabNavigation: View {
    public init(appStore: AppStore, tabId: UUID) {
        self.appStore = appStore
        self.tabId = tabId
    }

    let appStore: AppStore
    let tabId: UUID

#if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
#endif

    @Namespace private var hoverEffectNameSpace
    @SceneStorage("RootRoute") private var selectedTab: RootRoute = .game
    @State private var splitSelectedTab: RootRoute = .game

    public var body: some View {
        let _ = Self._printChanges()
        //let _ = print(selectedTab)

        Group {
#if os(macOS)
            allTabs
#elseif os(visionOS)
            //splitTabs
            allCustomTabs
#else
            if UIDevice.current.userInterfaceIdiom == .phone {
                fiveTabs
            } else {
                allTabs
            }
#endif
        }
        .environment(appStore.audioRootModel)
        .environment(appStore.diceRootModel)
        .environment(appStore.pdfRootModel)
        .environment(appStore.photoRootModel)
        .environment(appStore.spaceRootModel)
        .environment(appStore.tableRootModel)
        .environment(appStore.weatherRootModel)
        .onNavigationOpenURL(RootURLHandler(appStore: appStore))
        .focusedSceneValue(\.selectedModule, tabSelectedModule)
    }
    
    private var tabSelectedModule: Binding<NetworkModules> {
        Binding {
            selectedTab.module
        } set: {
            try? appStore.externalRouter.route(to: KnownRoutes.route(module: $0, itemId: nil, entryId: nil))
        }
    }
}

private extension TabNavigation {
    func pageTab(for tab: RootRoute) -> Tab<RootRoute, some View, DefaultTabLabel> {
        Tab(title(for: tab), systemImage: tab.icon, value: tab) {
            tab
        }
    }
    
    func title(for tab: RootRoute) -> String {
#if os(iOS)
        horizontalSizeClass == .compact ? tab.title : ""
#else
        tab.title
#endif
    }

    var allTabs: some View {
        TabView(selection: $selectedTab) {
            ForEach(RootRoute.allTabs(for: tabId)) { tab in
                pageTab(for: tab)
            }
        }
        .onNavigationReceive(assign: $selectedTab, delay: 0.8)
        .onNavigationRoute(RootRouteRouter(appStore: appStore, tabId: tabId))
    }

    var fiveTabs: some View {
        TabView(selection: $selectedTab) {
            ForEach(RootRoute.fiveTabs(for: tabId)) { tab in
                pageTab(for: tab)
            }
        }
        .onNavigationReceive { (route: RootRoute, navigator) in
            let isFive = RootRoute.fiveTabs(for: tabId).contains(route)
            if isFive == true {
                if selectedTab == route {
                    return .immediately
                }
                selectedTab = route
                return .auto
            }
            if selectedTab != .editors(tabId) {
                selectedTab = .editors(tabId)
            }
            return .immediately
        }
        .onNavigationRoute(RootFiveRouteRouter(appStore: appStore, tabId: tabId))
    }

    var allCustomTabs: some View {
        ZStack {
            ForEach(RootRoute.allTabs(for: tabId)) { tab in
                tab.opacity(selectedTab == tab ? 1 : 0)
            }
        }
        .onNavigationReceive(assign: $selectedTab, delay: 0.8)
        .onNavigationRoute(RootRouteRouter(appStore: appStore, tabId: tabId))
#if os(visionOS)
        .ornament(attachmentAnchor: .scene(.leading), contentAlignment: .center) {
            PrimaryTabBar(tabId: tabId, selectedTab: $selectedTab)
        }
#endif
    }

    var splitTabs: some View {
        TabView(selection: $selectedTab) {
            ForEach(RootRoute.splitLeadingTabs(for: tabId)) { tab in
                pageTab(for: tab)
            }
        }
        .opacity(isTabVisible ? 1 : 0)
        .onChange(of: selectedTab) {
            if selectedTab == .editors(tabId) {
                if splitSelectedTab == .game {
                    splitSelectedTab = RootRoute.splitTrailingTabs(for: tabId).first ?? .game
                }
            } else {
                splitSelectedTab = .game
            }
        }
        .onNavigationReceive { (route: RootRoute, navigator) in
            let isSplit = RootRoute.splitLeadingTabs(for: tabId).contains(route)
            if isSplit == true {
                if selectedTab == route {
                    return .immediately
                }
                selectedTab = route
                return .auto
            }
            if selectedTab != .editors(tabId) {
                selectedTab = .editors(tabId)
            }
            splitSelectedTab = route
            return .immediately
        }
        .onNavigationRoute(RootRouteRouter(appStore: appStore, tabId: tabId))
        .onNavigationOpenURL(RootURLHandler(appStore: appStore))
        .overlay(alignment: .topLeading) {
            ZStack {
                ForEach(RootRoute.splitTrailingTabs(for: tabId)) { tab in
                    tab.opacity(splitSelectedTab == tab ? 1 : 0)
                }
            }
        }
#if os(visionOS)
        .ornament(attachmentAnchor: .scene(.trailing), contentAlignment: .leading) {
            SecondaryTabBar(tabId: tabId, selectedTab: $splitSelectedTab)
        }
#endif
    }

    var isTabVisible: Bool {
        selectedTab != .editors(tabId)
    }
}
