// @copyright André Trettin

import CoreExternalRPG
import CoreRPG
import SwiftData
import SwiftUI

struct PdfRootView: View {
    @Environment(PdfRootModel.self) private var root
    
    var body: some View {
        let _ = Self._printChanges()
        
        ItemRootView(root: root.rootController)
            .navigationAutoReceive(PdfRoute.self)
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

#Preview(traits: .mockData) {
    ManagedNavigationStack {
        PdfRootView()
    }
}
