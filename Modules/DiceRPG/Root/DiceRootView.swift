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
            CoreRPG.DetailRootView {
            } editor: {
                if let model {
#if os(macOS)
                    ScrollView {
                        detailEditorView(model: model)
                    }
#else
                    
                    detailEditorView(model: model)
                        .padding(.horizontal, -20)
#endif
                }
            }
        }
        .overlay {
            SaveView(root: root)
        }
    }
    
    var model: DiceConfigDataModel? {
        root.itemController.model(for: root.listControllable.listModel.selectedItemId)
    }
    
    func detailEditorView(model: DiceConfigDataModel) -> some View {
        Form {
            DiceEditor(model: model)
            DiceOptionEditor(model: model)
            CoupEditor(model: model)
            FumbleEditor(model: model)
            RerollEditor(model: model)
            SpecialOptionEditor(model: model)
        }
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
    @Previewable @Query var models: [DiceDataModel]

    ManagedNavigationStack {
        DiceRootView(withoutNavigation: true)
    }
}


#Preview("Split", traits: .mockData) {
    @Previewable @Query var models: [DiceDataModel]

    DiceRootView(withoutNavigation: false)
}
