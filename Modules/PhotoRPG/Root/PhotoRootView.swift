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
    @SceneStorage("PhotoListModel") private var listMode: ListModel.ListMode = .list

    var body: some View {
        RootView(module: PhotoDataModel.typeId, listModel: root.listModel, displayMode: $displayMode, listMode: $listMode, withoutNavigation: withoutNavigation, route: $route) {
            .detail($0)
        } detailId: {
            switch $0 {
            case .detail(let itemId): itemId
            }
        } list: {
            ListView()
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
