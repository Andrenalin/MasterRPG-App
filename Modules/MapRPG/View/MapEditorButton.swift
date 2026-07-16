// @copyright André Trettin

import CoreRPG
import SwiftUI

struct MapEditorButton: View {
    let model: MapModel

    @Environment(\.navigator) private var navigator
    @Environment(ScenesManager.self) private var scenesManager
    @Environment(MapRootModel.self) private var root

    var body: some View {
        Button {
#if os(visionOS) || os(macOS)
            root.editController.editorModel.sheetEditorModel.itemId = model.id
            scenesManager.openWindow(.mapEditor)
#else
            navigator.navigate(to: MapEditorRoute.mapEditor(model.id))
#endif
        } label: {
            Label {
                Text("Map Editor", bundle: .module)
            } icon: {
                Image(systemName: "mappin.and.ellipse")
            }
        }
    }
}

#Preview(traits: .mockData) {
    MapEditorButton(model: .preview)
}
