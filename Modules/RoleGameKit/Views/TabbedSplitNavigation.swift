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
            ManagedNavigationStack(name: selectedModule.title) { _ in
                appModel.selectedModule
            }
            .environment(appModel.itemRootController(for: selectedModule))
        } detail: {
            SplitDetailView()
                .environment(appModel.itemRootController(for: selectedModule))
        }
        .onChange(of: appModel.selectedModule) {
            print("**** \(appModel.selectedModule?.title ?? "Nothing selected")")
        }
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
            ForEach(RootRoute.allTabs) { tab in
                NavigationLink(to: tab) {
                    Label(tab.title, systemImage: tab.icon)
                }
                .tag(tab)
            }
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
}
