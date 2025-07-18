// @copyright André Trettin

import CoreExternalRPG
import AndrenalinKit
import RPGAdventures
import RPGAudios
import RPGDie
import RPGMaps
import RPGPdfs
import RPGPhotos
import RPGSpaces
import RPGTables
import RPGWeathers
import SwiftUI

struct ExtendedTabBar: View {
    let tabId: UUID

    @State var currentModule: ExtendedTabRoute?

    @Environment(AppStore.self) private var appStore
    @Environment(\.navigator) private var navigator

    @Namespace private var zoomNamespace

    var body: some View {
        ManagedNavigationStack(scene: "ExtendedTabBar") { navigator in
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
            .navigationDestination(for: ExtendedTabRoute.self) { route in
                route
                    .modifier(ZoomTransitionViewModifier(sourceID: route.module.token, namespace: zoomNamespace))
            }
            .navigationDestination(for: AudioRoute.self) { route in
                route
                    .environment(appStore.audioRoot)
            }
            .navigationDestination(for: DiceRoute.self) { route in
                route
                    .environment(appStore.diceRoot)
            }
            .navigationDestination(for: MapRoute.self) { route in
                route
                    .environment(appStore.mapRoot)
            }
            .navigationDestination(for: PdfRoute.self) { route in
                route
                    .environment(appStore.pdfRoot)
            }
            .navigationDestination(for: PhotoRoute.self) { route in
                route
                    .environment(appStore.photoRoot)
            }
            .navigationDestination(for: SpaceRoute.self) { route in
                route
                    .environment(appStore.spaceRoot)
            }
            .navigationDestination(for: TableRoute.self) { route in
                route
                    .environment(appStore.tableRoot)
            }
            .navigationDestination(for: WeatherRoute.self) { route in
                route
                    .environment(appStore.weatherRoot)
            }
            .onNavigationReceive { (route: ExtendedTabRoute, navigator) in
                if currentModule == route {
                    return .immediately
                }
                navigator.push(route)
                return .auto
            }
            .onNavigationReceive { (route: AudioRoute, navigator) in
                if case .detail(let selected, _) = route {
                    changeNavigation(selected: selected, navigator: navigator, route: route)
                }
                return .auto
            }
            .onNavigationReceive { (route: DiceRoute, navigator) in
                if case .detail(let selected, _) = route {
                    changeNavigation(selected: selected, navigator: navigator, route: route)
                }
                return .auto
            }
            .onNavigationReceive { (route: MapRoute, navigator) in
                if case .detail(let selected, _) = route {
                    changeNavigation(selected: selected, navigator: navigator, route: route)
                }
                return .auto
            }
            .onNavigationReceive { (route: PdfRoute, navigator) in
                if case .detail(let selected, _) = route {
                    changeNavigation(selected: selected, navigator: navigator, route: route)
                }
                return .auto
            }
            .onNavigationReceive { (route: PhotoRoute, navigator) in
                if case .detail(let selected, _) = route {
                    changeNavigation(selected: selected, navigator: navigator, route: route)
                }
                return .auto
            }
            .onNavigationReceive { (route: SpaceRoute, navigator) in
                if case .detail(let selected, _) = route {
                    changeNavigation(selected: selected, navigator: navigator, route: route)
                }
                return .auto
            }
            .onNavigationReceive { (route: TableRoute, navigator) in
                if case .detail(let selected, _) = route {
                    changeNavigation(selected: selected, navigator: navigator, route: route)
                }
                return .auto
            }
            .onNavigationReceive { (route: WeatherRoute, navigator) in
                if case .detail(let selected, _) = route {
                    changeNavigation(selected: selected, navigator: navigator, route: route)
                }
                return .auto
            }
            .onNavigationRoute(RootFiveRouteRouter(appStore: appStore, tabId: tabId))
        }
    }
}

private extension ExtendedTabBar {
    func changeNavigation(selected: ItemRowTreeModel?, navigator: Navigator, route: any NavigationDestination) {
        if selected != nil {
            navigator.push(route)
        } else {
            if navigator.count > 1 {
                navigator.pop(to: 1)
            }
        }
    }

    func gridButtonView(for route: ExtendedTabRoute, in navigator: Navigator) -> some View {
        GridButtonView(value: route.module, color: route.module.color) {
            navigator.push(route)
        }
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
