// @copyright André Trettin

import CoreExternalRPG
import CoreRPG
import SwiftData
import SwiftUI

struct PhotoRootView: View {
    let withoutNavigation: Bool

    @Environment(PhotoRootModel.self) private var root
    
    var body: some View {
        let _ = Self._printChanges()
        
        ItemRootView(root: root.rootController, withoutNavigation: withoutNavigation) {
            DetailRootView()
        }
        .overlay {
            SaveView(root: root)
        }
    }
}

struct SaveView: View {
    let root: PhotoRootModel
    
    @SceneStorage("PhotoRoute") private var route: ItemRootRoute?
    @SceneStorage("PhotoDisplayModel") private var displayMode: ListDisplayModel.DisplayMode = .medium
    @SceneStorage("PhotoListModel") private var listMode: ListDisplayModel.ListMode = .list

    var body: some View {
        let _ = Self._printChanges()

        Color.clear
            .applyItemRootRoute(listControllable: root.listControllable, route: $route)
            .syncListDisplay(listControllable: root.listControllable, displayMode: $displayMode, listMode: $listMode)
    }
}

//#Preview("Small", traits: .mockData) {
//    ManagedNavigationStack {
//        PhotoRootView(withoutNavigation: true)
//    }
//}


#Preview("Split", traits: .mockData) {
    PhotoRootView(withoutNavigation: false)
}
