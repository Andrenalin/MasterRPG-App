// @copyright André Trettin

#if !os(tvOS)

import CoreRPG
import SwiftUI

struct SplitNavigation: View {
    @AppStorage("MasterRPGCustomization") private var customization: TabViewCustomization
    @SceneStorage("RootRoute") private var storedTab: RootRoute = SplitNavigation.defaultTab
    
    @Environment(AppModel.self) private var appModel
    
    @State private var column: NavigationSplitViewVisibility = .all
    @State private var preferredCompactColumn: NavigationSplitViewColumn = .sidebar
    
    var body: some View {
        let _ = Self._printChanges()
        @Bindable var appModel = appModel

        allTabs
            .syncOptionalState(
                source: $storedTab,
                destination: $appModel.selectedModule
            ) { newValue in
                if appModel.menuSelectedModule != newValue.module {
                    appModel.menuSelectedModule = newValue.module
                }
            }
            .focusedSceneValue(\.selectedModule, $appModel.menuSelectedModule)
            .onNavigationReceive(assign: $appModel.selectedModule, delay: 0.8)
            .onNavigationRoute(RootRouteRouter(appModel: appModel))
            .onNavigationOpenURL(RootURLHandler(appModel: appModel))
    }
    
    var selectedModule: NetworkModules {
        (appModel.selectedModule ?? SplitNavigation.defaultTab).module
    }
    
    static let defaultTab: RootRoute = .game
}

private extension SplitNavigation {
    @ViewBuilder var allTabs: some View {
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
                .tint(tab.module.tint)
        }
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
    
    func splitWithDetail(tab: RootRoute) -> some View {
        SplitWithDetailView(
            tab: tab,
            column: $column,
            preferredCompactColumn: $preferredCompactColumn,
            appModel: appModel
        )
    }
}

private struct SplitWithDetailView: View {
    let tab: RootRoute
    @Binding var column: NavigationSplitViewVisibility
    @Binding var preferredCompactColumn: NavigationSplitViewColumn
    let appModel: AppModel

    @State private var fallbackNavigationModel = ModuleNavigationModel()
    
    var body: some View {
        let _ = Self._printChanges()
        let controller = appModel.itemRootController(for: tab.module)
        @Bindable var model = controller?.navigationModel ?? fallbackNavigationModel
        NavigationSplitView(columnVisibility: $column, preferredCompactColumn: $preferredCompactColumn) {
            ManagedPresentationView {
                tab
            }
            .environment(controller)
        } detail: {
            SplitDetailView(isExtendedRoutes: false)
                .environment(controller)
        }
        .inspectorAll(isPresented: $model.showInspector) {
            if model.showInspector {
                AppInspectorView(isExtendedRoutes: false)
            }
        }
    }
}

#endif
