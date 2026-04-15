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
    
    func tabView(tab: ExtendedTabRoute) -> some View {
        ExtendedSplitWithDetailView(
            tab: tab,
            column: $column,
            preferredCompactColumn: $preferredCompactColumn,
            appModel: appModel
        )
    }

    func contentView(tab: ExtendedTabRoute) -> some View {
        ManagedPresentationView {
            tab
        }
        .environment(appModel.itemRootController(for: tab.module))
    }
}

private struct ExtendedSplitWithDetailView: View {
    let tab: ExtendedTabRoute
    @Binding var column: NavigationSplitViewVisibility
    @Binding var preferredCompactColumn: NavigationSplitViewColumn
    let appModel: AppModel

    @State private var fallbackNavigationModel = ModuleNavigationModel()
    
    var body: some View {
        let controller = appModel.itemRootController(for: tab.module)
        @Bindable var model = controller?.navigationModel ?? fallbackNavigationModel
        NavigationSplitView(columnVisibility: $column, preferredCompactColumn: $preferredCompactColumn) {
            ManagedPresentationView {
                tab
            }
            .environment(controller)
        } detail: {
            SplitDetailView(isExtendedRoutes: true)
                .environment(controller)
        }
        .inspectorAll(isPresented: $model.showInspector) {
            if model.showInspector {
                AppInspectorView(isExtendedRoutes: true)
            }
        }
    }
}

#endif
