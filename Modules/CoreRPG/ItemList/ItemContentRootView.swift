// @copyright André Trettin

import CoreExternalRPG
import SwiftUI

public struct ItemContentRootView<List: View>: View {
    public init(module: NetworkModules, listController: any ListControllable, withoutNavigation: Bool, @ViewBuilder list: () -> List) {
        self.module = module
        self.listController = listController
        self.withoutNavigation = withoutNavigation
        self.list = list()
    }

    let module: NetworkModules
    let listController: any ListControllable
    let withoutNavigation: Bool
    let list: List

    @Environment(DeviceRotationModel.self) private var deviceRotationModel
#if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
#endif

    @State private var cacheItemListModel = CacheItemListModel()

    @State private var column: NavigationSplitViewVisibility = .all
    @State private var preferredCompactColumn: NavigationSplitViewColumn = .sidebar

    public var body: some View {
#if os(iOS)
        Group {
            if withoutNavigation && horizontalSizeClass == .compact {
                listRoot
                    .navigationDestination(for: ItemRootRoute.self) { route in
                        route
                            .environment(cacheItemListModel)
                            .environment(deviceRotationModel)
                    }
                    .onAppear {
                        listController.listModel.resetListSelection()
                        listController.listModel.update(selection: Set())
                    }
            } else {
                splitRoot
            }
        }
#else
        splitRoot
#endif
    }

    @ViewBuilder
    private var splitRoot: some View {
        NavigationSplitView(columnVisibility: $column, preferredCompactColumn: $preferredCompactColumn) {
            ManagedPresentationView {
                listRoot
            }
        } detail: {
            if let selected = listController.listModel.selectedItemId {
                ManagedNavigationStack {
                    ItemRootRoute.detail(selected)
                }
            } else {
                SplitContentUnavailableView(module: module)
            }
        }
    }

    @ViewBuilder
    private var listRoot: some View {
        list
            .searchItemList(listControllable: listController)
    }
}

