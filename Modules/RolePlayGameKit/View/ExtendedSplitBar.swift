// @copyright André Trettin

#if !os(tvOS)

import CoreRPG
import SwiftUI

struct ExtendedSplitBar: View {
    @SceneStorage("ExtendedTabRoute") var currentModule: ExtendedTabRoute?

    @Environment(AppModel.self) private var appModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.navigator) private var navigator

    @State private var tabSelectedModule: NetworkModules = .map
    
    @State private var column: NavigationSplitViewVisibility = .all
    @State private var preferredCompactColumn: NavigationSplitViewColumn = .sidebar
    
    var body: some View {
        allCustomTabs
            .navigationAutoReceive(ExtendedTabRoute.self)
            .onNavigationRoute(RootVisionRouteRouter(appModel: appModel))
            .onChange(of: currentModule, initial: true) {
                appModel.selectedExtendedModule <=> currentModule
                guard let currentModule else { return }
                tabSelectedModule = currentModule.module
            }
            .onChange(of: appModel.selectedExtendedModule) {
                guard appModel.selectedExtendedModule != currentModule else { return }
                currentModule <=> appModel.selectedExtendedModule
            }
            .onChange(of: appModel.selectedModule, initial: true) {
                guard let selectedModule = appModel.selectedModule, selectedModule == .editors, currentModule == nil else { return }
                currentModule = .maps
            }
            .focusedSceneValue(\.selectedModule, $tabSelectedModule)
    }
}

private extension ExtendedSplitBar {
    var allCustomTabs: some View {
        ZStack {
            ForEach(ExtendedTabRoute.limitedTabs) { tab in
                tabView(tab: tab)
                    .opacity(appModel.selectedExtendedModule == tab ? 1 : 0)
            }
        }
#if os(visionOS)
        .ornament(attachmentAnchor: .scene(.trailing), contentAlignment: .leading) {
            SecondaryTabBar()
        }
#endif
    }
    
    @ViewBuilder
    func tabView(tab: ExtendedTabRoute) -> some View {
        @Bindable var model = appModel.itemRootController(for: tab.module)?.folderListControllable.detailInspectorModel ?? DetailInspectorModel()

        NavigationSplitView(columnVisibility: $column, preferredCompactColumn: $preferredCompactColumn) {
            contentView(tab: tab)
        } detail: {
            SplitDetailView(isExtendedRoutes: true)
                .environment(appModel.itemRootController(for: tab.module))
        }
        .inspectorAll(isPresented: $model.showInspector) {
            model.currentInspectorView
        }
    }

    func contentView(tab: ExtendedTabRoute) -> some View {
        ManagedPresentationView {
            tab
        }
        .environment(appModel.itemRootController(for: tab.module))
    }
}

#endif
