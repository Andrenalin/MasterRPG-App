// @copyright André Trettin

import CoreExternalRPG
import AndrenalinKit
import SwiftUI

public struct TabbedSplitNavigation: View {
    public init() {}

    @Environment(AppStore.self) private var appModel
    
    public var body: some View {
        let _ = Self._printChanges()
        let _ = print("Tab: \(selectedModule.title)")
        @Bindable var appModel = appModel
        
        NavigationSplitView {
            TabSidebar()
                .navigationSplitViewColumnWidth(min: 100, ideal: 150, max: 200)
        } content: {
            ManagedPresentationView {
                appModel.selectedModule
            }
            .environment(appModel.itemRootController(for: selectedModule))
        } detail: {
            SplitDetailView()
                .environment(appModel.itemRootController(for: selectedModule))
        }
        .onChange(of: appModel.selectedModule) {
            guard let selected = appModel.selectedModule, appModel.menuSelectedModule != selected.module else { return }
            appModel.menuSelectedModule = selected.module
        }
        .focusedSceneValue(\.selectedModule, $appModel.menuSelectedModule)
        .onNavigationReceive(assign: $appModel.selectedModule, delay: 0.8)
        .onNavigationRoute(RootRouteRouter(appStore: appModel))
        .onNavigationOpenURL(RootURLHandler(appStore: appModel))
    }
    
    var selectedModule: NetworkModules {
        (appModel.selectedModule ?? .game).module
    }
}


struct TabSidebar: View {
    @SceneStorage("RootRoute") private var storedTab: RootRoute = .game

    @Environment(AppStore.self) private var appModel
    
    var body: some View {
        @Bindable var appModel = appModel
        List(selection: $appModel.selectedModule) {
            allTabs
        }
        .onChange(of: storedTab, initial: true) {
            guard storedTab != appModel.selectedModule else { return }
            appModel.selectedModule = storedTab
        }
        .onChange(of: appModel.selectedModule) {
            guard storedTab != appModel.selectedModule, let selectedModule = appModel.selectedModule else { return }
            storedTab = selectedModule
        }
    }
    
    @ViewBuilder var allTabs: some View {
            Section {
                tabView(tab: .search)

                tabView(tab: .generator)
            } header: {
                Text("Special", bundle: .module)
            }

            Section {
                tabView(tab: .adventures)
                tabView(tab: .values)
                tabView(tab: .maps)
                tabView(tab: .weathers)
            } header: {
                Text("Library", bundle: .module)
            }

            Section {
                tabView(tab: .pdfs)
                tabView(tab: .tables)
            } header: {
                Text("References", bundle: .module)
            }

            Section {
                tabView(tab: .audios)
                tabView(tab: .dice)
                tabView(tab: .photos)
                tabView(tab: .space)
            } header: {
                Text("Material", bundle: .module)
            }
    }
    
    @ViewBuilder func tabView(tab: RootRoute) -> some View {
        NavigationLink(to: tab) {
            Label(tab.title, systemImage: tab.icon)
        }
        .tag(tab)
    }
}
