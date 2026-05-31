// @copyright André Trettin

import CoreRPG
import SwiftUI

struct SplitEditorNavigation: View {
    @SceneStorage("EditorRoute") private var storedTab: RootRoute = .pdfs
    
    @Environment(AppModel.self) private var appModel
    @Environment(ScenesManager.self) private var scenesManager
    
    @State private var column: NavigationSplitViewVisibility = .all
    @State private var preferredCompactColumn: NavigationSplitViewColumn = .sidebar
    
    var body: some View {
        @Bindable var appModel = appModel
        
        TabView(selection: $appModel.selectedEditorModule) {
            ForEach(RootRoute.visionEditorTabs) { tab in
                Tab(tab.title, systemImage: tab.icon, value: tab, role: tab == .search ? .search : nil) {
                    tabView(tab: tab)
                }
            }
        }
        .syncOptionalState(
            source: $storedTab,
            destination: $appModel.selectedEditorModule
        ) { newValue in
            if appModel.menuSelectedModule != newValue.module {
                appModel.menuSelectedModule = newValue.module
            }
        }
        .focusedSceneValue(\.selectedModule, $appModel.menuSelectedModule)
        .onNavigationReceive { (route: RootRoute, navigator) in
            guard RootRoute.visionEditorTabs.contains(route) else {
                return .immediately
            }
            if appModel.selectedEditorModule == route {
                return .immediately
            }
            appModel.selectedEditorModule = route
            return .after(0.8)
        }
#if os(visionOS)
        .ornament(attachmentAnchor: .scene(.trailing), contentAlignment: .leading) {
            VStack {
                menuView
            }
            .padding(12)
            .environment(scenesManager)
        }
        .ornament(attachmentAnchor: .scene(.bottomLeading), contentAlignment: .topLeading) {
            Button {
                scenesManager.openWindow(SceneId.game)
            } label: {
                Label {
                    Text("Game", bundle: .module)
                } icon: {
                    Image(systemName: NetworkModules.game.icon)
                }
            }
            .padding([.top, .leading], 12)
            .environment(scenesManager)
        }
#endif
    }
    
    var selectedModule: NetworkModules {
        (appModel.selectedEditorModule ?? AppModel.defaultEditorModule).module
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
    
    @ViewBuilder func splitWithDetail(tab: RootRoute) -> some View {
        NavigationSplitView(columnVisibility: $column, preferredCompactColumn: $preferredCompactColumn) {
            contentView(tab: tab)
        } detail: {
            SplitDetailView(isExtendedRoutes: true)
                .environment(appModel.itemRootController(for: tab.module))
        }
    }
    
    var menuView: some View {
        Group {
            MenuWindowButtonView(valueType: .adventure)
            MenuWindowButtonView(valueType: .audio)
            MenuWindowButtonView(valueType: .dice)
            MenuWindowButtonView(valueType: .map)
            MenuWindowButtonView(valueType: .pdf)
            MenuWindowButtonView(valueType: .photo)
            MenuWindowButtonView(valueType: .space)
            MenuWindowButtonView(valueType: .table)
            MenuWindowButtonView(valueType: .value)
            MenuWindowButtonView(valueType: .weather)
        }
    }
}
