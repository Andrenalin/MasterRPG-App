// @copyright André Trettin

#if !os(tvOS)

import CoreRPG
import SwiftUI

struct SplitWithDetailView: View {
    let tab: RootRoute
    @Binding var column: NavigationSplitViewVisibility
    @Binding var preferredCompactColumn: NavigationSplitViewColumn
    let appModel: AppModel

    @Environment(AppWindowSizeModel.self) private var appWindowSizeModel
    @Environment(AppNavigationModel.self) private var appNavigationModel
    @State private var fallbackNavigationModel = ModuleNavigationModel()

    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()

        let controller = appModel.itemRootController(for: tab.module)
        @Bindable var model = controller?.navigationModel ?? fallbackNavigationModel
        let canShow = appNavigationModel.canShowInspector(appSizeModel: appWindowSizeModel)
        let inspectorBinding = Binding(
            get: { canShow && model.showInspector },
            set: { if canShow { model.showInspector = $0 } }
        )
        NavigationSplitView(columnVisibility: $column, preferredCompactColumn: $preferredCompactColumn) {
            ManagedPresentationView {
                tab
            }
            .environment(controller)
#if os(iOS)
            .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 800)
#endif
        } detail: {
            SplitDetailView(module: tab.module)
                .environment(controller)
        }
        .inspectorAll(isPresented: inspectorBinding) {
            if canShow && model.showInspector {
                AppInspectorView(module: tab.module)
            }
        }
    }
}

#Preview("Adventure split detail") {
    let appModel = AppModel()

    SplitWithDetailView(
        tab: .adventures,
        column: .constant(.all),
        preferredCompactColumn: .constant(.content),
        appModel: appModel
    )
    .environment(appModel)
    .environment(appModel.appNavigationModel)
    .environment(AppWindowSizeModel())
}

#endif
