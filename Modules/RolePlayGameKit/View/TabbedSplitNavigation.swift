// @copyright André Trettin

import CoreRPG
import SwiftUI

struct TabbedSplitNavigation: View {
    @Environment(AppModel.self) private var appModel
    @Environment(AppWindowSizeModel.self) private var appWindowSizeModel
    @Environment(AppNavigationModel.self) private var appNavigationModel

    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var preferredCompactColumn: NavigationSplitViewColumn = .sidebar

    @AppStorage("contentColumnWidth") private var contentColumnWidth: Double = 350
    @State private var fallbackNavigationModel = ModuleNavigationModel()

    var body: some View {
        @Bindable var appModel = appModel
        let controller = appModel.itemRootController(for: selectedModule)
        @Bindable var model = controller?.navigationModel ?? fallbackNavigationModel
        let canShow = appNavigationModel.canShowInspector(appSizeModel: appWindowSizeModel)
        let inspectorBinding = Binding(
            get: { canShow && model.showInspector },
            set: { if canShow { model.showInspector = $0 } }
        )

        NavigationSplitView(columnVisibility: $columnVisibility, preferredCompactColumn: $preferredCompactColumn) {
            TabSidebar()
                .navigationSplitViewColumnWidth(min: 100, ideal: 150, max: 200)
        } content: {
            ManagedPresentationView {
                appModel.selectedModule
            }
            .environment(appModel.itemRootController(for: selectedModule))
            .navigationSplitViewColumnWidth(min: 250, ideal: contentColumnWidth, max: 600)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.frame(in: .global).width
            } action: { newWidth in
                contentColumnWidth = newWidth
            }
        } detail: {
            SplitDetailView(isExtendedRoutes: false)
                .environment(appModel.itemRootController(for: selectedModule))
        }
        .inspectorAll(isPresented: inspectorBinding) {
            if canShow && model.showInspector {
                AppInspectorView(isExtendedRoutes: false)
            }
        }
        .onChange(of: appModel.selectedModule) {
            guard let selected = appModel.selectedModule, appModel.menuSelectedModule != selected.module else { return }
            appModel.menuSelectedModule = selected.module
        }
        .focusedSceneValue(\.selectedModule, $appModel.menuSelectedModule)
        .onNavigationReceive(assign: $appModel.selectedModule)
        .navigationSplitViewStyle(.prominentDetail)
    }
    
    var selectedModule: NetworkModules {
        (appModel.selectedModule ?? .game).module
    }
}

struct TabSidebar: View {
    @SceneStorage("RootRoute") private var storedTab: RootRoute = .adventures

    @Environment(AppModel.self) private var appModel

    var body: some View {
        @Bindable var appModel = appModel
        List(selection: $appModel.selectedModule) {
            allTabs
        }
        .onAppear {
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
        
        Section {
            //tabView(tab: .search)
            
            tabView(tab: .generator)
        } header: {
            Text("Special", bundle: .module)
        }
    }
    
    @ViewBuilder func tabView(tab: RootRoute) -> some View {
        NavigationLink(to: tab) {
            Label(tab.title, systemImage: tab.icon)
        }
        .tag(tab)
    }
}
