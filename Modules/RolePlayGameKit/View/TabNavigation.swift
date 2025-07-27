// @copyright André Trettin

import CoreExternalRPG
import CoreRPG
import SwiftUI

public struct TabNavigation: View {
    public init() {}

    @AppStorage("MasterRPGCustomization") private var customization: TabViewCustomization
    @SceneStorage("RootRoute") private var selectedTab: RootRoute = .game

    @Environment(AppModel.self) private var appModel
#if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
#endif
    
    @State private var tabTitleModel = TabTitleModel()
    @State private var tabSelectedModule: NetworkModules = .game
    
    public var body: some View {
        let _ = Self._printChanges()

        Group {
#if os(macOS)
            allMacTabs
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
#if os(iOS)
        .tabBarMinimizeBehavior26(.onScrollDown)
#endif
#if os(macOS)
        .tabViewStyle(.grouped)
        //.frame(minWidth: 220, maxWidth: 300)
#else
        .tabViewStyle(.sidebarAdaptable)
#endif
        .environment(tabTitleModel)
        .focusedSceneValue(\.selectedModule, $tabSelectedModule)
        .onNavigationOpenURL(RootURLHandler(appModel: appModel))
        .onChange(of: selectedTab, initial: true) {
            tabSelectedModule = selectedTab.module
        }
    }
}

private extension TabNavigation {
    func pageTab(for tab: RootRoute) -> Tab<RootRoute, some View, DefaultTabLabel> {
        Tab(tabTitleModel.titles[tab.module, default: tab.title], systemImage: tab.icon, value: tab, role: tab == .search ? .search : nil) {
            tab
        }
    }

    func pageMacTab(for tab: RootRoute) -> Tab<RootRoute, some View, DefaultTabLabel> {
        Tab(tabTitleModel.titles[tab.module, default: tab.title], systemImage: tab.icon, value: tab) {
            tab
        }
    }

    var allMacTabs: some View {
        TabView(selection: $selectedTab) {
            pageTab(for: .game)

            ForEach(RootRoute.allTabs) { tab in
                pageMacTab(for: tab)
            }
        }
        .onNavigationReceive(assign: $selectedTab, delay: 0.8)
        .onNavigationRoute(RootRouteRouter(appModel: appModel))
    }

    
    var allTabs: some View {
        TabView(selection: $selectedTab) {
            pageTab(for: .game)
                .customizationID("Tab.\(NetworkModules.game.token)")
            #if !os(macOS)
                .customizationBehavior(.disabled, for: .sidebar, .tabBar)
            #endif

            pageTab(for: .search)
                .customizationID("Tab.\(NetworkModules.search.token)")

            TabSection {
                pageTab(for: .adventures)
                    .customizationID("Tab.\(NetworkModules.adventure.token)")
                pageTab(for: .values)
                    .customizationID("Tab.\(NetworkModules.value.token)")
                pageTab(for: .maps)
                    .customizationID("Tab.\(NetworkModules.map.token)")
            } header: {
                Text("Library", bundle: .module)
            }
            .customizationID("Tab.Libaray")
            .defaultVisibility(.hidden, for: .tabBar)


            TabSection {
                pageTab(for: .pdfs)
                    .customizationID("Tab.\(NetworkModules.pdf.token)")
                pageTab(for: .tables)
                    .customizationID("Tab.\(NetworkModules.table.token)")
            } header: {
                Text("References", bundle: .module)
            }
            .customizationID("Tab.References")
            .defaultVisibility(.hidden, for: .tabBar)

            TabSection {
                pageTab(for: .audios)
                    .customizationID("Tab.\(NetworkModules.audio.token)")
                pageTab(for: .dice)
                    .customizationID("Tab.\(NetworkModules.dice.token)")
                pageTab(for: .photos)
                    .customizationID("Tab.\(NetworkModules.photo.token)")
                pageTab(for: .space)
                    .customizationID("Tab.\(NetworkModules.space.token)")
            } header: {
                Text("Material", bundle: .module)
            }
            .customizationID("Tab.Material")
            .defaultVisibility(.hidden, for: .tabBar)

            pageTab(for: .settings)
                .customizationID("Tab.\(NetworkModules.setting.token)")
        }
        .tabViewCustomization($customization)
#if os(macOS)
        // Enforce minimum sidebar width on macOS
        .frame(minWidth: 220)
#endif
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
            PrimaryTabBar(selectedTab: $selectedTab)
        }
#endif
    }
}
