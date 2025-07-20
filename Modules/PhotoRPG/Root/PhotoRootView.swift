// @copyright André Trettin

import CoreExternalRPG
import CoreRPG
import SwiftData
import SwiftUI

struct PhotoRootView: View {
    let withoutNavigation: Bool

    @State private var cacheItemListModel = CacheItemListModel()
    @State private var listModel = ListModel()
    @State private var searchModel = SearchModel()
    @State private var selectionModel = ListSelectionModel<PhotoDataModel>()


    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
    var body: some View {
        RootView(module: .photo, selectionModel: selectionModel, withoutNavigation: withoutNavigation, list: {
            ListView()
                .applyIf(withoutNavigation) { content in
                    content
                        .navigationDestination(for: PhotoRoute.self) { route in
                            route
                                .environment(cacheItemListModel)
                        }
                        .onChange(of: listModel.selected) {
                            guard listModel.selected != nil else { return }
                            listModel.selected = nil
                        }
                }
        }, detail: {
            if let selected = selectionModel.selectedItem {
                DetailView(model: selected)
            }
        })
        .environment(cacheItemListModel)
        .environment(listModel)
        .environment(searchModel)
        .onNavigationReceive { (route: PhotoRoute, navigator) in
            switch route {
            case .detail(let itemId):
                if selectionModel.selectedItem?.id == itemId {
                    return .immediately
                }
                listModel.update(listSelection: Set(arrayLiteral: itemId))
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
