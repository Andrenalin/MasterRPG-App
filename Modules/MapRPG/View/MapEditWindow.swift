// @copyright André Trettin

import CoreRPG
import SwiftUI

struct MapEditWindow: View {
    let editController: EditController

    @Environment(MapRootModel.self) private var root

    var body: some View {
        Group {
            if root.editController.editorModel.currentItemId != nil {
                RootEditCanvasMap(editController: editController)
                    //.navigationTitle(root.editController.model.name)
            } else {
                ContentUnavailableView("No map item is selected", image: NetworkModules.map.icon)
                //Text("No Map Item is selected for editing", bundle: .module)
            }
        }
    }
}

#Preview(traits: .mockData) {
    @Previewable @Environment(MapRootModel.self) var root
    
    Group {
        if root.editController.editorModel.currentItemId != nil {
            MapEditWindow(editController: root.editController)
        } else {
            Text("Wait")
                .onAppear {
                    root.editController.setCurrentItem(to: ItemRowTreeModel(itemId: root.itemController.itemDataModel.items[0], typeId: .map))
                }
        }
    }
    .environment(DropPinModel())
}
