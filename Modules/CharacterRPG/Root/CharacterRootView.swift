// @copyright André Trettin

import CoreExternalRPG
import CoreRPG
import SwiftData
import SwiftUI

struct CharacterRootView: View {
    let withoutNavigation: Bool

    @Environment(CharacterRootModel.self) private var root

    var body: some View {
        let _ = Self._printChanges()
        
        ItemRootView(root: root.rootController, withoutNavigation: withoutNavigation)
            .navigationAutoReceive(CharacterRoute.self)
            .overlay {
                SaveView(root: root)
            }
    }
}

struct SaveView: View {
    let root: CharacterRootModel
    
    @SceneStorage("CharacterRoute") private var route: ItemRootRoute?
    @SceneStorage("CharacterDisplayModel") private var displayMode: ListDisplayModel.DisplayMode = .medium
    @SceneStorage("CharacterListModel") private var listMode: ListDisplayModel.ListMode = .list

    var body: some View {
        let _ = Self._printChanges()

        Color.clear
            .applyItemRootRoute(listControllable: root.listControllable, route: $route)
            .syncListDisplay(listControllable: root.listControllable, displayMode: $displayMode, listMode: $listMode)
    }
}

#Preview("Embed", traits: .mockData) {
    ManagedNavigationStack {
        CharacterRootView(withoutNavigation: true)
    }
}

#Preview("Split", traits: .mockData) {
    CharacterRootView(withoutNavigation: false)
}

