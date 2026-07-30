// @copyright André Trettin


import CoreRPG
import SwiftUI

struct ExtendedTabBar: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.navigator) private var navigator

    private let restoresState: Bool

    @Namespace private var zoomNamespace

    @State private var tabSelectedModule: NetworkModules = .game

    init(restoresState: Bool = true) {
        self.restoresState = restoresState
    }

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
        .navigationTitle(Text(verbatim: NetworkModules.editor.title))
        .navigationBarTitleDisplayModeAll(.inline)
        .navigationModifier { destination in
            if let extened = destination as? ExtendedTabRoute {
                destination()
                    .modifier(ZoomTransitionViewModifier(sourceID: extened.module.token, namespace: zoomNamespace))
            } else {
                destination()
            }
        }
        .navigationAutoReceive(ExtendedTabRoute.self)
        .applyIf(restoresState) {
            $0.modifier(ExtendedTabBarRestorationModifier(
                appModel: appModel,
                tabSelectedModule: $tabSelectedModule
            ))
        }
        .focusedSceneValue(\.selectedModule, $tabSelectedModule)
    }
}

#Preview {
    ExtendedTabBar(restoresState: false)
        .environment(AppModel.previewWithoutDatabase)
}

private struct ExtendedTabBarRestorationModifier: ViewModifier {
    @SceneStorage("ExtendedTabRoute") private var currentModule: ExtendedTabRoute?

    let appModel: AppModel
    @Binding var tabSelectedModule: NetworkModules

    func body(content: Content) -> some View {
        content
            .onChange(of: appModel.selectedExtendedModule) {
                guard appModel.selectedExtendedModule != currentModule else { return }
                currentModule <=> appModel.selectedExtendedModule
            }
            .onAppear {
                appModel.selectedExtendedModule <=> currentModule
                guard let currentModule else { return }
                tabSelectedModule = currentModule.module
            }
    }
}

private extension ExtendedTabBar {
    func gridButtonView(for route: ExtendedTabRoute, in navigator: Navigator) -> some View {
        Button {
            appModel.selectedExtendedModule = route
            navigator.navigate(to: route)
        } label: {
            GridLabelView(value: route.module, color: theme.tint(for: route.module))
        }
        .accessibilityIdentifier("module.editor.\(route.module.token)")
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


///
/*
 func changeNavigation(selected: UUID?, navigator: Navigator, route: any NavigationDestination) {
     if selected != nil {
         navigator.push(route)
     } else {
         if navigator.count > 1 {
             navigator.pop(to: 1)
         }
     }
 }
 */
