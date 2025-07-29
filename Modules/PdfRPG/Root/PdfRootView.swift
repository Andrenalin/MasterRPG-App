// @copyright André Trettin

import CoreExternalRPG
import CoreRPG
import SwiftData
import SwiftUI

struct PdfRootView: View {
    let withoutNavigation: Bool

    @Environment(PdfRootModel.self) private var root
    @Environment(DeviceRotationModel.self) private var deviceRotationModel
    
    @SceneStorage("PdfRoute") private var route: PdfRoute?
    @SceneStorage("PdfDisplayModel") private var displayMode: ListModel.DisplayMode = .medium

    @State private var cacheItemListModel = CacheItemListModel()

    var listModel: ListModel {
        root.listModel
    }
    
    var body: some View {
        RootView(module: PdfDataModel.typeId, listModel: listModel, withoutNavigation: withoutNavigation) {
            ListView()            
                .navigationDestination(for: PdfRoute.self) { route in
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
                PdfRoute.detail(selected)
            }
        }
        .environment(cacheItemListModel)
        .environment(listModel)
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
        .onNavigationReceive { (route: PdfRoute, navigator) in
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
    @Previewable @Query var models: [PdfDataModel]

    ManagedNavigationStack {
        PdfRootView(withoutNavigation: true)
            .environment(TabTitleModel())
            .environment(DeviceRotationModel())
    }
}


#Preview("Split", traits: .mockData) {
    @Previewable @Query var models: [PdfDataModel]

    PdfRootView(withoutNavigation: false)
        .environment(TabTitleModel())
        .environment(DeviceRotationModel())
#if os(macOS)
        .frame(width: 800, height: 600)
#endif
}
