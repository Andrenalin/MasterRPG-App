// @copyright André Trettin

import CoreRPG

import SwiftData
import SwiftUI

struct DiceRootView: View {
    @Environment(DiceRootModel.self) private var root
    
    var body: some View {
        ItemRootView(root: root.rootController)
            .overlay {
                SaveView(root: root)
            }
    }
}

struct SaveView: View {
    let root: DiceRootModel
    
    @SceneStorage("DiceRoute") private var route: DiceRoute?
    @SceneStorage("DiceDisplayModel") private var displayMode: ListDisplayModel.DisplayMode = .medium
    @SceneStorage("DiceListModel") private var listMode: ListDisplayModel.ListMode = .list

    var body: some View {
        let _ = Self._printChanges()

        Color.clear
            .applyItemRootRoute(listControllable: root.folderListController, route: $route)
            .syncListDisplay(listControllable: root.folderListController, displayMode: $displayMode, listMode: $listMode)
    }
}

#Preview(traits: .mockData) {
    ManagedNavigationStack {
        DiceRootView()
    }
}
