// @copyright André Trettin

import CoreExternalRPG
import CoreRPG
import SwiftData
import SwiftUI

struct SpaceRootView: View {
    let withoutNavigation: Bool

    @Environment(SpaceRootModel.self) private var root

    @SceneStorage("SpaceRoute") private var route: SpaceRoute?
    @SceneStorage("SpaceDisplayModel") private var displayMode: ListModel.DisplayMode = .medium
    @SceneStorage("SpaceListModel") private var listMode: ListModel.ListMode = .list
    
    var body: some View {
        RootView(module: SpaceDataModel.typeId, listModel: root.listModel, displayMode: $displayMode, listMode: $listMode, withoutNavigation: withoutNavigation, route: $route) {
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

