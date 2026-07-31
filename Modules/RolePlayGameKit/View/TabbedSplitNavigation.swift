// @copyright André Trettin

import CoreRPG
import SwiftUI

struct TabbedSplitNavigation: View {
    @Environment(AppModel.self) private var appModel
    @Environment(AppWindowSizeModel.self) private var appWindowSizeModel
    @Environment(AppNavigationModel.self) private var appNavigationModel

    private let restoresState: Bool

    init(restoresState: Bool = true) {
        self.restoresState = restoresState
    }

    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var preferredCompactColumn: NavigationSplitViewColumn = .sidebar

    @State private var fallbackNavigationModel = ModuleNavigationModel()

    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()
        
        @Bindable var appModel = appModel
        let controller = appModel.itemRootController(for: selectedModule)
        @Bindable var model = controller?.navigationModel ?? fallbackNavigationModel
        let canShow = appNavigationModel.canShowInspector(appSizeModel: appWindowSizeModel)
        let inspectorBinding = Binding(
            get: { canShow && model.showInspector },
            set: { if canShow { model.showInspector = $0 } }
        )

        NavigationSplitView(columnVisibility: $columnVisibility, preferredCompactColumn: $preferredCompactColumn) {
            TabSidebar(restoresState: restoresState)
                .navigationSplitViewColumnWidth(min: 96, ideal: 120, max: 180)
        } content: {
            ManagedPresentationView {
                appModel.selectedModule
            }
            .frame(maxWidth: 400)
            .navigationSplitViewColumnWidth(min: 150, ideal: 250, max: 400)
            .environment(appModel.itemRootController(for: selectedModule))
        } detail: {
            SplitDetailView(module: selectedModule)
                .environment(appModel.itemRootController(for: selectedModule))
                .frame(maxWidth: .infinity)
                .navigationSplitViewColumnWidth(min: 200, ideal: 450)
        }
        .inspectorAll(isPresented: inspectorBinding) {
            if canShow && model.showInspector {
                AppInspectorView(module: selectedModule)
            }
        }
        .onChange(of: appModel.selectedModule) {
            guard let selected = appModel.selectedModule, appModel.menuSelectedModule != selected.module else { return }
            appModel.menuSelectedModule = selected.module
        }
        .focusedSceneValue(\.selectedModule, $appModel.menuSelectedModule)
        .onNavigationReceive(assign: $appModel.selectedModule)
        .navigationSplitViewStyle(.balanced)
    }
    
    var selectedModule: NetworkModules {
        (appModel.selectedModule ?? .adventures).module
    }
}

#Preview {
    let appModel = AppModel.previewWithoutDatabase

    TabbedSplitNavigation(restoresState: false)
        .environment(appModel)
        .environment(appModel.appNavigationModel)
        .environment(AppWindowSizeModel())
        .environment(AppFocusModel())
}
