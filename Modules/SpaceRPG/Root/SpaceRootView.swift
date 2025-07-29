// @copyright André Trettin

import CoreExternalRPG
import CoreRPG
import SwiftData
import SwiftUI

struct SpaceRootView: View {
    let withoutNavigation: Bool

    @Environment(SpaceRootModel.self) private var root
    @Environment(DeviceRotationModel.self) private var deviceRotationModel

    @SceneStorage("SpaceRoute") private var route: SpaceRoute?
    @SceneStorage("SpaceDisplayModel") private var displayMode: ListModel.DisplayMode = .medium

    @State private var cacheItemListModel = CacheItemListModel()

    var listModel: ListModel {
        root.listModel
    }

    var body: some View {
        RootView(module: SpaceDataModel.typeId, listModel: listModel, withoutNavigation: withoutNavigation) {
            ListView()
                .navigationDestination(for: SpaceRoute.self) { route in
                    route
                        .environment(cacheItemListModel)
                        .environment(deviceRotationModel)
                        .environment(root.searchModel)
                        .onDisappear {
                            listModel.resetListSelection()
                            listModel.update(selection: Set())
                        }
                }
        } detail: {
            if let selected = listModel.selected {
                SpaceRoute.detail(selected)
            }
        }
        .environment(cacheItemListModel)
        .environment(listModel)
        .environment(root.searchModel)
        .onChange(of: displayMode, initial: true) {
            listModel.displayMode = displayMode
        }
        .onChange(of: listModel.displayMode) {
            displayMode <=> listModel.displayMode
        }
        .onChange(of: route, initial: true) {
            if let route {
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
                route <=> .detail(itemId)
            } else {
                route <=> nil
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
        }
    }
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

