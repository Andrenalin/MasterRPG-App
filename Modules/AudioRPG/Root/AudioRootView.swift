// @copyright André Trettin

import CoreExternalRPG
import CoreRPG
import SwiftData
import SwiftUI

struct AudioRootView: View {
    let withoutNavigation: Bool
    
    @Environment(AudioRootModel.self) private var root

    @SceneStorage("AudioRoute") private var route: AudioRoute?
    @SceneStorage("AudioDisplayModel") private var displayMode: ListModel.DisplayMode = .medium
    @SceneStorage("AudioListModel") private var listMode: ListModel.ListMode = .list

    var body: some View {
        RootView(module: AudioDataModel.typeId, listModel: root.listModel, displayMode: $displayMode, listMode: $listMode, withoutNavigation: withoutNavigation, route: $route) {
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
    @Previewable @Query var models: [AudioDataModel]

    ManagedNavigationStack {
        AudioRootView(withoutNavigation: true)
    }
}


#Preview("Split", traits: .mockData) {
    @Previewable @Query var models: [AudioDataModel]

    AudioRootView(withoutNavigation: false)
}
