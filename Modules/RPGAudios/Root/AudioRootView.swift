// @copyright André Trettin

import CoreExternalRPG
import AndrenalinKit
import SwiftUI

struct AudioRootView: View {
    @Environment(AudioRoot.self) private var root

    var body: some View {
        let _ = Self._printChanges()
        ItemRootView(root: root.rootController)
            .overlay {
                SaveView(root: root)
            }
    }
}

struct SaveView: View {
    let root: AudioRoot
    
    @SceneStorage("AudioRoute") private var route: AudioRoute?
    @SceneStorage("AudioDisplayModel") private var displayMode: ListDisplayModel.DisplayMode = .medium
    @SceneStorage("AudioListModel") private var listMode: ListDisplayModel.ListMode = .list

    var body: some View {
        let _ = Self._printChanges()

        Color.clear
            .applyItemRootRoute(listControllable: root.folderListController, route: $route)
            .syncListDisplay(listControllable: root.folderListController, displayMode: $displayMode, listMode: $listMode)
    }
}

#Preview(traits: .mockData) {
    ManagedNavigationStack {
        AudioRootView()
    }
}
