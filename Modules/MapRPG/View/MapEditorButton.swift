// @copyright André Trettin

import CoreRPG
import SwiftUI
import TipKit

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
            MasterRPGTips.recordMapEditorOpened()
        } label: {
            Label {
                Text("Map Editor", bundle: .module)
            } icon: {
                Image(systemName: "mappin.and.ellipse")
            }
        }
        .popoverTip(MasterRPGTips.openMapEditor)
#if os(iOS)
        // Without a photo the iOS editor cover renders empty (no toolbar to dismiss it).
        .disabled(model.photoId == nil)
#endif
    }
}

#Preview(traits: .mockData) {
    MapEditorButton(model: .preview)
}
