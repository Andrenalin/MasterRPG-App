// @copyright André Trettin

import CoreExternalRPG
import CoreRPG
import SwiftData
import SwiftUI

struct AudioRootView: View {
    let withoutNavigation: Bool

    @SceneStorage("AudioRoute") private var photoRoute: AudioRoute?
    @SceneStorage("AudioDisplayModel") private var displayMode: ListModel.DisplayMode = .medium

    @State private var cacheItemListModel = CacheItemListModel()
    @State private var listModel = ListModel()
    @State private var searchModel = SearchModel()

    var body: some View {
        RootView(module: .audio, listModel: listModel, withoutNavigation: withoutNavigation, list: {
            ListView()
                .navigationDestination(for: AudioRoute.self) { route in
                    route
                        .environment(cacheItemListModel)
                        .onDisappear {
                            listModel.resetListSelection()
                            listModel.update(selection: Set())
                        }
                }
        }, detail: {
            if let selected = listModel.selected {
                AudioRoute.detail(selected)
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
        .onChange(of: photoRoute, initial: true) {
            if let route = photoRoute {
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
                photoRoute <=> .detail(itemId)
            } else {
                photoRoute <=> nil
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
