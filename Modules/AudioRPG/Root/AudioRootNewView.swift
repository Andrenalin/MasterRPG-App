// @copyright André Trettin

import CoreExternalRPG
import CoreRPG
import SwiftData
import SwiftUI

struct AudioRootNewView: View {
    let withoutNavigation: Bool
    
    @Environment(AudioRootModel.self) private var root

    var body: some View {
        let _ = Self._printChanges()
        
        ItemRootView(root: root.rootController, withoutNavigation: withoutNavigation)
            .overlay {
                SaveView(root: root)
            }
    }
}

struct SaveView: View {
    let root: AudioRootModel
    
    @SceneStorage("AudioNewRoute") private var route: ItemRootRoute?
    @SceneStorage("AudioDisplayModel") private var displayMode: ListDisplayModel.DisplayMode = .medium
    @SceneStorage("AudioListModel") private var listMode: ListDisplayModel.ListMode = .list

    var body: some View {
        let _ = Self._printChanges()

        Color.clear
            .applyItemRootRoute(listControllable: root.listControllable, route: $route)
            .syncListDisplay(listControllable: root.listControllable, displayMode: $displayMode, listMode: $listMode)
    }
}

#Preview("Small", traits: .mockCoreData) {
    ManagedNavigationStack {
        AudioRootNewView(withoutNavigation: true)
    }
}


#Preview("Split", traits: .mockCoreData) {
    AudioRootNewView(withoutNavigation: false)
}
