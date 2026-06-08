// @copyright André Trettin

import CoreRPG
import SwiftUI

struct MapEditWindow: View {
    let isTileEditor: Bool
    @Environment(MapRootModel.self) private var root
    
    var body: some View {
        Group {
            if let itemId = root.editController.sheetEditorModel.itemId {
                RootEditCanvasMap(itemId: itemId, isTileEditor: isTileEditor)
                    .id(itemId)
            } else {
                ContentUnavailableView(String(localized: "No map item is selected", bundle: .module).localizedString, image: root.configurable.module.icon)
            }
        }
    }
}

#Preview(traits: .mockData) {
    @Previewable @Environment(MapRootModel.self) var root
    
    MapEditWindow(isTileEditor: false)
        .onAppear {
            root.editController.setCurrentItem(to: ItemRowTreeModel(itemId: root.itemController.itemDataModel.items[0], typeId: .map))
        }
        .environment(DropPinModel())
}
