// @copyright André Trettin

import CoreRPG
import SwiftUI

struct SaveView: View {
    let root: GeneratorRootModel
    private let restoresState: Bool

    init(root: GeneratorRootModel, restoresState: Bool = true) {
        self.root = root
        self.restoresState = restoresState
    }

    var body: some View {
        if restoresState {
            Color.clear
                .modifier(SaveStateRestorationModifier(root: root))
        } else {
            Color.clear
        }
    }
}

#Preview(traits: .mockData) {
    SaveView(root: .preview, restoresState: false)
}

private struct SaveStateRestorationModifier: ViewModifier {
    let root: GeneratorRootModel

    @SceneStorage("GeneratorRoute") private var route: GeneratorRoute?
    @SceneStorage("GeneratorDisplayModel") private var displayMode: ListDisplayModel.DisplayMode = .regular
    @SceneStorage("GeneratorListModel") private var listMode: ListDisplayModel.ListMode = .list

    func body(content: Content) -> some View {
        content
            .applyItemRootRoute(listControllable: root.folderListController, route: $route)
            .syncListDisplay(
                listControllable: root.folderListController,
                displayMode: $displayMode,
                listMode: $listMode
            )
            .onChange(of: root.navigationModel.selectedItemId) {
                // Surface deep-linked selections written by `WindowRouter` into the local route.
                if let itemId = root.navigationModel.selectedItemId {
                    route <=> GeneratorRoute.detail(itemId)
                    if root.folderListController.listModel.selectedItemId != itemId {
                        root.folderListController.listModel.set(selectedItemId: itemId)
                    }
                }
            }
    }
}
