// @copyright André Trettin

import CoreExternalRPG
import CoreRPG
import SwiftData
import SwiftUI

struct AudioRootNewView: View {
    let withoutNavigation: Bool
    
    @Environment(AudioRootModel.self) private var root

    @SceneStorage("AudioNewRoute") private var route: ItemRootRoute?
    @SceneStorage("AudioDisplayModel") private var displayMode: ListDisplayModel.DisplayMode = .medium
    @SceneStorage("AudioListModel") private var listMode: ListDisplayModel.ListMode = .list

    var body: some View {
        ItemRootView(root: root, withoutNavigation: withoutNavigation, displayMode: $displayMode, listMode: $listMode, route: $route)
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
