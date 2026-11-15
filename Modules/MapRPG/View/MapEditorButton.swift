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
            MapEditorKind.map.open(model: model, root: root, navigator: navigator, scenesManager: scenesManager)
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
