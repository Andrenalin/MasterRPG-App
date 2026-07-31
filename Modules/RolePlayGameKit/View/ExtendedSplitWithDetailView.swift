// @copyright André Trettin

#if !os(tvOS)

import CoreRPG
import SwiftUI

struct ExtendedSplitWithDetailView: View {
    let tab: ExtendedTabRoute
    @Binding var column: NavigationSplitViewVisibility
    @Binding var preferredCompactColumn: NavigationSplitViewColumn
    let appModel: AppModel

    @State private var fallbackNavigationModel = ModuleNavigationModel()

    init(
        tab: ExtendedTabRoute,
        column: Binding<NavigationSplitViewVisibility>,
        preferredCompactColumn: Binding<NavigationSplitViewColumn>,
        appModel: AppModel
    ) {
        self.tab = tab
        self._column = column
        self._preferredCompactColumn = preferredCompactColumn
        self.appModel = appModel
    }

    var body: some View {
        let controller = appModel.itemRootController(for: tab.module)
        @Bindable var model = controller?.navigationModel ?? fallbackNavigationModel
        NavigationSplitView(columnVisibility: $column, preferredCompactColumn: $preferredCompactColumn) {
            ManagedPresentationView {
                tab
            }
            .environment(controller)
        } detail: {
            SplitDetailView(module: tab.module)
                .environment(controller)
        }
        .inspectorAll(isPresented: $model.showInspector) {
            if model.showInspector {
                AppInspectorView(module: tab.module)
            }
        }
    }
}

#Preview("Map split detail") {
    let appModel = AppModel()

    ExtendedSplitWithDetailView(
        tab: .maps,
        column: .constant(.all),
        preferredCompactColumn: .constant(.sidebar),
        appModel: appModel
    )
    .environment(appModel)
}

#endif
