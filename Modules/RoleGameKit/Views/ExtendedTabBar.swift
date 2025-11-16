// @copyright André Trettin

import CoreExternalRPG
import AndrenalinKit
import SwiftUI

struct ExtendedTabBar: View {
    @SceneStorage("ExtendedTabRoute") var currentModule: ExtendedTabRoute?

    @Environment(AppStore.self) private var appModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.navigator) private var navigator

    @Namespace private var zoomNamespace

    @State private var tabSelectedModule: NetworkModules = .game

    var body: some View {
        ScrollView {
            VStack {
                Grid(horizontalSpacing: 16, verticalSpacing: 16) {
                    ForEach(doubleColumnTabs, id: \.self.0.id) { column in
                        GridRow {
                            gridButtonView(for: column.0, in: navigator)

                            if let tab = column.1 {
                                gridButtonView(for: tab, in: navigator)
                            }
                        }
                        .gridCellColumns(column.1 == nil ? 2 : 1)
                    }
                }
            }
        }
        .navigationTitle(Text(NetworkModules.editor.title))
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .navigationModifier { destination in
            if let extened = destination as? ExtendedTabRoute {
                destination()
                    .modifier(ZoomTransitionViewModifier(sourceID: extened.module.token, namespace: zoomNamespace))
            } else {
                destination()
            }
        }
        .navigationAutoReceive(ExtendedTabRoute.self)
        .onNavigationRoute(RootFiveRouteRouter(appModel: appModel))
        .onChange(of: currentModule, initial: true) {
            appModel.selectedExtendedModule = currentModule
            guard let currentModule else { return }
            tabSelectedModule = currentModule.module
        }
        .focusedSceneValue(\.selectedModule, $tabSelectedModule)
    }
}

private extension ExtendedTabBar {
    func changeNavigation(selected: UUID?, navigator: Navigator, route: any NavigationDestination) {
        if selected != nil {
            navigator.push(route)
        } else {
            if navigator.count > 1 {
                navigator.pop(to: 1)
            }
        }
    }

    func gridButtonView(for route: ExtendedTabRoute, in navigator: Navigator) -> some View {
        NavigationLink(to: route) {
            GridLabelView(value: route.module, color: route.module.tint)
        }
        .buttonStyle(.borderless)
        .modifier(ZoomDestinationViewModifier(sourceID: route.module.token, namespace: zoomNamespace))
    }

    var doubleColumnTabs: [(ExtendedTabRoute, ExtendedTabRoute?)] {
        var columns: [(ExtendedTabRoute, ExtendedTabRoute?)] = []
        var lastColumn: (ExtendedTabRoute, ExtendedTabRoute?)? = nil
        for (index, page) in ExtendedTabRoute.allTabs.enumerated() {
            if index.isMultiple(of: 2) {
                lastColumn = (page, nil)
            } else {
                lastColumn?.1 = page
                if let lastColumn {
                    columns.append(lastColumn)
                }
                lastColumn = nil
            }
        }
        if let lastColumn {
            columns.append(lastColumn)
        }
        return columns
    }
}
