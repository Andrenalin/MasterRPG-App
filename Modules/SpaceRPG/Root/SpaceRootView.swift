// @copyright André Trettin

import CoreExternalRPG
import CoreRPG
import SwiftData
import SwiftUI

struct SpaceRootView: View {
    let withoutNavigation: Bool

    @SceneStorage("SpaceRoute") private var spaceRoute: SpaceRoute?
    @SceneStorage("SpaceDisplayModel") private var displayMode: ListModel.DisplayMode = .medium

    @State private var cacheItemListModel = CacheItemListModel()
    @State private var listModel = ListModel()
    @State private var searchModel = SearchModel()

    var body: some View {
        RootView(module: .space, listModel: listModel, withoutNavigation: withoutNavigation, list: {
            ListView()
                .navigationDestination(for: SpaceRoute.self) { route in
                    route
                        .environment(cacheItemListModel)
                        .onDisappear {
                            listModel.resetListSelection()
                            listModel.update(selection: Set())
                        }
                }

        }, detail: {
            if let selected = listModel.selected {
                SpaceRoute.detail(selected)
            }
        })
        .environment(cacheItemListModel)
        .environment(listModel)
        .environment(searchModel)
        .onChange(of: displayMode, initial: true) {
            listModel.displayMode = displayMode
        }
        .onChange(of: listModel.displayMode) {
            displayMode <=> listModel.displayMode
        }
        .onChange(of: spaceRoute, initial: true) {
            if let route = spaceRoute {
                switch route {
                    case .detail(let itemId):
                        if listModel.selected != itemId {
                            listModel.update(selection: Set(arrayLiteral: itemId))
                        }
                }
            } else {
                listModel.update(selection: Set())
            }
        }
        .onChange(of: listModel.selected) {
            if let itemId = listModel.selected {
                spaceRoute <=> .detail(itemId)
            } else {
                spaceRoute <=> nil
            }
        }
        .onNavigationReceive { (route: SpaceRoute, navigator) in
            switch route {
                case .detail(let itemId):
                    if listModel.selected == itemId {
                        return .immediately
                    }
                    listModel.update(selection: Set(arrayLiteral: itemId))
                    return .auto
            }
        }    }
}

#Preview("Embed", traits: .mockData) {
    @Previewable @Query var models: [SpaceDataModel]

    ManagedNavigationStack {
        SpaceRootView(withoutNavigation: true)
            .environment(TabTitleModel())
            .environment(DeviceRotationModel())
    }
}

#Preview("Split", traits: .mockData) {
    @Previewable @Query var models: [SpaceDataModel]

    SpaceRootView(withoutNavigation: false)
        .environment(TabTitleModel())
        .environment(DeviceRotationModel())
#if os(macOS)
        .frame(width: 800, height: 600)
#endif
}

