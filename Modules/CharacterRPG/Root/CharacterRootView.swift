// @copyright André Trettin

import CoreRPG
import CoreExternalRPG
import SwiftUI

struct CharacterRootView: View {
    @Environment(CharacterRootModel.self) private var root

    var body: some View {
        let _ = Self._printChanges()
        
        ItemRootView(root: root.rootController)
            .overlay {
                SaveView(root: root)
            }
    }
}

struct SaveView: View {
    let root: CharacterRootModel
    
    @SceneStorage("CharacterRoute") private var route: CharacterRoute?
    @SceneStorage("CharacterDisplayModel") private var displayMode: ListDisplayModel.DisplayMode = .medium
    @SceneStorage("CharacterListModel") private var listMode: ListDisplayModel.ListMode = .list

    var body: some View {
        let _ = Self._printChanges()

        Color.clear
            .applyItemRootRoute(listControllable: root.folderListController, route: $route)
            .syncListDisplay(listControllable: root.folderListController, displayMode: $displayMode, listMode: $listMode)
    }
}

#Preview(traits: .mockData) {
    ManagedNavigationStack {
        CharacterRootView()
    }
}

