// @copyright André Trettin

import CoreExternalRPG
import CoreRPG
import SwiftData
import SwiftUI

struct DiceRootView: View {
    let withoutNavigation: Bool

    @Environment(DiceRootModel.self) private var root
    @Environment(DeviceRotationModel.self) private var deviceRotationModel
    
    @SceneStorage("DiceRoute") private var route: DiceRoute?
    @SceneStorage("DiceDisplayModel") private var displayMode: ListModel.DisplayMode = .medium
    @SceneStorage("DiceListModel") private var listMode: ListModel.ListMode = .list

    @State private var cacheItemListModel = CacheItemListModel()

    var listModel: ListModel {
        root.listModel
    }
    
    var body: some View {
        RootView(module: DiceDataModel.typeId, listModel: listModel, withoutNavigation: withoutNavigation, route: route, displayMode: $displayMode, listMode: $listMode) {
            ListView()
        } detail: {
            Group {
                if let selected = listModel.selected {
                    DiceRoute.detail(selected)
                }
            }
            .navigationDestination(for: DiceRoute.self) { route in
                route
            }
        }
        .environment(cacheItemListModel)
        .environment(listModel)
        .environment(root.searchModel)
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
            root.currentSelectedItemId = listModel.selected
            if let itemId = listModel.selected {
                route <=> .detail(itemId)
            } else {
                route <=> nil
            }
        }
        .onNavigationReceive { (route: DiceRoute, navigator) in
            switch route {
                case .detail(let itemId):
                    if listModel.selected == itemId {
                        return .immediately
                    }
                    listModel.update(selection: Set(arrayLiteral: itemId))
                    return .auto
            }
        }
        .environment(root.searchModel)
    }
}

#Preview("Small", traits: .mockData) {
    @Previewable @Query var models: [DiceDataModel]

    ManagedNavigationStack {
        DiceRootView(withoutNavigation: true)
            .environment(TabTitleModel())
            .environment(DeviceRotationModel())
    }
}


#Preview("Split", traits: .mockData) {
    @Previewable @Query var models: [DiceDataModel]

    DiceRootView(withoutNavigation: false)
        .environment(TabTitleModel())
        .environment(DeviceRotationModel())
#if os(macOS)
        .frame(width: 800, height: 600)
#endif
}
