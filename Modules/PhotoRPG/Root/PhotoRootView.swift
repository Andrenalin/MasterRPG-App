// @copyright André Trettin

import CoreExternalRPG
import CoreRPG
import SwiftData
import SwiftUI

struct PhotoRootView: View {
    let withoutNavigation: Bool

    @Environment(PhotoRootModel.self) private var root
    
    @SceneStorage("PhotoRoute") private var route: PhotoRoute?
    @SceneStorage("PhotoDisplayModel") private var displayMode: ListModel.DisplayMode = .medium

    @State private var cacheItemListModel = CacheItemListModel()
    @State private var listModel = ListModel()
    @State private var searchModel = SearchModel()

    var body: some View {
        RootView(module: PhotoDataModel.typeId, listModel: listModel, withoutNavigation: withoutNavigation, list: {
            ListView()
                .navigationDestination(for: PhotoRoute.self) { route in
                    route
                        .environment(cacheItemListModel)
                        .onDisappear {
                            listModel.resetListSelection()
                            listModel.update(selection: Set())
                        }
                }
        }, detail: {
            if let selected = listModel.selected {
                PhotoRoute.detail(selected)
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
