// @copyright André Trettin

#if !os(tvOS)
import CoreExternalRPG
import AndrenalinKit
import SwiftUI

public struct SplitNavigation: View {
    public init() {}

    @AppStorage("MasterRPGCustomization") private var customization: TabViewCustomization
    @SceneStorage("RootRoute") private var storedTab: RootRoute = .game

    @Environment(AppStore.self) private var appModel
    
    @State private var column: NavigationSplitViewVisibility = .all
    @State private var preferredCompactColumn: NavigationSplitViewColumn = .sidebar
    
    public var body: some View {
        let _ = Self._printChanges()
        let _ = print("Tab: \(selectedModule.title)")
        @Bindable var appModel = appModel

        Group {
#if os(visionOS)
            allCustomTabs
#else
            allTabs
#endif
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
        .onNavigationReceive(assign: $appModel.selectedModule, delay: 0.8)
        .onNavigationRoute(RootRouteRouter(appModel: appModel))
        .onNavigationOpenURL(RootURLHandler(appModel: appModel))
    }
    
    var selectedModule: NetworkModules {
        (appModel.selectedModule ?? .game).module
    }
}

private extension SplitNavigation {
    
    @ViewBuilder
    var allTabs: some View {
        @Bindable var appModel = appModel
        
        TabView(selection: $appModel.selectedModule) {
            pageTab(for: .game)
                .customizationID("Tab.\(NetworkModules.game.token)")
            #if !os(macOS)
                .customizationBehavior(.disabled, for: .sidebar, .tabBar)
            #endif

            TabSection {
                pageTab(for: .search)
                    .customizationID("Tab.\(NetworkModules.search.token)")

                pageTab(for: .generator)
                    .customizationID("Tab.\(NetworkModules.generator.token)")
            } header: {
                Text("Special", bundle: .module)
            }
            .customizationID("Tab.Special")
            .defaultVisibility(.hidden, for: .tabBar)

            TabSection {
                pageTab(for: .adventures)
                    .customizationID("Tab.\(NetworkModules.adventure.token)")
                pageTab(for: .values)
                    .customizationID("Tab.\(NetworkModules.value.token)")
                pageTab(for: .maps)
                    .customizationID("Tab.\(NetworkModules.map.token)")
                pageTab(for: .weathers)
                    .customizationID("Tab.\(NetworkModules.weather.token)")
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

            TabSection {
                pageTab(for: .settings)
                    .customizationID("Tab.\(NetworkModules.setting.token)")
            } header: {
                Text("Setting", bundle: .module)
            }
            .customizationID("Tab.Util")

        }
        .tabViewCustomization($customization)
        .tabViewStyle(.sidebarAdaptable)
    }

    func pageTab(for tab: RootRoute) -> Tab<RootRoute?, some View, DefaultTabLabel> {
        Tab(tab.title, systemImage: tab.icon, value: tab, role: tab == .search ? .search : nil) {
            tabView(tab: tab)
        }
    }
    
    var allCustomTabs: some View {
        ZStack {
            ForEach(RootRoute.allTabs) { tab in
                tabView(tab: tab)
                    .opacity(appModel.selectedModule == tab ? 1 : 0)
            }
        }
#if os(visionOS)
        .ornament(attachmentAnchor: .scene(.leading), contentAlignment: .center) {
            PrimaryTabBar()
        }
#endif
    }
    
    @ViewBuilder
    func tabView(tab: RootRoute) -> some View {
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
    
    func splitWithDetail(tab: RootRoute) -> some View {
        NavigationSplitView(columnVisibility: $column, preferredCompactColumn: $preferredCompactColumn) {
            contentView(tab: tab)
        } detail: {
            SplitDetailView()
                .environment(appModel.itemRootController(for: tab.module))
        }
    }
}

#endif
