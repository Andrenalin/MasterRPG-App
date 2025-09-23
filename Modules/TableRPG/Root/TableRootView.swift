// @copyright André Trettin

import CoreExternalRPG
import CoreRPG
import SwiftData
import SwiftUI

struct TableRootView: View {
    let withoutNavigation: Bool

    @Environment(TableRootModel.self) private var root

    var body: some View {
        let _ = Self._printChanges()
        
        ItemRootView(root: root.rootController, withoutNavigation: withoutNavigation)
            .navigationAutoReceive(TableRoute.self)
            .overlay {
                SaveView(root: root)
            }
    }
}

struct SaveView: View {
    let root: TableRootModel
    
    @SceneStorage("TableRoute") private var route: ItemRootRoute?
    @SceneStorage("TableDisplayModel") private var displayMode: ListDisplayModel.DisplayMode = .medium
    @SceneStorage("TableListModel") private var listMode: ListDisplayModel.ListMode = .list

    var body: some View {
        let _ = Self._printChanges()

        Color.clear
            .applyItemRootRoute(listControllable: root.listControllable, route: $route)
            .syncListDisplay(listControllable: root.listControllable, displayMode: $displayMode, listMode: $listMode)
    }
}

#Preview("Embed", traits: .mockData) {
    ManagedNavigationStack {
        TableRootView(withoutNavigation: true)
    }
}

#Preview("Split", traits: .mockData) {
    TableRootView(withoutNavigation: false)
}

