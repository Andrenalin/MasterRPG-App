// @copyright André Trettin

import CoreExternalRPG
import CoreRPG
import SwiftData
import SwiftUI

struct DiceRootView: View {
    let withoutNavigation: Bool

    @Environment(DiceRootModel.self) private var root
    
    @SceneStorage("DiceRoute") private var route: DiceRoute?
    @SceneStorage("DiceDisplayModel") private var displayMode: ListModel.DisplayMode = .medium
    @SceneStorage("DiceListModel") private var listMode: ListModel.ListMode = .list

    var body: some View {
        RootView(module: DiceDataModel.typeId, listModel: root.listModel, displayMode: $displayMode, listMode: $listMode, withoutNavigation: withoutNavigation, route: $route) {
            .detail($0)
        } detailId: {
            switch $0 {
            case .detail(let itemId): itemId
            }
        } list: {
            ListView()
        }
        .environment(root.listModel)
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
