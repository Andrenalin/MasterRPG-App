// @copyright André Trettin

import CoreExternalRPG
import CoreRPG
import SwiftData
import SwiftUI

struct PhotoRootView: View {
    let withoutNavigation: Bool

    @Environment(PhotoRootModel.self) private var root
    @Environment(DeviceRotationModel.self) private var deviceRotationModel
    
    @SceneStorage("PhotoRoute") private var route: PhotoRoute?
    @SceneStorage("PhotoDisplayModel") private var displayMode: ListModel.DisplayMode = .medium
    @SceneStorage("PhotoListModel") private var listMode: ListModel.ListMode = .list

    @State private var cacheItemListModel = CacheItemListModel()

    var listModel: ListModel {
        root.listModel
    }
    
    var body: some View {
        RootView(module: PhotoDataModel.typeId, listModel: listModel, withoutNavigation: withoutNavigation) {
            ListView()            
                .navigationDestination(for: PhotoRoute.self) { route in
                    route
                        .environment(cacheItemListModel)
                        .environment(deviceRotationModel)
                        .environment(listModel)
                        .environment(root.searchModel)
                        .onDisappear {
                            listModel.resetListSelection()
                            listModel.update(selection: Set())
                        }
                }
        } detail: {
            Group {
                if let selected = listModel.selected {
                    PhotoRoute.detail(selected)
                }
            }
            .navigationDestination(for: PhotoRoute.self) { route in
                route
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
        .onChange(of: listMode, initial: true) {
            listModel.listMode <=> listMode
        }
        .onChange(of: listModel.listMode) {
            listMode <=> listModel.listMode
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
            root.currentSelectedItemId = listModel.selected
            if let itemId = listModel.selected {
                route <=> .detail(itemId)
            } else {
                route <=> nil
            }
        }
        .onNavigationReceive { (route: PhotoRoute, navigator) in
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
    @Previewable @Query var models: [PhotoDataModel]

    ManagedNavigationStack {
        PhotoRootView(withoutNavigation: true)
            .environment(TabTitleModel())
            .environment(DeviceRotationModel())
    }
}


#Preview("Split", traits: .mockData) {
    @Previewable @Query var models: [PhotoDataModel]

    PhotoRootView(withoutNavigation: false)
        .environment(TabTitleModel())
        .environment(DeviceRotationModel())
#if os(macOS)
        .frame(width: 800, height: 600)
#endif
}
