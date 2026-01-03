// @copyright André Trettin

import CoreRPG
import SwiftUI

struct MapEditWindow: View {
    let itemId: UUID?

    var body: some View {
        if let itemId {
            RootEditCanvasMap(itemId: itemId)
        } else {
            ContentUnavailableView(String(localized: "No map item is selected").localizedString, image: NetworkModules.map.icon)
        }
    }
}

#Preview(traits: .mockData) {
    @Previewable @Environment(MapRootModel.self) var root
    
    MapEditWindow(itemId: root.editController.editorModel.currentItemId)
        .onAppear {
            root.editController.setCurrentItem(to: ItemRowTreeModel(itemId: root.itemController.itemDataModel.items[0], typeId: .map))
        }
        .environment(DropPinModel())
}
