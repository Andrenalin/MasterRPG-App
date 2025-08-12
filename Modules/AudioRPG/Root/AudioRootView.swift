// @copyright André Trettin

import CoreExternalRPG
import CoreRPG
import SwiftData
import SwiftUI

struct AudioRootView: View {
    let withoutNavigation: Bool
    
    @Environment(AudioRootModel.self) private var root
    @Environment(DeviceRotationModel.self) private var deviceRotationModel

    @SceneStorage("AudioRoute") private var route: AudioRoute?
    @SceneStorage("AudioDisplayModel") private var displayMode: ListModel.DisplayMode = .medium
    @SceneStorage("AudioListModel") private var listMode: ListModel.ListMode = .list

    @State private var cacheItemListModel = CacheItemListModel()

    var listModel: ListModel {
        root.listModel
    }
    
    var body: some View {
        RootView(module: AudioDataModel.typeId, listModel: root.listModel, withoutNavigation: withoutNavigation, route: route, displayMode: $displayMode, listMode: $listMode) {
            ListView(listModel: root.listModel)
        } detail: {
            Group {
                if let selected = listModel.selected {
                    AudioRoute.detail(selected)
                }
            }
        }
        .environment(cacheItemListModel)
        .environment(root.listModel)
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
        .onNavigationReceive { (route: AudioRoute, navigator) in
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
    @Previewable @Query var models: [AudioDataModel]

    ManagedNavigationStack {
        AudioRootView(withoutNavigation: true)
            .environment(TabTitleModel())
            .environment(DeviceRotationModel())
    }
}


#Preview("Split", traits: .mockData) {
    @Previewable @Query var models: [AudioDataModel]

    AudioRootView(withoutNavigation: false)
        .environment(TabTitleModel())
        .environment(DeviceRotationModel())
#if os(macOS)
        .frame(width: 800, height: 600)
#endif
}
