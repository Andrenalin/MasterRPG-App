// @copyright André Trettin

import CoreExternalRPG
import CoreRPG
import SwiftData
import SwiftUI

struct DiceRootView: View {
    let withoutNavigation: Bool

    @Environment(DiceRootModel.self) private var root
    
    var body: some View {
        ItemRootView(root: root.rootController, withoutNavigation: withoutNavigation) {
            DetailRootView(selectedId: nil)
        }
        .overlay {
            SaveView(root: root)
        }
        .navigationAutoReceive(DiceRoute.self)
    }
}

struct SaveView: View {
    let root: DiceRootModel
    
    @SceneStorage("DiceRoute") private var route: ItemRootRoute?
    @SceneStorage("DiceDisplayModel") private var displayMode: ListDisplayModel.DisplayMode = .medium
    @SceneStorage("DiceListModel") private var listMode: ListDisplayModel.ListMode = .list

    var body: some View {
        let _ = Self._printChanges()

        Color.clear
            .applyItemRootRoute(listControllable: root.listControllable, route: $route)
            .syncListDisplay(listControllable: root.listControllable, displayMode: $displayMode, listMode: $listMode)
    }
}

#Preview("Small", traits: .mockData) {
    ManagedNavigationStack {
        DiceRootView(withoutNavigation: true)
    }
}


#Preview("Split", traits: .mockData) {
    DiceRootView(withoutNavigation: false)
}
