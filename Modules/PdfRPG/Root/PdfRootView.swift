// @copyright André Trettin

import CoreExternalRPG
import CoreRPG
import SwiftData
import SwiftUI

struct PdfRootView: View {
    let withoutNavigation: Bool

    @Environment(PdfRootModel.self) private var root
    
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
    let root: PdfRootModel
    
    @SceneStorage("PdfRoute") private var route: ItemRootRoute?
    @SceneStorage("PdfDisplayModel") private var displayMode: ListDisplayModel.DisplayMode = .medium
    @SceneStorage("PdfListModel") private var listMode: ListDisplayModel.ListMode = .list

    var body: some View {
        let _ = Self._printChanges()

        Color.clear
            .applyItemRootRoute(listControllable: root.listControllable, route: $route)
            .syncListDisplay(listControllable: root.listControllable, displayMode: $displayMode, listMode: $listMode)
    }
}

#Preview("Small", traits: .mockData) {
    ManagedNavigationStack {
        PdfRootView(withoutNavigation: true)
    }
}


#Preview("Split", traits: .mockData) {
    PdfRootView(withoutNavigation: false)
}
