// @copyright André Trettin

import CoreRPG
import CoreExternalRPG
import SwiftUI

struct PdfRootView: View {
    @Environment(PdfRootModel.self) private var root

    var body: some View {
        let _ = Self._printChanges()
        ItemRootView(root: root.rootController)
            .overlay {
                SaveView(root: root)
            }
    }
}

struct SaveView: View {
    let root: PdfRootModel
    
    @SceneStorage("PdfRoute") private var route: PdfRoute?
    @SceneStorage("PdfDisplayModel") private var displayMode: ListDisplayModel.DisplayMode = .medium
    @SceneStorage("PdfListModel") private var listMode: ListDisplayModel.ListMode = .list

    var body: some View {
        let _ = Self._printChanges()

        Color.clear
            .applyItemRootRoute(listControllable: root.folderListController, route: $route)
            .syncListDisplay(listControllable: root.folderListController, displayMode: $displayMode, listMode: $listMode)
    }
}

#Preview(traits: .mockData) {
    ManagedNavigationStack {
        PdfRootView()
    }
}
